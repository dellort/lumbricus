///description of the binary file formats produced used for some resources
module framework.resfileformats;

import str = stdx.string: toString, split;
import stdx.conv: toShort;

struct FileAtlasTexture {
align(1):
    short x, y; //position
    short w, h; //size
    short page; //specified in the text .conf file
    short _pad0;//align to next power of 2 lol

    char[] toString() {
        return str.toString(x) ~ ' ' ~ str.toString(y) ~ ' '
            ~ str.toString(w) ~ ' ' ~ str.toString(h) ~ ' '
            ~ str.toString(page);
    }

    static FileAtlasTexture parseString(char[] s) {
        FileAtlasTexture ret;
        char[][] values = str.split(s);
        assert(values.length >= 4);
        ret.x = toShort(values[0]);
        ret.y = toShort(values[1]);
        ret.w = toShort(values[2]);
        ret.h = toShort(values[3]);
        if (values.length > 4) {
            ret.page = toShort(values[4]);
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
    int[2] frameCount; //for each direction
    int[2] mapParam;   //mapParam[direction] = param, see FileAnimationParamType
    int flags; //bitfield, see FileAnimationFlags
    FileAnimationFrame[0] frames;
}

struct FileAnimations {
align(1):
    int animationCount;
    FileAnimation[0] animations;
}
