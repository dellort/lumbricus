module wwpdata.reader_img;

import devil.image;
import std.stream;
import path = std.path;
import wwpdata.common;
import wwpdata.reader;

const IMG_FLAG_COMPRESSED = 0x40;

Image readImgFile(Stream st) {
    char[4] hdr;
    st.readBlock(hdr.ptr, 4);
    assert(hdr == "IMG\x1A");

    uint dataLen;
    ubyte bpp, flags;
    st.readBlock(&dataLen, 4);
    st.readBlock(&bpp, 1);
    st.readBlock(&flags, 1);

    WWPPalette pal = WWPPalette.read(st);

    ushort w, h;
    st.readBlock(&w, 2);
    st.readBlock(&h, 2);

    //alignment
    //xxx this could appear in other files, too
    st.seek((st.position+3) & 0xfffffffc,SeekPos.Set);

    dataLen -= st.position;
    ubyte[] data = new ubyte[dataLen];
    st.readBlock(data.ptr, dataLen);
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
