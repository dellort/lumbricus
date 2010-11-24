///description of the binary file formats produced used for some resources
module common.resfileformats;

import framework.surface;
import utils.misc;

struct FileAnimationFrame {
    SubSurface bitmap;
    bool mirrorY;
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

//all animation metadata for a single animation
struct AnimationData {
    short[2] size;  //size in pixels
    int[3] frameCount; //for each direction
    FileAnimationParamType[3] mapParam;   //mapParam[direction] = param
    bool repeat;
    int frametime_ms; //framerate in ms
    char[][3] param_conv;
    FileAnimationFrame[] frames;
}
