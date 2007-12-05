module utils.color;

import utils.configfile : ConfigNode;
import utils.strparser;
import utils.mybox;

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

    /// clamp all components to the range [0.0, 1.0]
    public void clamp() {
        if (r < 0.0f) r = 0.0f;
        if (r > 1.0f) r = 1.0f;
        if (g < 0.0f) g = 0.0f;
        if (g > 1.0f) g = 1.0f;
        if (b < 0.0f) b = 0.0f;
        if (b > 1.0f) b = 1.0f;
        if (a < 0.0f) a = 0.0f;
        if (a > 1.0f) a = 1.0f;
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
        return Color(r+c2.r,g+c2.g,b+c2.g,a+c2.a);
    }
    Color opSub(Color c2) {
        return Color(r-c2.r,g-c2.g,b-c2.g,a-c2.a);
    }

    //xxx: ?
    uint toRGBA32() {
        uint rb = cast(ubyte)(255*r);
        uint gb = cast(ubyte)(255*g);
        uint bb = cast(ubyte)(255*b);
        uint ab = cast(ubyte)(255*a);
        return ab << 24 | rb << 16 | gb << 8 | bb;
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
