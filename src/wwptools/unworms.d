module wwptools.unworms;

import wwptools.image;
import utils.stream;
import tango.io.Stdout;
import wwpdata.reader;
import wwpdata.reader_bnk;
import wwpdata.reader_dir;
import wwpdata.reader_img;
import wwpdata.reader_spr;
import utils.filetools;

void do_unworms(char[] filename, char[] outputDir) {
    char[] fnBase = basename(filename);
    auto st = Stream.OpenFile(filename, File.ReadExisting);
    scope(exit) st.close();

    if (auto readFunc = findReader(st)) {
        Stdout.formatln("Extracting from '{}'...", filename);
        readFunc(st, outputDir, fnBase);
    }
}

WWPReader findReader(Stream st) {
    char[4] hdr;
    st.position = 0;
    st.readExact(hdr.ptr, 4);
    st.position = 0;
    if (hdr in registeredReaders) {
        return registeredReaders[hdr];
    } else {
        Stdout("Error: Unknown filetype").newline;
        return null;
    }
}

//stream-version of unworms
//pathBase = what getBaseName returns for the filename st was opened from
void do_unworms(Stream st, char[] pathBase, char[] outputDir) {
    if (auto readFunc = findReader(st)) {
        readFunc(st, outputDir, pathBase);
    }
}
