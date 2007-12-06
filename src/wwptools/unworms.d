module tools.unworms;

import devil.image;
import std.stream;
import std.stdio;
import path = std.path;
import std.file;
import str = std.string;
import wwpdata.reader;
import wwpdata.reader_bnk;
import wwpdata.reader_dir;
import wwpdata.reader_img;
import wwpdata.reader_spr;

void do_unworms(char[] filename, char[] outputDir) {
    char[] fnBase = path.getBaseName(path.getName(filename));
    scope st = new File(filename, FileMode.In);

    char[4] hdr;
    st.readBlock(hdr.ptr, 4);
    if (hdr in registeredReaders) {
        writefln("Extracting from '%s'...",path.getBaseName(filename));
        WWPReader readFunc = registeredReaders[hdr];
        readFunc(st, outputDir, fnBase);
    } else {
        writefln("Error: Unknown filetype");
        return 1;
    }

    return 0;
}
