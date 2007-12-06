module tools.convert;

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
    RGBAColor col = imgIn.getPixel(0,0);
    return RGBTriple(cast(float)col.r/255, cast(float)col.g/255,
        cast(float)col.b/255);
}
