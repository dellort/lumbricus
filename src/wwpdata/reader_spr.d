module wwpdata.reader_spr;

import devil.image;
import stdx.stream;
import path = stdx.path;
import wwpdata.common;
import wwpdata.reader;
import wwpdata.animation;

struct WWPSprFrameHdr {
    uint offset;
    ushort x1, y1, x2, y2;
}

AnimList readSprFile(Stream st) {
    char[4] hdr;
    st.readExact(hdr.ptr, 4);
    assert(hdr == "SPR\x1A");

    uint dataLen;
    ubyte bpp, flags;
    st.readExact(&dataLen, 4);
    st.readExact(&bpp, 1);
    st.readExact(&flags, 1);

    WWPPalette pal = WWPPalette.read(st);
    st.seek(4, SeekPos.Current);

    ushort animFlags, boxW, boxH, frameCount;
    st.readExact(&animFlags, 2);
    st.readExact(&boxW, 2);
    st.readExact(&boxH, 2);
    st.readExact(&frameCount, 2);

    WWPSprFrameHdr[] frameHdr = new WWPSprFrameHdr[frameCount];
    st.readExact(frameHdr.ptr, frameCount*WWPSprFrameHdr.sizeof);

    auto anim = new Animation(boxW, boxH, (animFlags & WWP_ANIMFLAG_REPEAT) > 0,
        (animFlags & WWP_ANIMFLAG_BACKWARDS) > 0);

    foreach (fr; frameHdr) {
        int w = fr.x2 - fr.x1;
        int h = fr.y2 - fr.y1;
        ubyte[] data = new ubyte[w*h];
        st.readExact(data.ptr, w*h);

        RGBColor[] rgbData = pal.toRGBKey(data, COLORKEY);
        anim.addFrame(fr.x1, fr.y1, w, h, rgbData);
    }
    auto alist = new AnimList;
    alist.animations ~= anim;
    return alist;
}

void readSpr(Stream st, char[] outputDir, char[] fnBase) {
    scope alist = readSprFile(st);
    alist.save(outputDir, fnBase);
}

static this() {
    registeredReaders["SPR\x1A"] = &readSpr;
}
