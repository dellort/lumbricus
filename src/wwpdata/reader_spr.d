module wwpdata.reader_spr;

import devil.image;
import std.stream;
import path = std.path;
import wwpdata.common;
import wwpdata.reader;
import wwpdata.animation;

struct WWPSprFrameHdr {
    uint offset;
    ushort x1, y1, x2, y2;
}

void readSpr(Stream st, char[] outputDir, char[] fnBase) {
    uint dataLen;
    ubyte bpp, flags;
    st.readBlock(&dataLen, 4);
    st.readBlock(&bpp, 1);
    st.readBlock(&flags, 1);

    WWPPalette pal = WWPPalette.read(st);
    st.seek(4, SeekPos.Current);

    ushort animFlags, boxW, boxH, frameCount;
    st.readBlock(&animFlags, 2);
    st.readBlock(&boxW, 2);
    st.readBlock(&boxH, 2);
    st.readBlock(&frameCount, 2);

    WWPSprFrameHdr[] frameHdr = new WWPSprFrameHdr[frameCount];
    st.readBlock(frameHdr.ptr, frameCount*WWPSprFrameHdr.sizeof);

    auto anim = new Animation(boxW, boxH, (animFlags & WWP_ANIMFLAG_REPEAT) > 0,
        (animFlags & WWP_ANIMFLAG_BACKWARDS) > 0);

    foreach (fr; frameHdr) {
        int w = fr.x2 - fr.x1;
        int h = fr.y2 - fr.y1;
        ubyte[] data = new ubyte[w*h];
        st.readBlock(data.ptr, w*h);

        RGBColor[] rgbData = pal.toRGBKey(data, COLORKEY);
        anim.addFrame(fr.x1, fr.y1, w, h, rgbData);
    }
    auto alist = new AnimList;
    alist.animations ~= anim;
    alist.save(outputDir, fnBase);
}

static this() {
    registeredReaders["SPR\x1A"] = &readSpr;
}
