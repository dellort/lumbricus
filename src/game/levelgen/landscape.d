module game.levelgen.landscape;

import framework.framework;
import framework.resset;
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

//the part of the themeing which is still needed for a fully rendered level
//this is a smaller part of the real LevelTheme
//in generator.d, there's another type LandscapeGenTheme which contains theme
//graphics needed for rendering a Landscape
class LandscapeTheme {
    //all members are read-only after initialization

    //for the following two things, the color is only used if the Surface is null

    //the landscape border where landscape was destroyed
    Color borderColor = {0.6,0.6,0};
    Surface borderImage;

    //background image for the level (visible when parts of level destroyed)
    Color backColor = {0,0,0,0};
    Surface backImage;

    //corresponds to "landscape" node in a level theme
    this(ConfigNode node) {
        ResourceSet res = gFramework.resources.loadResSet(node);

        void load(char[] name, out Surface s, out Color c) {
            s = res.get!(Surface)(node[name ~ "_tex"], true);
            c.parse(node.getStringValue(name ~ "_color"));

            //throw new what
        }

        load("border", borderImage, borderColor);
        load("soil", backImage, backColor);
    }
}

/// Not a level anymore, only a piece of landscape.
public class Landscape {
    private {
        uint mPitch; //in Lexels, not bytes (currently they're the same anyway)
        Surface mImage;
        //metadata per pixel
        Lexel[] mData;

        LandscapeTheme mTheme;
    }

    public Vector2i size() {
        return mImage.size();
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

/+
nobody needs it, scrub it
    /// access the data array
    public Lexel opIndex(uint x, uint y) {
        return mData[y*mPitch+x];
    }
    public void opIndexAssign(Lexel lexel, uint x, uint y) {
        mData[y*mPitch+x] = lexel;
    }
+/

    this(Surface a_image, Lexel[] a_data, LandscapeTheme a_theme) {
        mImage = a_image;
        data = a_data; //use the setter
        assert(!!a_theme, "must provide a theme");
        mTheme = a_theme;
    }

    //copy constructor
    this(Landscape from) {
        mPitch = from.mPitch;
        mImage = from.mImage.clone();
        mData = from.mData.dup;
        mTheme = from.mTheme;
    }

    void data(Lexel[] data) {
        assert(data.length == size.x * size.y);
        mData = data;
        mPitch = size.x;
    }

    public LandscapeTheme theme() {
        return mTheme;
    }

    Landscape copy() {
        return new Landscape(this);
    }

    //create a new Landscape which contains a copy of a subrectangle of this
    Landscape cutOutRect(Rect2i rc) {
        rc.fitInsideB(Rect2i(mImage.size()));
        //copy out the subrect from the metadata
        Lexel[] ndata;
        ndata.length = rc.size.x * rc.size.y;
        uint sx = rc.size.x;
        int o1 = 0;
        int o2 = rc.p1.y*mPitch + rc.p1.x;
        for (int y = 0; y < rc.size.y; y++) {
            ndata[o1 .. o1 + sx] = mData[o2 .. o2 + sx];
            o1 += sx;
            o2 += mPitch;
        }
        return new Landscape(mImage.subrect(rc), ndata, theme());
    }
}

