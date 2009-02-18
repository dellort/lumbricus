module wwpdata.reader_bnk;

import devil.image;
import stdx.stream;
import wwpdata.common;
import wwpdata.reader;
import wwpdata.animation;
import tango.io.Stdout;

struct WWPBnkAnimHdr {
    ushort flags, x, y;
    ushort startFrameNr, frameCount;
    ubyte unk;
    ubyte frameTimeMS;
}

struct WWPBnkFrameHdr {
    ushort chunkNr;
    ushort startPixel;
    ushort x1, y1, x2, y2;
}

struct WWPBnkChunkHdr {
    uint startOffset, decompSize;
    uint unk;
}

AnimList readBnkFile(Stream st) {
    char[4] hdr;
    st.readExact(hdr.ptr, 4);
    assert(hdr == "BNK\x1A");

    uint dataLen;
    st.readExact(&dataLen, 4);

    WWPPalette pal = WWPPalette.read(st);
    st.seek(2, SeekPos.Current);

    uint animCount, frameCount, chunkCount;
    WWPBnkAnimHdr[] animHdr;
    st.readExact(&animCount, 4);
    animHdr.length = animCount;
    st.readExact(animHdr.ptr, WWPBnkAnimHdr.sizeof*animCount);

    WWPBnkFrameHdr[] frameHdr;
    st.readExact(&frameCount, 4);
    frameHdr.length = frameCount;
    st.readExact(frameHdr.ptr, WWPBnkFrameHdr.sizeof*frameCount);

    WWPBnkChunkHdr[] chunkHdr;
    st.readExact(&chunkCount, 4);
    chunkHdr.length = chunkCount;
    st.readExact(chunkHdr.ptr, WWPBnkChunkHdr.sizeof*chunkCount);

    int curChunkIdx = -1;
    ubyte[] chunkDecomp;
    auto alist = new AnimList;
    foreach (int ianim, WWPBnkAnimHdr hanim; animHdr) {
        Stdout.format("Animation {}/{}   \r", ianim+1, animCount);
        Stdout.flush();
        auto anim = new Animation(hanim.x, hanim.y,
            (hanim.flags & WWP_ANIMFLAG_REPEAT) > 0,
            (hanim.flags & WWP_ANIMFLAG_BACKWARDS) > 0, hanim.frameTimeMS);
        foreach (hframe; frameHdr[hanim.startFrameNr..hanim.startFrameNr+hanim.frameCount]) {
            if (hframe.chunkNr > curChunkIdx) {
                curChunkIdx = hframe.chunkNr;
                uint len;
                if (curChunkIdx >= chunkHdr.length-1) {
                    len = dataLen - st.position;
                } else {
                    len = chunkHdr[curChunkIdx+1].startOffset - chunkHdr[curChunkIdx].startOffset;
                }
                ubyte[] buf = new ubyte[len];
                st.readExact(buf.ptr, len);
                delete chunkDecomp;
                chunkDecomp = wormsDecompress(buf, chunkHdr[curChunkIdx].decompSize);
                delete buf;
            }
            int fwidth = hframe.x2-hframe.x1;
            int fheight = hframe.y2-hframe.y1;
            RGBColor[] rgbData = pal.toRGBKey(chunkDecomp[hframe.startPixel..hframe.startPixel+fwidth*fheight], COLORKEY);
            anim.addFrame(hframe.x1, hframe.y1, fwidth, fheight, rgbData);
        }
        alist.animations ~= anim;
    }
    delete chunkDecomp;
    delete animHdr;
    delete frameHdr;
    delete chunkHdr;
    Stdout.newline;
    return alist;
}

void readBnk(Stream st, char[] outputDir, char[] fnBase) {
    scope alist = readBnkFile(st);
    Stdout.newline();
    Stdout("Saving\r");
    alist.save(outputDir, fnBase);
    Stdout.newline();
}

static this() {
    registeredReaders["BNK\x1A"] = &readBnk;
}
