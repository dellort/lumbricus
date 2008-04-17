module wwptools.convert;

import devil.image;
import std.stdio;
import path = std.path;

struct RGBTriple {
    float r, g, b;
}

//Take a grass.png converted from worms and split it into grounddown.png
//and groundup.png (last one flipped)
//output a line specifying bordercolor which is in the right box of grass.png
RGBTriple convertGround(char[] filename, char[] destPath = ".") {
    scope imgIn = new Image(filename);

    scope imgDown = new Image(64,imgIn.h,false);
    imgDown.blit(imgIn,0,0,64,imgIn.h,0,0);
    imgDown.save(destPath~path.sep~"grounddown.png");
    scope imgUp = new Image(64,imgIn.h,false);
    imgUp.blit(imgIn,64,0,64,imgIn.h,0,0);
    imgUp.flip();
    imgUp.save(destPath~path.sep~"groundup.png");

    RGBAColor col = imgIn.getPixel(128,0);
    return RGBTriple(cast(float)col.r/255, cast(float)col.g/255,
        cast(float)col.b/255);
}

//Take a gradient.png converted from worms and output a line specifying
//skycolor (from the first pixel, so the sky is continued seeminglessly)
RGBTriple convertSky(char[] filename) {
    scope imgIn = new Image(filename);
    RGBAColor cTmp;
    float rAvg = 0, gAvg = 0, bAvg = 0;
    int pixCount = 0;
    for (int y = imgIn.h/2-1; y < imgIn.h/2+1; y++) {
        for (int x = 0; x < imgIn.w; x++) {
            cTmp = imgIn.getPixel(x, y);
            rAvg += cTmp.r; gAvg += cTmp.g; bAvg += cTmp.b;
            pixCount++;
        }
    }
    rAvg /= pixCount; gAvg /= pixCount; bAvg /= pixCount;
    RGBAColor colStart = imgIn.getPixel(0,0);
    RGBAColor colEnd = imgIn.getPixel(0,imgIn.h-1);
    std.stdio.writefln("%3d %3d %3d",colStart.r,colStart.g,colStart.b);
    std.stdio.writefln("%3.0f %3.0f %3.0f",rAvg,gAvg,bAvg);
    std.stdio.writefln("%3d %3d %3d",colEnd.r,colEnd.g,colEnd.b);
    return RGBTriple(cast(float)colStart.r/255, cast(float)colStart.g/255,
        cast(float)colStart.b/255);
}
