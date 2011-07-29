//left-overs of scr/devil/image.d
module wwptools.image;

import framework.surface;
import framework.imgread;
import framework.imgwrite;
import utils.configfile;
import utils.misc;
import utils.color;
import utils.stream;
import utils.vector2;
import utils.rect2;
import wwpdata.common;

alias Color.RGBA32 RGBAColor;

void saveImageToFile(Surface img, string filename) {
    auto f = Stream.OpenFile(filename, "wb");
    scope(exit) f.close();
    //xxx extension gets lost; but default (png) is ok => too lazy to fix
    saveImage(img, f);
}

//there's a loadImage(cstring path) in imgread.d, but that uses gFS
Surface loadImageFromFile(string path) {
    Stream f = Stream.OpenFile(path);
    scope(exit) f.close();
    return loadImage(f);
}

//copy the 8 bit palette encoded data on img, using the given palette
//rc is the destination rect on img
//data is expected to be packed, with image dimensions rc.size
void blitPALData(Surface img, WWPPalette pal, ubyte[] data, Rect2i rc) {
    argcheck(img.rect.contains(rc));
    Color.RGBA32* pixels;
    size_t pitch;
    img.lockPixelsRGBA32(pixels, pitch);
    uint w = rc.size.x;
    for (int y = rc.p1.y; y < rc.p2.y; y++) {
        auto p2 = pixels + pitch*y + rc.p1.x;
        pal.convertRGBA(data[0..w], p2[0..w]);
        data = data[w..$];
    }
    img.unlockPixels(img.rect);
}

RGBAColor getPixel(Surface img, int x, int y) {
    RGBAColor ret;
    Color.RGBA32* pixels;
    size_t pitch;
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
    size_t psrc, pdst;
    mask.lockPixelsRGBA32(src, psrc);
    img.lockPixelsRGBA32(dst, pdst);
    for (int y = 0; y < img.size.y; y++) {
        for (int x = 0; x < img.size.x; x++) {
            ubyte a = src[x].r;
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
