module wwptools.unworms;

import wwptools.image;
import utils.stream;
import wwpdata.reader;
import wwpdata.reader_bnk;
import wwpdata.reader_dir;
import wwpdata.reader_img;
import wwpdata.reader_spr;
import utils.filetools;
import std.path;
import std.stdio;

void do_unworms(string filename, string outputDir) {
    string fnBase = basename(filename);
    auto st = Stream.OpenFile(filename, "rb");
    scope(exit) st.close();

    if (auto readFunc = findReader(st)) {
        writefln("Extracting from '%s'...", filename);
        readFunc(st, outputDir, fnBase);
    }
}

WWPReader findReader(Stream st) {
    char[4] hdr;
    st.position = 0;
    st.readExact(hdr.ptr, 4);
    st.position = 0;
    if (auto phdr = hdr in registeredReaders) {
        return *phdr;
    } else {
        writefln("Error: Unknown filetype");
        return null;
    }
}

//stream-version of unworms
//pathBase = what getBaseName returns for the filename st was opened from
void do_unworms(Stream st, string pathBase, string outputDir) {
    if (auto readFunc = findReader(st)) {
        readFunc(st, outputDir, pathBase);
    }
}
