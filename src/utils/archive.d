module utils.archive;

import std.stream;

import gzip = utils.gzip;
import utils.output;
import utils.configfile;

//write an "archive", the only point is to support streaming + compression
//could be changed to output the zip or tar format
//tar would contain compressed file (instead of being a tar.gz)
class ZWriter {
    private {
        gzip.GZWriter mWriter;
        Stream mOut;
    }

    this(Stream s) {
        assert (!!s);
        mOut = s;
        mWriter = new gzip.GZWriter(&doWrite);
    }

    private void doWrite(ubyte[] data) {
        mOut.writeExact(data.ptr, data.length);
    }

    void write(ubyte[] data) {
        mWriter.write(data);
    }
    void write_ptr(void* ptr, size_t size) {
        write(cast(ubyte[])(ptr[0..size]));
    }

    private class MyOutput : OutputHelper {
        override void writeString(char[] str) {
            this.outer.write(cast(ubyte[])str);
        }
    }

    void writeConfigFile(ConfigNode n) {
        n.writeFile(new MyOutput());
    }

    void close() {
        mWriter.finish();
        mWriter = null;
        mOut.close();
        mOut = null;
    }
}

class ZReader {
    private {
        gzip.GZReader mReader;
        Stream mIn;
        ubyte[] mBuffer;
    }

    this(Stream s) {
        assert (!!s);
        mIn = s;
        mBuffer.length = 64*1024;
        mReader = new gzip.GZReader(&doRead);
    }

    private ubyte[] doRead() {
        uint res = mIn.read(mBuffer);
        if (res < mBuffer.length) {
            assert (mIn.eof());
        }
        return mBuffer[0..res];
    }

    ubyte[] read(ubyte[] data) {
        return mReader.read(data);
    }
    void read_ptr(void* ptr, size_t size) {
        ubyte[] res = read(cast(ubyte[])(ptr[0..size]));
        if (res.length != size)
            throw new Exception("read error: not enough data available");
    }

    ConfigNode readConfigFile() {
        //xxx: this is a major wtf: I don't know how much data to read (because
        //     I don't store the size), so I read everything lol
        //it's also inefficient
        //how to fix: write the size somewhere (like .zip does)
        ubyte[] bla, res;
        bla.length = 64*1024;
        while (bla.length) {
            bla = read(bla);
            res ~= bla;
        }
        auto f = new ConfigFile(cast(char[])res, "zreader", null);
        return f.rootnode();
    }

    void close() {
        mReader.finish();
        mReader = null;
        mIn.close();
        mIn = null;
    }
}

class TarArchive {
    private {
        Stream mFile;
        Entry[] mEntries;
        bool mReading;

        struct Entry {
            char[] name;
            ulong size;
            ulong offset; //the the file header
            bool writing;
        }

        //http://en.wikipedia.org/wiki/Tar_(file_format)
        struct TarHeader {
            char[100] filename;
            char[8] mode;
            char[8] user, group;
            char[12] filesize;
            char[12] moddate;
            char[8] checksum;
            char[1] link;
            char[100] linkedfile;
            char[255] pad;

            char[] getchecksum() {
                TarHeader copy = *this;
                copy.checksum[] = ' ';
                char* ptr = cast(char*)&copy;
                int s = 0;
                for (int n = 0; n < copy.sizeof; n++) {
                    s += cast(ubyte)ptr[n];
                }
                auto res = str.format("0%05o", s);
                res ~= "\0 ";
                assert (res.length == 8);
                return res;
            }

            bool iszero() {
                char* ptr = cast(char*)this;
                for (int n = 0; n < TarHeader.sizeof; n++) {
                    if (ptr[n] != '\0')
                        return false;
                }
                return true;
            }
        }

        static assert (TarHeader.sizeof == 512);
    }

