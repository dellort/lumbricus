module levelgen.level;

import framework.framework;
import game.animation;
import utils.configfile;

//LEvel ELement
//sorry for that stupid type name
public enum Lexel : ubyte {
    FREE = 0,           //free space
    LAND = 1,           //destroyable land
    SOLID_LAND = 2,     //undestroyable land

    INVALID = 255,
}

/// A Lumbricus level - this is the data passed from the level generator to the
/// engine (which is not there yet).
public class Level {
    private uint mWidth, mHeight, mPitch;
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
    Animation skyDebris;

    public uint width() {
        return mWidth;
    }
    public uint height() {
        return mHeight;
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

    public this(uint width, uint height, Surface image) {
        mWidth = width; mHeight = height; mImage = image;
        mData.length = width*height;
        mPitch = width;
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


    public Surface backimage() {
        return mBackImage;
    }
    public Color bordercolor() {
        return mBorderColor;
    }
}
