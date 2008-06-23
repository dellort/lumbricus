module animutil;

import str = std.string;
import path = std.path;
import std.stdio;
import std.conv;

import aconv.atlaspacker;
import devil.image;
import utils.vector2;
import wwptools.animconv;
import wwpdata.common;
import wwpdata.animation;

const cSyntax =
`Syntax: animutil <sourceImg> [<useAlpha> = true] [<boxX> = 512] [<boxY> = 512]

Source image must be square.`;

int main(char[][] args)
{
    //parse parameters
    if (args.length < 2) {
        writefln(cSyntax);
        return 1;
    }
    bool alpha = true;
    if (args.length > 2)
        if (args[2] != "true")
            alpha = false;
    auto box = Vector2i(512, 512);
    if (args.length > 3)
        box.x = toInt(args[3]);
    if (args.length > 4)
        box.y = toInt(args[4]);

    //get base of image filename -> target animation name
    char[] aniName = path.getName(path.getBaseName(args[1]));

    //construct packing classes (5 classes, lol)
    auto img = new Image(args[1]);
    auto animPacker = new AtlasPacker(aniName~"_atlas", box, alpha);
    auto animFile = new AniFile(aniName, animPacker);
    auto animEntry = new AniEntry(animFile, aniName);
    //xxx AniEntry expects an array
    Animation[1] animAni;
    animAni[0] = new Animation(img.w, img.h, true, false, 50);

    //rotate source image and create 36 frames
    RGBAColor clearColor;
    if (!alpha)
        clearColor = RGBAColor(COLORKEY.r, COLORKEY.g, COLORKEY.b, 255);

    Image curFrame;
    for (int i = 0; i < 36; i++) {
        curFrame = img.rotated(i*10, clearColor);
        animAni[0].addFrame(0, 0, curFrame);
    }
    //fill AniEntry
    animEntry.addFrames(animAni);
    animEntry.flags = FileAnimationFlags.Repeat;
    //save
    animPacker.write("./", true);
    animFile.write("./", true);

    return 0;
}