    //read==true: read mode, else write mode
    //read and write mode are completely separate, don't mix
    this(Stream f, bool read) {
        if (read)
            assert(f.readable);
        else
            assert(f.writeable);
        assert (mFile.seekable);
        mReading = read;
        if (mReading) {
            while (!mFile.eof()) {
                Entry e;
                TarHeader h;
                e.offset = mFile.position();
                mFile.readExact(&h, h.sizeof);
                if (h.iszero()) //eof
                    break;
                //"so relying on the first white space trimmed six digits for
                // checksum yields better compatibility."
                if (h.getchecksum()[0..6] != h.checksum[0..6])
                    throw new Exception("tar error");
                char[] getField(char[] f) {
                    assert (f.length > 0);
                    //else we had a buffer overflow with toString
                    //xxx: utf safety?
                    if (h.filename[$-1] != '\0')
                        throw new Exception("tar error");
                    return str.toString(&f[0]);
                }
                e.name = getField(h.filename).dup;
                char[] sz = getField(h.filesize);
                //parse octal by myself, Phobos is too stupid to do it
                ulong isz = 0;
                while (sz.length) {
                    int digit = sz[0] - '0';
                    if (digit < 0 || digit > 7)
                        throw new Exception("tar error");
                    isz = isz*8 + digit;
                    sz = sz[1..$];
                }
                e.size = isz;
                //normal file?
                if (h.link[0] == '0' || h.link[0] == '\0')
                    mEntries ~= e;
                mFile.position = mFile.position + e.size;
                align512();
            }
        }
    }

    ZReader openReadStream(char[] name, bool can_fail = false) {
        name = name ~ ".gz";
        foreach (Entry e; mEntries) {
            if (e.name == name) {
                auto s = new SliceStream(mFile, e.offset + 512,
                    e.offset + 512 + e.size);
                s.nestClose = false;
                return new ZReader(s);
            }
        }
        if (can_fail)
            return null;
        throw new Exception("tar entry not found");
    }

    static ubyte[512] waste;

    //NOTE: sequential writing is assumed, e.g. only one stream at a time
    ZWriter openWriteStream(char[] name) {
        finishLastFile();
        Entry e;
        e.name = name ~ ".gz";
        e.offset = mFile.position();
        e.writing = true;
        mEntries ~= e;
        mFile.writeExact(waste.ptr, waste.sizeof);
        auto s = new SliceStream(mFile, mFile.position());
        s.nestClose = false; //stupid phobos, this took me some time
        auto res = new ZWriter(s);
        assert (mFile.seekable);
        return res;
    }

    private void finishLastFile() {
        assert (mFile.seekable);
        if (!mEntries.length)
            return;
        Entry* e = &mEntries[$-1];
        if (!e.writing)
            return;
        e.writing = false;
        //SliceStream doesn't set parent seek position
        //so use the size to find out how much was written
        mFile.position = mFile.size;
        e.size = mFile.position() - (e.offset + 512);
        align512();
    }

    private void align512() {
        //aw, unlike unix streams, seeking beyond the end is not allowed?
        ulong npos = (mFile.position() + 511) & ~511UL;
        if (npos <= mFile.size()) {
            mFile.position = npos;
        } else {
            if (mReading)
                throw new Exception("tar error (file unaligned)");
            ulong todo = npos - mFile.position();
            assert (todo < 512);
            mFile.writeExact(&waste[0], todo);
        }
        assert ((mFile.position & 511) == 0);
    }

    void close() {
        if (!mReading) {
            finishLastFile();
            //write all headers
            foreach (Entry e;  mEntries) {
                TarHeader h;
                (cast(char*)&h)[0..h.sizeof] = '\0';
                h.filename[0..e.name.length] = e.name;
                char[] sz = str.format("%011o", e.size) ~ '\0';
                assert (sz.length == 12);
                h.filesize[] = sz;
                h.link[0] = '0';
                h.mode[] = "0000660\0"; //rw-rw----
                h.checksum[] = h.getchecksum();
                mFile.position = e.offset;
                mFile.writeExact(&h, h.sizeof);
            }
            //close header, twice
            mFile.position = mFile.size;
            for (int n = 0; n < 2; n++)
                mFile.writeExact(waste.ptr, waste.sizeof);
        }
        mFile.close();
        mFile = null;
    }
}
