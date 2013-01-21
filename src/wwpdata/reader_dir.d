module wwpdata.reader_dir;

import str = utils.string;
import utils.stream;
import utils.misc;
import wwpdata.common;
import wwpdata.reader;
import wwptools.unworms;
import utils.filetools;
import std.path;
import std.stdio;

struct WWPDirEntry {
    uint offset, size;
    string filename;

    static WWPDirEntry read(Stream st) {
        WWPDirEntry ret;
        st.seekRelative(4);
        st.readExact(&ret.offset, 4);
        st.readExact(&ret.size, 4);
        char[255] buf;
        int i;
        do {
            st.readExact(&buf[i],4);
            i += 4;
        } while (buf[i-1] != 0);
        //cut off zeros
        ret.filename = fromStringz(buf.ptr).idup;
        return ret;
    }

    void writeFile(Stream st, string outPath) {
        st.position = offset;
        scope fileOut = Stream.OpenFile(outPath ~ dirSeparator ~ filename, "wb");
        scope(exit) fileOut.close();
        fileOut.pipeOut.copyFrom(st.pipeIn, size);
    }

    //st: the .dir file, same as for read() and writeFile()
    Stream open(Stream st) {
        return new SliceStream(st, offset, offset+size);
    }
}

//same as readDir(), but instead of extracting it, provide the possibility of
//getting sub-streams of the .dir file (thus, needs an object)
class Dir {
    private {
        Stream mStream;
        WWPDirEntry[] mEntries;
    }

    //st must not be closed while this object is used
    this(Stream st) {
        mStream = st;
        mEntries = doReadDir(st);
    }

    this(string filename) {
        //NOTE: file isn't closed; you had to add that to ~this(), but D doesn't
        //   allow this because of the garbage collector destructor rules!
        this(Stream.OpenFile(filename, "rb"));
    }

    //filesystem-like interface, was too lazy to use filesystem.d
    Stream open(string filename) {
        foreach (e; mEntries) {
            if (str.icmp(e.filename, filename) == 0) {
                return e.open(mStream);
            }
        }
        throwError("file within .dir not found: " ~ filename);
        assert(false);
    }

    void close() {
        mStream.close();
    }

    //works exactly like do_unworms, just filename is opened from the .dir-file
    void unworms(string filename, string outputPath) {
        do_unworms(this.open(filename), filename,
            outputPath);
    }

    //works like std.file.listdir(pathname, pattern), on the .dir-filelist
    string[] listdir(string pattern) {
        string[] res;
        foreach (e; mEntries) {
            if (globMatch(e.filename, pattern))
                res ~= e.filename;
        }
        return res;
    }
}

void readDir(Stream st, string outputDir, string fnBase) {
    string outPath = outputDir ~ dirSeparator ~ fnBase;
    trymkdir(outPath);

    auto content = doReadDir(st);

    foreach (c; content) {
        writefln("%s", c.filename);
        c.writeFile(st, outPath);
    }
}

WWPDirEntry[] doReadDir(Stream st) {
    char[4] hdr;
    st.readExact(hdr.ptr, 4);
    assert(hdr == "DIR\x1A");

    uint dataLen;
    st.readExact(&dataLen, 4);

    uint dirPos;
    st.readExact(&dirPos, 4);
    st.position = dirPos+4096+4;

    WWPDirEntry[] content;
    while (!st.eof) {
        content ~= WWPDirEntry.read(st);
    }

    return content;
}

static this() {
    registeredReaders["DIR\x1A"] = &readDir;
}
