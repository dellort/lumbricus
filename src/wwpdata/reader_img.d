module wwpdata.reader_img;

import devil.image;
import std.stream;
import path = std.path;
import wwpdata.common;
import wwpdata.reader;

const IMG_FLAG_COMPRESSED = 0x40;

Image readImgFile(Stream st) {
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
    st.seek((st.position+3) & 0xfffffffc,SeekPos.Set);

    dataLen -= st.position;
    ubyte[] data = new ubyte[dataLen];
    st.readExact(data.ptr, dataLen);
    ubyte[] imgData;

    if (flags & IMG_FLAG_COMPRESSED) {
        imgData = wormsDecompress(data, w*h);
    } else {
        imgData = data[0..w*h];
    }
    RGBColor[] rgbData = pal.toRGBKey(imgData, COLORKEY);

    auto img = new Image(w, h, false);
    img.blitRGBData(rgbData.ptr, w, h, 0, 0, false);
    return img;
}

void readImg(Stream st, char[] outputDir, char[] fnBase) {
    scope img = readImgFile(st);
    img.save(outputDir ~ path.sep ~ fnBase ~ ".png");
}

static this() {
    registeredReaders["IMG\x1A"] = &readImg;
}
