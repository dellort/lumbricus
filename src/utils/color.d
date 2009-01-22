module utils.color;

import utils.configfile : ConfigNode;
import utils.strparser;
import utils.mybox;

import math = stdx.math;
import str = stdx.string;
import conv = stdx.conv;

//predefined colors - used by the parser
//global for fun and profit
Color[char[]] gColors;

public struct Color {
    //values between 0.0 and 1.0, 1.0 means full intensity
    //(a is the alpha value; 1.0 means fully opaque)
    float r = 0.0f, g = 0.0f, b = 0.0f;
    float a = 1.0f;

    /// a value that can be used as epsilon when comparing colors
    //0.3f is a fuzzify value, with 255 I expect colors to be encoded with at
    //most 8 bits
    public static const float epsilon = 0.3f * 1.0f/255;

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

    //xxx: ?
    uint toRGBA32() {
        uint rb = cast(ubyte)(255*r);
        uint gb = cast(ubyte)(255*g);
        uint bb = cast(ubyte)(255*b);
        uint ab = cast(ubyte)(255*a);
        return ab << 24 | bb << 16 | gb << 8 | rb;
    }

    ///parse color from string s and replace r/g/b/a values
    bool parse(char[] s) {
        auto colors = gColors;
        if (s in colors) {
            *this = colors[s];
            return true;
        }

        char[][] values = str.split(s);
        if (values.length < 3 || values.length > 4)
            return false;
        try {
            Color newc;
            newc.r = conv.toFloat(values[0]);
            newc.g = conv.toFloat(values[1]);
            newc.b = conv.toFloat(values[2]);
            newc.a = 1.0f;
            if (values.length > 3) {
                newc.a = conv.toFloat(values[3]);
            }
            *this = newc;
            return true;
        } catch (conv.ConvOverflowError e) {
        } catch (conv.ConvError e) {
        }
        return false;
    }
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

static this() {
    gBoxParsers[typeid(Color)] = &parseColorBox;
}
