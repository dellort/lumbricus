module wwpdata.common;

import utils.color;
import utils.stream;
import wwpdata.decompression;
import wwptools.image : RGBAColor;

import utils.misc;

class WWPPalette {
    //the unused part of the palette is padded with transparent entries
    //this way toRGBA() doesn't have to do extra bounds checking
    RGBAColor[256] palEntries;

    static WWPPalette read(Stream st) {
        auto ret = new WWPPalette;
        ushort palSize;
        st.readExact(cast(ubyte[])((&palSize)[0..1]));
        softAssert(palSize <= 255, "palette too big");
        //entry 0 is hard-wired to transparent; also clear the unused rest
        ret.palEntries[] = Color.Transparent.toRGBA32();
        foreach (inout pe; ret.palEntries[1..1 + palSize]) {
            struct RGBColor {
                ubyte r, g, b;
            }
            RGBColor c;
            st.readExact(cast(ubyte[])(&c)[0..1]);
            pe.r = c.r;
            pe.g = c.g;
            pe.b = c.b;
            pe.a = 0xff;
        }

        return ret;
    }

    void convertRGBA(ubyte[] palData, RGBAColor[] destData) {
        assert(palData.length <= destData.length);
        foreach (int i, ubyte b; palData) {
            destData[i] = palEntries[b];
        }
    }
}

const WWP_ANIMFLAG_REPEAT = 0x1;
const WWP_ANIMFLAG_BACKWARDS = 0x2;

ubyte[] wormsDecompress(ubyte[] data, ubyte[] buffer) {
    return decompress_wlz77(data, buffer);
}
