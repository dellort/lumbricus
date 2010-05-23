module utils.color;

import utils.configfile;
import strparser = utils.strparser;
import utils.mybox;
import utils.misc;

import math = tango.math.Math;
import str = utils.string;
import tango.text.convert.Integer : convert;

//predefined colors - used by the parser
//global for fun and profit
Color[char[]] gColors;

public struct Color {
    //values between 0.0 and 1.0, 1.0 means full intensity
    //(a is the alpha value; 1.0 means fully opaque)
    float r = 0.0f, g = 0.0f, b = 0.0f;
    float a = 1.0f;

    //memory format for the OpenGL texture format we use in our framework
    //exactly:
    //  glTexImage2D(GL_TEXTURE_2D, _, GL_RGBA, _, _, _, GL_RGBA,
    //      GL_UNSIGNED_BYTE, _)
    struct RGBA32 {
        union {
            struct {
                ubyte r, g, b, a;
            }
            //indexed
            ubyte[4] colors;
            //endian-dependent 32 bit value, but useful to access pixels at once
            uint uint_val;
        }
    }

    //for RGBA32.colors
    const cIdxR = 0, cIdxG = 1, cIdxB = 2, cIdxA = 3;

    //for RGBA32.uint_val
    version (LittleEndian) {
        const cMaskR = 0x00_00_00_FF;
        const cMaskG = 0x00_00_FF_00;
        const cMaskB = 0x00_FF_00_00;
        const cMaskA = 0xFF_00_00_00;
    } else version (BigEndian) {
        const cMaskR = 0xFF_00_00_00;
        const cMaskG = 0x00_FF_00_00;
        const cMaskB = 0x00_00_FF_00;
        const cMaskA = 0x00_00_00_FF;
    } else {
        static assert(false, "no endian");
    }

    //black transparent pixel
    const Color Transparent = Color(0, 0, 0, 0);
    //some other common colors (but not too many)
    const Color Black = Color(0, 0, 0, 1);
    const Color White = Color(1, 1, 1, 1);
    //"null" value (for default parameters)
    const Color Invalid = Color(float.infinity, float.infinity,
        float.infinity, float.infinity);

    /// a value that can be used as epsilon when comparing colors
    //0.3f is a fuzzify value, with 255 I expect colors to be encoded with at
    //most 8 bits
    public static const float epsilon = 0.3f * 1.0f / 255;

    //for use with Color.Invalid
    bool valid() {
        return *this != Invalid;
    }

    /// to help the OpenGL code; use with glColor4fv
    /// (unclean but better than to cast Color* to float* like it was before)
    float* ptr() {
        return &r;
    }

    /// clamp all components to the range [0.0, 1.0]
    public void clamp() {
        r = clampChannel(r);
        g = clampChannel(g);
        b = clampChannel(b);
        a = clampChannel(a);
    }

    static float clampChannel(float c) {
        if (c < 0.0f) c = 0.0f;
        if (c > 1.0f) c = 1.0f;
        return c;
    }

    public static Color opCall(float r, float g, float b, float a) {
        Color res;
        res.r = r;
        res.g = g;
        res.b = b;
        res.a = a;
        return res;
    }
    public static Color opCall(float r, float g, float b) {
        return opCall(r,g,b,1.0f);
    }
    public static Color opCall(float c) {
        return opCall(c,c,c);
    }

    ///convert ubyte to a float as used by Color ([0..255] -> [0..1])
    static float fromByte(ubyte c) {
        return c/255.0f;
    }
    ///reverse of fromByte(), doesn't clamp or range check
    static ubyte toByte(float c) {
        return cast(ubyte)(c*255);
    }

    //create Color where each channel is converted from [0..255] to [0..1]
    static Color fromBytes(ubyte r, ubyte g, ubyte b, ubyte a = 255) {
        return Color(fromByte(r), fromByte(g), fromByte(b), fromByte(a));
    }

    static Color fromRGBA32(ref RGBA32 rgba) {
        Color c = void;
        c.r = fromByte(rgba.r);
        c.g = fromByte(rgba.g);
        c.b = fromByte(rgba.b);
        c.a = fromByte(rgba.a);
        return c;
    }

    RGBA32 toRGBA32() {
        RGBA32 c = void;
        c.r = toByte(r);
        c.g = toByte(g);
        c.b = toByte(b);
        c.a = toByte(a);
        return c;
    }

    Color opMul(float m) {
        Color res = *this;
        res *= m;
        return res;
    }
    Color opMul(Color c) {
        Color res = *this;
        res *= c;
        return res;
    }
    void opMulAssign(float m) {
        r = r*m;
        g = g*m;
        b = b*m;
        a = a*m;
    }
    void opMulAssign(Color c) {
        r *= c.r;
        g *= c.g;
        b *= c.b;
        a *= c.a;
    }
    Color opAdd(Color c2) {
        return Color(r+c2.r,g+c2.g,b+c2.b,a+c2.a);
    }
    Color opSub(Color c2) {
        return Color(r-c2.r,g-c2.g,b-c2.b,a-c2.a);
    }

    //the following 4 functions are taken/modified from xzgv (GPL)
    //whatever they mean, whatever they're correct or not...
    static float dimmer(float color, float brightness) {
        return clampChannel(color+brightness);
    }
    static float contrastup(float color, float contrast) {
        return clampChannel(0.5f + (color - 0.5f)*contrast);
    }
    static float setgamma(float color, float g) {
        return math.pow(color, 1.0f/g);
    }
    //return modified color
    Color applyBCG(float brightness, float contrast, float gamma) {
        Color res;
        float apply(float c) {
            //xzgv author says it's debatable where gamma should be applied lol
            return dimmer(contrastup(setgamma(c, gamma), contrast), brightness);
        }
        res.r = apply(r);
        res.g = apply(g);
        res.b = apply(b);
        res.a = a;
        return res;
    }

