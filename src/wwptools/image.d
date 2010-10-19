//left-overs of scr/devil/image.d
//don't use for new code
//should be replaced by free functions using Surface directly
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
const RGBAColor cTransparent = {0, 0, 0, 0};

class Image {
    private Surface mImg;

    int w() { return mImg.size.x; }
    int h() { return mImg.size.y; }

    void blit(Image source, int xsrc, int ysrc, int aw, int ah, int xdst, int ydst) {
        mImg.copyFrom(source.mImg, Vector2i(xdst, ydst), Vector2i(xsrc, ysrc),
            Vector2i(aw, ah));
    }

    void blitRGBData(RGBAColor[] data, int aw, int ah) {
        Color.RGBA32* pixels;
        uint pitch;
        mImg.lockPixelsRGBA32(pixels, pitch);
        int w = max(min(aw, mImg.size.x), 0);
        for (int y = 0; y < min(ah, mImg.size.y); y++) {
            pixels[0..w] = data[aw*y .. aw*(y+1)];
            pixels += pitch;
        }
        mImg.unlockPixels(mImg.rect);
    }

    //flip over x-axis
    void flip() {
        mImg.mirror(true, false);
    }

    //mirror along y-axis
    void mirror() {
        mImg.mirror(false, true);
    }

    RGBAColor getPixel(int x, int y) {
        RGBAColor ret;
        Color.RGBA32* pixels;
        uint pitch;
        assert(mImg.rect.isInside(Vector2i(x, y)));
        //lockPixelsRGBA32 should
        mImg.lockPixelsRGBA32(pixels, pitch);
        pixels += y*pitch + x;
        ret = *pixels;
        mImg.unlockPixels(Rect2i.init);
        return ret;
    }

    void clear(RGBAColor clearColor = cTransparent) {
        clear(clearColor.r,clearColor.g,clearColor.b,clearColor.a);
    }

    void clear(ubyte r, ubyte g, ubyte b, ubyte a) {
        mImg.fill(mImg.rect, Color.fromBytes(r, g, b, a));
    }

    //set alpha values of this image to b/w values of another
    //mask will be converted to RGB, current image to RGBA
    //invert: Set to true to make white transparent (else black)
    //-- actually, use the red channel as alpha now (whatever DEVIL did)
    void applyAlphaMask(Image mask, bool invert = false) {
        assert(mImg.size == mask.mImg.size);

        Color.RGBA32* src, dst;
        uint psrc, pdst;
        mask.mImg.lockPixelsRGBA32(src, psrc);
        mImg.lockPixelsRGBA32(dst, pdst);
        for (int y = 0; y < mImg.size.y; y++) {
            for (int x = 0; x < mImg.size.x; x++) {
                int a = src[x].r;
                if (invert)
                    a = 255 - a;
                dst[x].a = a;
            }
            src += psrc;
            dst += pdst;
        }
        mImg.unlockPixels(mImg.rect);
        mask.mImg.unlockPixels(Rect2i.init);
    }

    void save(char[] filename) {
        auto f = Stream.OpenFile(filename, File.WriteCreate);
        scope(exit) f.close();
        saveTo(f);
    }

    void saveTo(Stream s) {
        saveImage(mImg, s);
    }

    this(char[] file) {
        Stream f = Stream.OpenFile(file);
        scope(exit) f.close();
        mImg = loadImage(f);
    }

    this(int aw, int ah, bool colorkey = true) {
        mImg = new Surface(Vector2i(aw, ah));
    }

    private this() {
    }

    void free() {
        mImg.free();
        mImg = null;
    }

    Image dup() {
        Image n = new Image();
        n.mImg = mImg.clone();
        return n;
    }
}

