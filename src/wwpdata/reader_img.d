module wwpdata.reader_img;

import framework.surface;
import wwptools.image;
import utils.array;
import utils.misc;
import utils.rect2;
import utils.stream;
import utils.vector2;
import wwpdata.common;
import wwpdata.reader;
import std.path;

enum IMG_FLAG_COMPRESSED = 0x40;

Surface readImgFile(Stream st) {
    char[4] hdr;
    st.readExact(hdr.ptr, 4);
    assert(hdr == "IMG\x1A");

    uint dataLen;
    ubyte bpp, flags;
    st.readExact(&dataLen, 4);
    st.readExact(&bpp, 1);
    st.readExact(&flags, 1);

    WWPPalette pal = WWPPalette.read(st);

    ushort w, h;
    st.readExact(&w, 2);
    st.readExact(&h, 2);

    //alignment
    //xxx this could appear in other files, too
    st.position = (st.position+3) & 0xfffffffc;

    dataLen -= st.position;
    ubyte[] data = new ubyte[dataLen];
    st.readExact(data.ptr, dataLen);
    ubyte[] imgData, decomp;

    if (flags & IMG_FLAG_COMPRESSED) {
        decomp = imgData = new ubyte[w*h];
        wormsDecompress(data, imgData);
    } else {
        imgData = data[0..w*h];
    }

    auto img = new Surface(Vector2i(w, h));
    blitPALData(img, pal, imgData, Rect2i(0, 0, w, h));

    delete decomp;
    delete data;

    return img;
}

void readImg(Stream st, string outputDir, string fnBase) {
    scope img = readImgFile(st);
    saveImageToFile(img, outputDir ~ sep ~ fnBase ~ ".png");
    img.free();
}

static this() {
    registeredReaders["IMG\x1A"] = &readImg;
}