    ///if alpha value is <= 1.0 - epsilon
    bool hasAlpha() {
        return a <= 1.0f - epsilon;
    }

    /++
     + parse color from string s and replace r/g/b/a values
     + formats:
     +  1) <float> <float> <float> [<float>]: rgb or rgba directly (deprecated)
     +  2) [<ext> (',' <ext>)*]
     +    <ext> ::= <colorname> | ('r'|'g'|'b'|'a'|'k' '=' <float>)
     +    single components, or a colorname to set all components (if components
     +    are assigned more than once, the latest values are used)
     +    'k' means to set rgb to the given float value
     +  3) hex format, RRGGBB[AA], e.g. 00ff00
     + On failure, this isn't touched!
     + Previous member values of Color are used, if the color spec is
     + incomplete, e.g. "a=0.5" will simply do this.a = 0.5f;
     +/
    static Color fromString(char[] s, Color previous = Color.init) {
        Color newc = previous;

        //old parsing

        char[][] values = str.split(s);
        if (values.length == 3 || values.length == 4) {
            try {
                newc.r = strparser.fromStr!(float)(values[0]);
                newc.g = strparser.fromStr!(float)(values[1]);
                newc.b = strparser.fromStr!(float)(values[2]);
                newc.a = 1.0f;
                if (values.length > 3) {
                    newc.a = strparser.fromStr!(float)(values[3]);
                }
                return newc;
            } catch (strparser.ConversionException e) {
            }
        }

        //hex format
        if (newc.parseHex(s) == s.length) {
            return newc;
        }

        //new parsing

        char[][] stuff = str.split(s, ",");

        if (stuff.length == 0)
            throw strparser.newConversionException!(Color)(s, "empty string");

        foreach (x; stuff) {
            char[][] sub = str.split(x, "=");
            if (sub.length == 1) {
                auto pcolor = str.tolower(str.strip(sub[0])) in gColors;
                if (!pcolor)
                    throw strparser.newConversionException!(Color)(s,
                        "possibly unknown color name");
                newc = *pcolor;
            } else if (sub.length == 2) {
                float val;
                try {
                    val = strparser.fromStr!(float)(str.strip(sub[1]));
                } catch (strparser.ConversionException e) {
                    throw strparser.newConversionException!(Color)(s,
                        "color component not a float");
                }
                switch (str.strip(sub[0])) {
                    case "r": newc.r = val; break;
                    case "g": newc.g = val; break;
                    case "b": newc.b = val; break;
                    case "a": newc.a = val; break;
                    case "k": newc.r = newc.g = newc.b = val; break;
                    default:
                        throw strparser.newConversionException!(Color)(s,
                            "unknown color component");
                }
            } else {
                throw strparser.newConversionException!(Color)(s);
            }
        }

        return newc;
    }

    //try parsing a hexadecimal color value at the start of s (no prefix)
    //Example: 00ff00
    //Garbage may follow the color code; returns number of chars eaten
    private int parseHex(char[] s) {
        if (s.length > 5) {
            //try reading r/g/b
            uint cnt, tmp;
            ubyte sr = cast(ubyte)convert(s[0..2], 16U, &tmp); cnt += tmp;
            ubyte sg = cast(ubyte)convert(s[2..4], 16U, &tmp); cnt += tmp;
            ubyte sb = cast(ubyte)convert(s[4..6], 16U, &tmp); cnt += tmp;
            if (cnt < 6)
                return 0;
            r = fromByte(sr);
            g = fromByte(sg);
            b = fromByte(sb);
            if (s.length > 7) {
                //try reading optional alpha
                ubyte sa = cast(ubyte)convert(s[6..8], 16U, &cnt);
                if (cnt == 2) {
                    a = fromByte(sa);
                    return 8;
                }
            }
            //r,g,b were read successfully
            return 6;
        }
        return 0;
    }

    char[] fromStringRev() {
        return toString();
    }

    //produce string parseable by parse()
    char[] toString() {
        if (hasAlpha)
            return myformat("r={}, g={}, b={}, a={}", r, g, b, a);
        else
            return myformat("r={}, g={}, b={}", r, g, b);
    }
}

//a unittest never hurts
unittest {
    Color p(char[] s) {
        try {
            return Color.fromString(s);
        } catch (strparser.ConversionException e) {
            assert(false, e.toString());
        }
    }
    assert(p("a=0.2, b=0.4,r=0.8") == Color(0.8, 0, 0.4, 0.2));
    assert(p("a=0.2, b=0.4 ,k=0.8") == Color(0.8, 0.8, 0.8, 0.2));
    auto x = "r=0.2, g=0.2, b=0.2, a=0.2";
    assert(p(p(x).toString()) == p(x));
    gColors["red"] = Color(1,0,0);
    assert(p("red, a=0.8") == Color(1,0,0,0.8));
    assert(p(" red  ,a    = 0.8 ") == Color(1,0,0,0.8));
    assert(p("00ff00") == Color(0,1.0,0));
    assert(p("1   0.5 0.5") == Color(1,0.5,0.5));
}

//(try to) load each item from node as color
void loadColors(ConfigNode node) {
    foreach (char[] key, char[] value; node) {
        //try {
            //(not a single expression, because AA key creation)
            auto c = Color.fromString(value);
            gColors[key] = c;
        //} catch (strparser.ConversionException e) {
        //}
    }
}


//--------------- idiotic idiocy
static this() {
    strparser.addStrParser!(Color)();
}
