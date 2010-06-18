///description of the binary file formats produced used for some resources
module common.resfileformats;

import utils.misc;

struct FileAtlasTexture {
align(1):
    short x, y; //position
    short w, h; //size
    short page; //specified in the text .conf file
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
    P3 = 4,
}

const char[][] cFileAnimationParamTypeStr = [
    "Null",
    "Time",
    "P1",
    "P2",
    "P3"
];

enum FileAnimationFlags {
    //see common.animation.AnimationData
    Repeat = 1,
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
