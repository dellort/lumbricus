module levelgen.level;

import framework.framework;
import game.animation;
import utils.configfile;

//LEvel ELement
//collection of flags
//all 0 currently means pixel is free
public enum Lexel : ubyte {
    Null = 0,
    SolidSoft = 1, // destroyable ground
    SolidHard = 2, // undestroyable ground

    INVALID = 255
}

/// A Lumbricus level.
public class Level {
    package Vector2i mSize;
    private uint mPitch;
    package Surface mImage;
    //metadata per pixel
    package Lexel[] mData;

    //non-landscape values filled by level generator
    private bool mIsCave;     //is this a cave level
    private uint mWaterLevel; //initial water level, in pixels from lower border

    //color of the landscape border where landscape was destroyed
    package Color mBorderColor = {0.6,0.6,0};
    //background image for the level (visible when parts of level destroyed)
    //can be null!
    package Surface mBackImage;

    Surface skyGradient;
    Surface skyBackdrop;
    Color skyColor;
    Animation skyDebris;

    public Vector2i size() {
        return mSize;
    }

    /// pitch value for the data array (length of scanline)
    public uint dataPitch() {
        return mPitch;
    }

    /// bitmap of the level, returned surface has the same width/height
    public Surface image() {
        return mImage;
    }

    /// contains a mask value for each pixel... pixmask = mData[width*y + x]
    public Lexel[] data() {
        return mData;
    }

    /// access the data array
    public Lexel opIndex(uint x, uint y) {
        return mData[y*mPitch+x];
    }
    public void opIndexAssign(Lexel lexel, uint x, uint y) {
        mData[y*mPitch+x] = lexel;
    }

    /*public this(Vector2i asize, Surface image) {
        mSize = asize; mImage = image;
        mData.length = size.x*size.y;
        mPitch = size.x;
    }*/
    //usually created by generator.d/Generator
    package this() {
    }

    package void data(Lexel[] data) {
        assert(data.length == mSize.x * mSize.y);
        mData = data;
        mPitch = mSize.x;
    }

    public bool isCave() {
        return mIsCave;
    }
    package void isCave(bool cave) {
        mIsCave = cave;
    }

    public uint waterLevel() {
        return mWaterLevel;
    }
    package void waterLevel(uint wlevel) {
        mWaterLevel = wlevel;
    }

    public Surface backImage() {
        return mBackImage;
    }
    public Color borderColor() {
        return mBorderColor;
    }
}

//helpers
//xxx these should be moved away, they really don't belong here
package:

import conv = std.conv;
import str = std.string;

private static char[][] marker_strings = ["FREE", "LAND", "SOLID_LAND"];

Lexel parseMarker(char[] value) {
    static Lexel[] marker_values = [Lexel.Null, Lexel.SolidSoft,
        Lexel.SolidHard];
    for (uint i = 0; i < marker_strings.length; i++) {
        if (str.icmp(value, marker_strings[i]) == 0) {
            return marker_values[i];
        }
    }
    //else explode
    throw new Exception("invalid marker value in configfile: " ~ value);
}

char[] writeMarker(Lexel v) {
    return marker_strings[v];
}

Vector2i readVector(char[] s) {
    //whatever
    Vector2i pt;
    if (!parseVector(s, pt))
        throw new Exception("invalid vector string");
    return pt;
}

//some of this stuff maybe should be moved into configfile.d
//practically a map over ConfigNode *g*
T[] readList(T)(ConfigNode node, T delegate(char[] item) translate) {
    T[] res;
    //(the name isn't needed (and should be empty))
    foreach(char[] name, char[] value; node) {
        T item = translate(value);
        res ~= item;
    }
    return res;
}

Vector2i[] readPointList(ConfigNode node) {
    return readList!(Vector2i)(node, (char[] item) {
        //a bit inefficient, but that doesn't matter
        //(as long as nobody puts complete vector graphics there...)
        // ^ update: yes we do! generated levels...
        return readVector(item);
    });
}
uint[] readUIntList(ConfigNode node) {
    return readList!(uint)(node, (char[] item) {
        return conv.toUint(item);
    });
}

void writeList(T)(ConfigNode to, T[] stuff, char[] delegate(T item) translate) {
    to.clear();
    foreach(T s; stuff) {
        to.setStringValue("", translate(s));
    }
}

void writePointList(ConfigNode node, Vector2i[] stuff) {
    writeList!(Vector2i)(node, stuff, (Vector2i item) {
        return str.format("%s %s", item.x, item.y);
    });
}
void writeUIntList(ConfigNode node, uint[] stuff) {
    writeList!(uint)(node, stuff, (uint item) {
        return str.toString(item);
    });
}
