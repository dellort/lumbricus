///description of the binary file formats produced used for some resources
module common.resfileformats;

import utils.misc;
import utils.stream;

struct FileAtlasTexture {
align(1):
    short x, y; //position
    short w, h; //size
    short page; //specified in the text .conf file
}

struct FileAtlas {
align(1):
    int textureCount; //textures.length
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

struct FileSmallString {
align(1):
    ubyte length;
    //follows: length char[] (must be valid utf-8)
}

struct FileAnimation {
align(1):
    short[2] size;  //size in pixels
    int[3] frameCount; //for each direction
    int[3] mapParam;   //mapParam[direction] = param, see FileAnimationParamType
    int flags; //bitfield, see FileAnimationFlags
    int frametime_ms; //framerate in ms
    //what follows after this struct is:
    //- frameCount[0]*frameCount[1]*frameCount[2] FileAnimationFrame[]
    //- 3 pairs of FileSmallString for the param_conv array
}

struct FileAnimations {
align(1):
    int animationCount;
    //follows: animationCount Fileanimation[]
}

//actually never written to a file; just dumped it here because the module is
//  imported by both animconv.d and restypes/animation.d

//xxx: I know I shouldn't use the structs directly from the stream,
//  because the endianess etc. might be different on various platforms
//  - the sizes and alignments are ok though, so who cares?
//maybe should use marshal.d instead, but too lazy

//all animation metadata for a single animation
struct AnimationData {
    FileAnimation info;
    FileAnimationFrame[] frames;
    char[][3] param_conv;

    void write(Stream s) {
        //again, endian issues etc....
        s.writeExact(&info, info.sizeof);
        s.writeExact(frames.ptr, typeof(frames[0]).sizeof * frames.length);
        foreach (char[] str; param_conv) {
            softAssert(str.length <= 255, "can't write");
            ubyte x = str.length;
            s.writeExact((&x)[0..1]);
            s.writeExact(cast(ubyte[])str);
        }
    }

    void read(Stream s) {
        s.readExact(cast(ubyte[])(&info)[0..1]);
        //in a perfect world there wouldn't be any overflow issues
        frames.length = info.frameCount[0] * info.frameCount[1]
            * info.frameCount[2];
        s.readExact(cast(ubyte[])frames);
        foreach (ref char[] str; param_conv) {
            ubyte x;
            s.readExact((&x)[0..1]);
            str.length = x;
            s.readExact(cast(ubyte[])str);
        }
    }
}

AnimationData[] readAnimations(Stream s) {
    AnimationData[] res;
    FileAnimations header;
    s.readExact(cast(ubyte[])(&header)[0..1]);
    res.length = header.animationCount;
    foreach (ref ani; res) {
        ani.read(s);
    }
    return res;
}

void writeAnimations(Stream s, AnimationData[] anis) {
    FileAnimations header;
    header.animationCount = anis.length;
    s.writeExact(&header, header.sizeof);
    foreach (ani; anis) {
        ani.write(s);
    }
}
