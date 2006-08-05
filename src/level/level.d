module level.level;

import framework.framework;

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
    private uint mWidth, mHeight;
    private Surface mImage;
    private Lexel[] mData;
    
    public uint width() {
        return mWidth;
    }
    public uint height() {
        return mHeight;
    }
    
    /// bitmap of the level, returned surface has the same width/height
    public Surface image() {
        return mImage;
    }
    
    /// contains a mask value for each pixel... pixmask = mData[width*y + x]
    public Lexel[] data() {
        return mData;
    }
    
    public this(uint width, uint height, Surface image) {
        mWidth = width; mHeight = height; mImage = image;
        mData.length = width*height;
    }
}