module levelgen.level;

import framework.framework;
import game.resources;
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
    private Vector2i mSize;
    private uint mPitch;
    package Surface mImage;
    //metadata per pixel
    private Lexel[] mData;

    //non-landscape values filled by level generator
    private bool mIsCave;     //is this a cave level
    private uint mWaterLevel; //initial water level, in pixels from lower border

    //color of the landscape border where landscape was destroyed
    package Color mBorderColor;
    //background image for the level (visible when parts of level destroyed)
    //can be null!
    package Surface mBackImage;

    Surface skyGradient;
    Surface skyBackdrop;
    Color skyColor;
    AnimationResource skyDebris;

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

    public this(Vector2i asize, Surface image) {
        mSize = asize; mImage = image;
        mData.length = size.x*size.y;
        mPitch = size.x;
        mBorderColor = Color(0.6,0.6,0);
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
