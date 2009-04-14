module utils.color;

import utils.configfile : ConfigNode;
import utils.strparser;
import utils.mybox;
import utils.misc;

import math = tango.math.Math;
import str = stdx.string;
import conv = tango.util.Convert;
import tango.text.convert.Float;
import tango.core.Exception : IllegalArgumentException;

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
    const cIdxR = 0, cIdxG = 1, cIdxB = 2, cIdxAlpha = 3;

    //for RGBA32.uint_val
    version (LittleEndian) {
        const cMaskR = 0x00_00_00_FF;
        const cMaskG = 0x00_00_FF_00;
        const cMaskB = 0x00_FF_00_00;
        const cMaskAlpha = 0xFF_00_00_00;
    } else version (BigEndian) {
        const cMaskR = 0xFF_00_00_00;
        const cMaskG = 0x00_FF_00_00;
        const cMaskB = 0x00_00_FF_00;
        const cMaskAlpha = 0x00_00_00_FF;
    } else {
        static assert(false, "no endian");
    }

    //black transparent pixel
    const Color cTransparent = Color(0, 0, 0, 0);

    /// a value that can be used as epsilon when comparing colors
    //0.3f is a fuzzify value, with 255 I expect colors to be encoded with at
    //most 8 bits
    public static const float epsilon = 0.3f * 1.0f / 255;

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
    void opMulAssign(float m) {
        r = r*m;
        g = g*m;
        b = b*m;
        a = a*m;
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
     +  <float> <float> <float> [<float>]: rgb or rgba directly (deprecated)
     +  [<ext> (',' <ext>)*]
     +    <ext> ::= <colorname> | ('r'|'g'|'b'|'a'|'k' = <float>)
     +    single components, or a colorname to set all components (if components
     +    are assigned more than once, the latest values are used)
     +    'k' means to set rgb to the given float value
     +/
    bool parse(char[] s) {
        //old parsing

        char[][] values = str.split(s);
        if (values.length == 3 || values.length == 4) {
            try {
                Color newc;
                newc.r = toFloat(values[0]);
                newc.g = toFloat(values[1]);
                newc.b = toFloat(values[2]);
                newc.a = 1.0f;
                if (values.length > 3) {
                    newc.a = toFloat(values[3]);
                }
                *this = newc;
                return true;
            } catch (IllegalArgumentException e) {
            }
        }

        //new parsing

        *this = Color.init;
        char[][] stuff = str.split(s, ",");

        if (stuff.length == 0)
            return false;

        foreach (x; stuff) {
            char[][] sub = str.split(x, "=");
            if (sub.length == 1) {
                auto pcolor = str.tolower(str.strip(sub[0])) in gColors;
                if (!pcolor)
                    return false;
                *this = *pcolor;
            } else if (sub.length == 2) {
                float val;
                try {
                    val = toFloat(str.strip(sub[1]));
                } catch (IllegalArgumentException e) {
                    return false;
                }
                switch (str.strip(sub[0])) {
                    case "r": r = val; break;
                    case "g": g = val; break;
                    case "b": b = val; break;
                    case "a": a = val; break;
                    case "k": r = g = b = val; break;
                    default:
                        return false;
                }
            } else {
                return false;
            }
        }

        return true;
    }

    //produce string parseable by parse()
    char[] toString() {
        return myformat("r={}, g={}, b={}, a={}", r, g, b, a);
    }
}

//a unittest never hurts
unittest {
    Color p(char[] s) {
        Color res;
        bool b = res.parse(s);
        assert(b);
        return res;
    }
    assert(p("a=0.2, b=0.4,r=0.8") == Color(0.8, 0, 0.4, 0.2));
    assert(p("a=0.2, b=0.4 ,k=0.8") == Color(0.8, 0.8, 0.8, 0.2));
    auto x = "r=0.2, g=0.2, b=0.2, a=0.2";
    assert(p(p(x).toString()) == p(x));
}

//(try to) load each item from node as color
void loadColors(ConfigNode node) {
    foreach (char[] key, char[] value; node) {
        Color c;
        if (c.parse(value))
            gColors[key] = c;
    }
}

//colorparser for boxes (used by the commandline)
private MyBox parseColorBox(char[] s) {
    Color res;
    if (res.parse(s)) {
        return MyBox.Box(res);
    }
    return MyBox();
}

private char[] unParseColorBox(MyBox b) {
    return b.unbox!(Color)().toString();
}

static this() {
    gBoxParsers[typeid(Color)] = &parseColorBox;
    gBoxUnParsers[typeid(Color)] = &unParseColorBox;
}
