module wwpdata.common;

import std.stream;
import wwpdata.decompression;

struct RGBColor {
    ubyte r, g, b;
}

const RGBColor COLORKEY = {255, 0, 255};

struct WWPPalette {
    RGBColor[] palEntries;

    static WWPPalette read(Stream st) {
        WWPPalette ret;
        ushort palSize;
        st.readBlock(&palSize, 2);
        ret.palEntries.length = palSize;
        foreach (inout pe; ret.palEntries) {
            st.readBlock(&pe, 3);
        }
        return ret;
    }

    RGBColor[] toRGBKey(ubyte[] palData, RGBColor key) {
        RGBColor[] ret = new RGBColor[palData.length];
        foreach (int i, ubyte b; palData) {
            if (b > 0 && b <= palEntries.length) {
                ret[i] = palEntries[b-1];
            } else {
                ret[i] = key;
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
