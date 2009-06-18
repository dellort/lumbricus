///description of the binary file formats produced used for some resources
module common.resfileformats;

import str = utils.string;
import tango.util.Convert;
import utils.misc;

struct FileAtlasTexture {
align(1):
    short x, y; //position
    short w, h; //size
    short page; //specified in the text .conf file
    short _pad0;//align to next power of 2 lol

    char[] toString() {
        return myformat("{} {} {} {} {}", x, y, w, h, page);
    }

    static FileAtlasTexture parseString(char[] s) {
        FileAtlasTexture ret;
        char[][] values = str.split(s);
        assert(values.length >= 4);
        ret.x = to!(short)(values[0]);
        ret.y = to!(short)(values[1]);
        ret.w = to!(short)(values[2]);
        ret.h = to!(short)(values[3]);
        if (values.length > 4) {
            ret.page = to!(short)(values[4]);
        } else {
            ret.page = 0;
        }
        return ret;
    }
}

struct FileAtlas {
align(1):
    int textureCount; //textures.length
    FileAtlasTexture[0] textures;
}

enum FileDrawEffects {
    MirrorY = 1,
}

struct FileAnimationFrame {
align(1):
    int bitmapIndex;
    int drawEffects; //bitfield, see FileDrawEffects
    short centerX, centerY;
}

enum FileAnimationParamType {
    Null = 0,
    Time = 1,
    P1 = 2,
    P2 = 3,
}

enum FileAnimationFlags {
    //see common.animation.AnimationData
    Repeat = 1,
    KeepLastFrame = 2,
}

struct FileAnimation {
align(1):
    short[2] size;  //size in pixels
    int[3] frameCount; //for each direction
    int[3] mapParam;   //mapParam[direction] = param, see FileAnimationParamType
    int flags; //bitfield, see FileAnimationFlags
    FileAnimationFrame[0] frames;
}

struct FileAnimations {
align(1):
    int animationCount;
    FileAnimation[0] animations;
}
