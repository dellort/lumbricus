module wwpdata.reader_dir;

import str = utils.string;
import tango.stdc.stringz : fromStringz;
import stdx.stream;
import wwpdata.common;
import wwpdata.reader;
import wwptools.unworms;
import utils.filetools;

import tango.io.Stdout;
import tango.io.FilePath;
import tango.util.PathUtil;

import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

struct WWPDirEntry {
    uint offset, size;
    char[] filename;

    static WWPDirEntry read(Stream st) {
        WWPDirEntry ret;
        st.seek(4, SeekPos.Current);
        st.readExact(&ret.offset, 4);
        st.readExact(&ret.size, 4);
        char[255] buf;
        int i;
        do {
            st.readExact(&buf[i],4);
            i += 4;
        } while (buf[i-1] != 0);
        //cut off zeros
        ret.filename = fromStringz(buf.ptr).dup;
        return ret;
    }

    void writeFile(Stream st, char[] outPath) {
        st.seek(offset, SeekPos.Set);
        scope fileOut = new File(outPath ~ pathsep ~ filename, FileMode.OutNew);
        fileOut.copyFrom(st, size);
    }

    //st: the .dir file, same as for read() and writeFile()
    Stream open(Stream st) {
        auto res = new SliceStream(st, offset, offset+size);
        res.seek(0, SeekPos.Set);
        return res;
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

    this(char[] filename) {
        //NOTE: file isn't closed; you had to add that to ~this(), but D doesn't
        //   allow this because of the garbage collector destructor rules!
        this(new File(filename, FileMode.In));
    }

    //filesystem-like interface, was too lazy to use filesystem.d
    Stream open(char[] filename) {
        foreach (e; mEntries) {
            if (str.icmp(e.filename, filename) == 0) {
                return e.open(mStream);
            }
        }
        throw new Exception("file within .dir not found: " ~ filename);
    }

    //works exactly like do_unworms, just filename is opened from the .dir-file
    void unworms(char[] filename, char[] outputPath) {
        do_unworms(this.open(filename), FilePath(filename).name,
            outputPath);
    }

    //works like std.file.listdir(pathname, pattern), on the .dir-filelist
    char[][] listdir(char[] pattern) {
        char[][] res;
        foreach (e; mEntries) {
            if (patternMatch(e.filename, pattern))
                res ~= e.filename;
        }
        return res;
    }
}

void readDir(Stream st, char[] outputDir, char[] fnBase) {
    char[] outPath = outputDir ~ pathsep ~ fnBase;
    trymkdir(outPath);

    auto content = doReadDir(st);

    foreach (c; content) {
        Stdout(c.filename).newline;
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
    st.seek(dirPos+4096+4, SeekPos.Set);

    WWPDirEntry[] content;
    while (!st.eof) {
        content ~= WWPDirEntry.read(st);
    }

    return content;
}

static this() {
    registeredReaders["DIR\x1A"] = &readDir;
}
