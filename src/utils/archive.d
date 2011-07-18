module utils.archive;

import utils.stream;

import gzip = utils.gzip;
import utils.configfile;
import utils.misc;
import utils.path;


//shared interface for archive readers (currently: tar and zip)
interface ArchiveReader {
    //does archive contain a file (not directory)
    bool fileExists(VFSPath name);
    //does archive contain a directory (may only return full directories)
    bool pathExists(VFSPath name);
    //open a file for reading
    Stream openReadStream(VFSPath name, bool can_fail = false);
    //iterate over files (not directories)
    int opApply(int delegate(ref VFSPath file) del);
    //close archive (you should close open streams first)
    void close();
}

/+
//now what is so hard about that, tango guys? (ZipFolder throws AVs at me)
class ZipArchiveReader : ArchiveReader {
    private {
        struct MyZipEntry {
            ZipEntry entry;
            VFSPath name;
        }

        InputStream mFile;
        ZipReader mReader;
        MyZipEntry[] mEntries;
    }

    //xxx why exactly do we have our own stream interface?
    this(Stream f) {
        auto cs = castStrict!(ConduitStream)(f);
        assert(!!cs.input);
        this(cs.input);
    }

    this(InputStream input) {
        mFile = input;
        mReader = new ZipBlockReader(input);
        //read directory and cache entries (waste of memory, but
        //  ZipBlockReader can only iterate once)
        foreach (entry; mReader) {
            mEntries ~= MyZipEntry(entry.dup, VFSPath(entry.info.name));
        }
    }

    private MyZipEntry* findFile(VFSPath name) {
        //xxx ZIP files store directories, but tango ZipEntry provides no
        //    method to check if it represents a directory
        //    so for now I assume size() == 0 means it is a directory
        foreach (ref e; mEntries) {
            if (e.name == name && e.entry.size() > 0) {
                return &e;
            }
        }
        return null;
    }

    Stream openReadStream(VFSPath name, bool can_fail = false) {
        auto e = findFile(name);
        if (e) {
            debug e.entry.verify();
            return new SeekFixStream(&e.entry.open, e.entry.size());
        }
        if (can_fail)
            return null;
        throw new CustomException("zip entry not found: >"~name.toString~"<");
    }

    bool fileExists(VFSPath name) {
        return findFile(name) !is null;
    }

    bool pathExists(VFSPath name) {
        //search for a file starting with that directory name
        foreach (e; mEntries) {
            if (name.isChild(e.name)) {
                return true;
            }
        }
        return false;
    }

    int opApply(int delegate(ref VFSPath file) del) {
        foreach (e; mEntries) {
            if (e.entry.size() > 0) {
                int res = del(e.name);
                if (res)
                    return res;
            }
        }
        return 0;
    }

    void close()  {
        mReader.close();
        mReader = null;
        mFile.close();
        mFile = null;
        mEntries = null;
    }
}
+/

