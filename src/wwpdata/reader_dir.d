module wwpdata.reader_dir;

import str = std.string;
import path = std.path;
import std.file;
import std.stream;
import std.stdio;
import wwpdata.common;
import wwpdata.reader;

struct WWPDirEntry {
    uint offset, size;
    char[] filename;

    static WWPDirEntry read(Stream st) {
        WWPDirEntry ret;
        st.seek(4, SeekPos.Current);
        st.readBlock(&ret.offset, 4);
        st.readBlock(&ret.size, 4);
        char[255] buf;
        int i;
        do {
            st.readBlock(&buf[i],4);
            i += 4;
        } while (buf[i-1] != 0);
        //cut off zeros
        ret.filename = str.toString(buf.ptr).dup;
        return ret;
    }

    void writeFile(Stream st, char[] outPath) {
        st.seek(offset, SeekPos.Set);
        scope fileOut = new File(outPath ~ path.sep ~ filename, FileMode.OutNew);
        fileOut.copyFrom(st, size);
    }
}

void readDir(Stream st, char[] outputDir, char[] fnBase) {
    char[] outPath = outputDir ~ path.sep ~ fnBase;
    try { mkdir(outPath); } catch {};

    uint dataLen;
    st.readBlock(&dataLen, 4);

    uint dirPos;
    st.readBlock(&dirPos, 4);
    st.seek(dirPos+4096+4, SeekPos.Set);

    WWPDirEntry[] content;
    while (!st.eof) {
        content ~= WWPDirEntry.read(st);
        writefln(content[$-1].filename);
    }
    foreach (de; content) {
        de.writeFile(st, outPath);
    }
}

static this() {
    registeredReaders["DIR\x1A"] = &readDir;
}
