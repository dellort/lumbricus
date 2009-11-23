module wwptools.convert;

import wwptools.image;

import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

struct RGBTriple {
    float r, g, b;
}

struct GradientDef {
    RGBTriple top, half, bottom;
}

//Take a grass.png converted from worms (imgIn) and split it into grounddown.png
//and groundup.png (last one flipped)
//output a line specifying bordercolor which is in the right box of grass.png
RGBTriple convertGround(Image imgIn, char[] destPath = ".") {
    scope imgDown = new Image(64,imgIn.h);
    imgDown.blit(imgIn,0,0,64,imgIn.h,0,0);
    imgDown.save(destPath~pathsep~"grounddown.png");
    scope imgUp = new Image(64,imgIn.h);
    imgUp.blit(imgIn,64,0,64,imgIn.h,0,0);
    imgUp.flip();
    imgUp.save(destPath~pathsep~"groundup.png");

    RGBAColor col = imgIn.getPixel(128,0);
    return RGBTriple(cast(float)col.r/255, cast(float)col.g/255,
        cast(float)col.b/255);
}

//Take a gradient.png converted from worms and output a line specifying
//skycolor (from the first pixel, so the sky is continued seeminglessly)
GradientDef convertSky(Image imgIn) {
    GradientDef ret;
    //average over a width x 3 area at the image center to get 3rd color
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
    //top color
    RGBAColor colStart = imgIn.getPixel(0,0);
    //bottom color
    RGBAColor colEnd = imgIn.getPixel(0,imgIn.h-1);
    //convert to float
    ret.top = RGBTriple(cast(float)colStart.r/255, cast(float)colStart.g/255,
        cast(float)colStart.b/255);
    ret.half = RGBTriple(rAvg/255, gAvg/255, bAvg/255);
    ret.bottom = RGBTriple(cast(float)colEnd.r/255, cast(float)colEnd.g/255,
        cast(float)colEnd.b/255);
    return ret;
}