class TarArchive : ArchiveReader {
    private {
        Stream mFile;
        Entry[] mEntries;
        bool mReading;
        SliceStream mCurrentWriter;

        struct Entry {
            VFSPath name;
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

            string getchecksum() {
                TarHeader copy = this;
                copy.checksum[] = ' ';
                char* ptr = cast(char*)&copy;
                int s = 0;
                for (int n = 0; n < copy.sizeof; n++) {
                    s += cast(ubyte)ptr[n];
                }
                auto res = myformat("0{:o5}", s);
                res ~= "\0 ";
                assert (res.length == 8);
                return res;
            }

            bool iszero() {
                char* ptr = &filename[0];
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
        assert (!!f);
        mFile = f;
        mReading = read;
        if (mReading) {
            while (!mFile.eof()) {
                Entry e;
                TarHeader h;
                e.offset = mFile.position();
                mFile.readExact(cast(ubyte[])(&h)[0..1]);
                if (h.iszero()) //eof
                    break;
                //"so relying on the first white space trimmed six digits for
                // checksum yields better compatibility."
                char[6] hcs = h.checksum[0..6];
                foreach (ref digit; hcs)
                    if (digit == ' ') digit = '0';
                if (h.getchecksum()[0..6] != hcs)
                    throw new CustomException("tar error: CS "~h.getchecksum()[0..6]~" != "~cast(string)hcs);
                const(char)[] getField(in char[] f) {
                    assert (f.length > 0);
                    //else we had a buffer overflow with toString
                    //xxx: utf safety?
                    if (h.filename[$-1] != '\0')
                        throw new CustomException("tar error");
                    return fromStringz(&f[0]);
                }
                e.name = VFSPath(getField(h.filename).idup);
                char[] sz = h.filesize[0..11].dup;
                //parse octal by myself, Phobos is too stupid to do it
                ulong isz = 0;
                while (sz.length) {
                    if (sz[0] == ' ') sz[0] = '0';
                    int digit = sz[0] - '0';
                    if (digit < 0 || digit > 7)
                        throw new CustomException("tar error");
                    isz = isz*8 + digit;
                    sz = sz[1..$];
                }
                e.size = isz;
                //normal file?
                if (h.link[0] == '0' || h.link[0] == '\0') {
                    mEntries ~= e;
                    mFile.position = mFile.position + e.size;
                }
                align512();
            }
        }
    }

    bool fileExists(VFSPath name) {
        foreach (Entry e; mEntries) {
            if (e.name == name) {
                return true;
            }
        }
        return false;
    }

    bool pathExists(VFSPath name) {
        //xxx directories are stored in tar files (h.link == '5'), but I'm too
        //    lazy to change the parsing code above
        //search for a file starting with that directory name
        foreach (Entry e; mEntries) {
            if (name.isChild(e.name)) {
                return true;
            }
        }
        return false;
    }

    int opApply(int delegate(ref VFSPath filename) del) {
        foreach (Entry e; mEntries) {
            int res = del(e.name);
            if (res)
                return res;
        }
        return 0;
    }

    Stream openReadStream(VFSPath name, bool can_fail = false) {
        foreach (Entry e; mEntries) {
            if (e.name == name) {
                auto s = new SliceStream(mFile, e.offset + 512,
                    e.offset + 512 + e.size);
                return s;
            }
        }
        if (can_fail)
            return null;
        throw new CustomException("tar entry not found: >"~name.toString~"<");
    }

    PipeIn openReadStreamCompressed(string name, bool can_fail = false) {
        name = name ~ ".gz";
        auto s = openReadStream(VFSPath(name), can_fail);
        if (!s)
            return PipeIn.Null;
        return gzip.GZReader.Pipe(s.pipeIn(true));
    }

    //open a file by openReadStream() and parse as config file
    ConfigNode readConfigStream(string name) {
        auto r = openReadStreamCompressed(name);
        scope(exit) r.close();
        return ConfigFile.Parse(cast(string)r.readAll(), "?.tar/"~name);
    }

    static ubyte[512] waste;

    private void startEntry(string name) {
        finishLastFile();
        Entry e;
        e.name = VFSPath(name);
        e.offset = mFile.position();
        e.writing = true;
        mEntries ~= e;
        mFile.writeExact(waste);
    }

    //NOTE: sequential writing is assumed, e.g. only one stream at a time
    PipeOut openWriteStream(string name) {
        Stream o = openUncompressed(name ~ ".gz");
        return gzip.GZWriter.Pipe(o.pipeOut(true));
    }

    //NOTE: sequential writing is assumed, e.g. only one stream at a time
    //this does the same as openWriteStream(), but it's uncompressed
    Stream openUncompressed(string name) {
        startEntry(name);
        assert(!mCurrentWriter);
        auto s = new SliceStream(mFile, mFile.position());
        mCurrentWriter = s;
        return s;
    }

    private void finishLastFile() {
        if (!mEntries.length)
            return;
        Entry* e = &mEntries[$-1];
        if (!e.writing)
            return;
        if (mCurrentWriter && mCurrentWriter.source()) {
            //because we can support only one writer at a moment
            throw new CustomException("previous tar sub-file not closed: "
                ~ e.name.toString);
        }
        e.writing = false;
        mCurrentWriter = null;
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
                throw new CustomException("tar error (file unaligned)");
            ulong todo = npos - mFile.position();
            assert (todo < 512);
            mFile.writeExact(waste[0..cast(size_t)todo]);
        }
        assert ((mFile.position & 511) == 0);
    }

    void close() {
        if (!mFile)
            return;
        if (!mReading) {
            finishLastFile();
            //write all headers
            foreach (Entry e;  mEntries) {
                TarHeader h;
                (cast(char*)&h)[0..h.sizeof] = '\0';
                string fname = e.name.get(false);
                h.filename[0..fname.length] = fname;
                string sz = myformat("{:o11}", e.size) ~ '\0';
                assert (sz.length == 12);
                h.filesize[] = sz;
                h.link[0] = '0';
                h.mode[] = "0000660\0"; //rw-rw----
                h.checksum[] = h.getchecksum();
                mFile.position = e.offset;
                mFile.writeExact(cast(ubyte[])(&h)[0..1]);
            }
            //close header, twice
            mFile.position = mFile.size;
            for (int n = 0; n < 2; n++)
                mFile.writeExact(waste);
        }
        mFile.close();
        mFile = null;
    }
}
