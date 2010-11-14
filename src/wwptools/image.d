//left-overs of scr/devil/image.d
module wwptools.image;

import framework.surface;
import framework.imgread;
import framework.imgwrite;
import tango.stdc.stringz : toStringz, fromStringz;
import utils.configfile;
import utils.misc;
import utils.color;
import utils.stream;
import utils.vector2;
import utils.rect2;

alias Color.RGBA32 RGBAColor;

void saveImageToFile(Surface img, char[] filename) {
    auto f = Stream.OpenFile(filename, File.WriteCreate);
    scope(exit) f.close();
    //xxx extension gets lost; but default (png) is ok => too lazy to fix
    saveImage(img, f);
}

//there's a loadImage(char[] path) in imgread.d, but that uses gFS
Surface loadImageFromFile(char[] path) {
    Stream f = Stream.OpenFile(path);
    scope(exit) f.close();
    return loadImage(f);
}

void blitRGBData(Surface img, RGBAColor[] data, int aw, int ah) {
    Color.RGBA32* pixels;
    uint pitch;
    img.lockPixelsRGBA32(pixels, pitch);
    int w = max(min(aw, img.size.x), 0);
    for (int y = 0; y < min(ah, img.size.y); y++) {
        pixels[0..w] = data[aw*y .. aw*(y+1)];
        pixels += pitch;
    }
    img.unlockPixels(img.rect);
}

RGBAColor getPixel(Surface img, int x, int y) {
    RGBAColor ret;
    Color.RGBA32* pixels;
    uint pitch;
    argcheck(img.rect.isInside(Vector2i(x, y)));
    img.lockPixelsRGBA32(pixels, pitch);
    pixels += y*pitch + x;
    ret = *pixels;
    img.unlockPixels(Rect2i.init);
    return ret;
}

//set alpha values of this image to b/w values of another
//mask will be converted to RGB, current image to RGBA
//invert: Set to true to make white transparent (else black)
//-- actually, use the red channel as alpha now (whatever DEVIL did)
void applyAlphaMask(Surface img, Surface mask, bool invert = false) {
    argcheck(img.size == mask.size);

    Color.RGBA32* src, dst;
    uint psrc, pdst;
    mask.lockPixelsRGBA32(src, psrc);
    img.lockPixelsRGBA32(dst, pdst);
    for (int y = 0; y < img.size.y; y++) {
        for (int x = 0; x < img.size.x; x++) {
            int a = src[x].r;
            if (invert)
                a = 255 - a;
            dst[x].a = a;
        }
        src += psrc;
        dst += pdst;
    }
    img.unlockPixels(img.rect);
    mask.unlockPixels(Rect2i.init);
}
