module wwpdata.reader_bnk;

import wwptools.image;
import utils.array;
import utils.misc;
import utils.stream;
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

//make buffer at least this big; possibly destroy existing array data
private void minbuffer(T)(ref T[] buffer, size_t length) {
    arrayReallocTrash(buffer, max(buffer.length, length));
}

RawAnimation[] readBnkFile(Stream st) {
    char[4] hdr;
    st.readExact(hdr.ptr, 4);
    assert(hdr == "BNK\x1A");

    uint dataLen;
    st.readExact(&dataLen, 4);

    WWPPalette pal = WWPPalette.read(st);
    st.seekRelative(2);

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
    ubyte[] readBuffer;
    RawAnimation[] alist;
    foreach (int ianim, WWPBnkAnimHdr hanim; animHdr) {
        //Stdout.format("Animation {}/{}   \r", ianim+1, animCount);
        //Stdout.flush();
        auto anim = new RawAnimation(pal, hanim.x, hanim.y,
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
                minbuffer(readBuffer, len);
                st.readExact(readBuffer.ptr, len);
                size_t decsize = chunkHdr[curChunkIdx].decompSize;
                minbuffer(chunkDecomp, decsize);
                wormsDecompress(readBuffer[0..len], chunkDecomp);
            }
            int fwidth = hframe.x2-hframe.x1;
            int fheight = hframe.y2-hframe.y1;
            ubyte[] fd = chunkDecomp[hframe.startPixel..hframe.startPixel+fwidth*fheight];
            anim.addFrame(hframe.x1, hframe.y1, fwidth, fheight, fd.dup);
        }
        alist ~= anim;
    }
    delete chunkDecomp;
    delete readBuffer;
    delete animHdr;
    delete frameHdr;
    delete chunkHdr;
    //Stdout.newline;
    return alist;
}

void readBnk(Stream st, char[] outputDir, char[] fnBase) {
    scope alist = readBnkFile(st);
    Stdout.newline();
    Stdout("Saving\r");
    saveAnimations(alist, outputDir, fnBase);
    Stdout.newline();
}

static this() {
    registeredReaders["BNK\x1A"] = &readBnk;
}
