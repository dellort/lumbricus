module wwpdata.common;

import utils.stream;
import wwpdata.decompression;
import devil.image : RGBAColor;

struct WWPPalette {
    RGBAColor[] palEntries;

    static WWPPalette read(Stream st) {
        WWPPalette ret;
        ushort palSize;
        st.readExact(cast(ubyte[])(&palSize)[0..1]);
        ret.palEntries.length = palSize;
        foreach (inout pe; ret.palEntries) {
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

    RGBAColor[] toRGBA(ubyte[] palData) {
        RGBAColor[] ret = new RGBAColor[palData.length];
        foreach (int i, ubyte b; palData) {
            if (b > 0 && b <= palEntries.length) {
                ret[i] = palEntries[b-1];
            } else {
                ret[i].a = 0;
            }
        }
        return ret;
    }
}

const WWP_ANIMFLAG_REPEAT = 0x1;
const WWP_ANIMFLAG_BACKWARDS = 0x2;

ubyte[] wormsDecompress(ubyte[] data, int len) {
    //std.stdio.writefln(len);
    return decompress_wlz77(data, len);
}
