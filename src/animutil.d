module animutil;

import tango.io.FilePath;
import tango.io.Stdout;
import tango.util.Convert;
//xxx dsss bug? linker errors about ConversionException on win32 without
//    this import (not needed otherwise)
import tango.util.PathUtil;

import aconv.atlaspacker;
import devil.image;
import utils.vector2;
import wwptools.animconv;
import wwpdata.common;
import wwpdata.animation;

const cSyntax =
`Syntax: animutil <sourceImg> [<boxX> = 512] [<boxY> = 512] [-repeat]

Source image must be square.`;

int main(char[][] args)
{
    //parse parameters
    if (args.length < 2) {
        Stdout(cSyntax).newline;
        return 1;
    }
    auto box = Vector2i(512, 512);
    bool repeat = false;
    try {
        if (args.length > 2)
            box.x = to!(int)(args[2]);
        if (args.length > 3)
            box.y = to!(int)(args[3]);
        if (args.length > 4)
            repeat = (args[4] == "-repeat");
    } catch (ConversionException e) {
        Stderr("Invalid arguments").newline;
    }

    //get base of image filename -> target animation name
    char[] aniName = (new FilePath(args[1])).name;

    //construct packing classes (5 classes, lol)
    auto img = new Image(args[1]);
    auto animPacker = new AtlasPacker(aniName~"_atlas", box);
    auto animFile = new AniFile(aniName, animPacker);
    auto animEntry = new AniEntry(animFile, aniName);
    //xxx AniEntry expects an array
    Animation[1] animAni;
    animAni[0] = new Animation(img.w, img.h, true, false, 50);

    //rotate source image and create 36 frames
    Image curFrame;
    for (int i = 0; i < 36; i++) {
        curFrame = img.rotated(i*10);
        animAni[0].addFrame(0, 0, curFrame);
    }
    //fill AniEntry
    animEntry.addFrames(animAni);
    if (repeat)
        animEntry.flags = FileAnimationFlags.Repeat;
    //save
    animPacker.write("./", true);
    animFile.write("./", true);

    return 0;
}
