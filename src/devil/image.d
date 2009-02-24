// abstract devil a bit
module devil.image;

import str = stdx.string;
import derelict.devil.il;
import derelict.devil.ilu;
import derelict.util.exception;

//pragma(lib,"DerelictIL");
//pragma(lib,"DerelictILU");
//pragma(lib,"DerelictUtil");

struct RGBAColor {
    ubyte r, g, b, a;

    const RGBAColor Transparent = {0, 0, 0, 0};
}

private bool devilInitialized = false;

class Image {
    int w, h;
    private ILuint mImg;
    bool alpha; //always true lol

    private static ILuint loadImage(char[] filename) {
        ILuint imgName;
        ilGenImages(1, &imgName);
        ilBindImage(imgName);

        if (!ilLoadImage(str.toStringz(filename))) {
            throw new Exception("Failed to load image " ~ filename ~ " : " ~
                str.toString(ilGetError()));
        }

        return imgName;
    }

    //bind to IL
    void bind() {
        ilBindImage(mImg);
    }

    void blit(Image source, int xsrc, int ysrc, int aw, int ah, int xdst, int ydst) {
        ubyte[] buf;
        buf.length = aw*ah*4;

        int fmt = IL_RGB;
        if (source.alpha)
            fmt = IL_RGBA;

        source.bind();
        ilCopyPixels(xsrc, ysrc, 0, aw, ah, 1, fmt, IL_UNSIGNED_BYTE, buf.ptr);

        this.bind();
        ilSetPixels(xdst, ydst, 0, aw, ah, 1, fmt, IL_UNSIGNED_BYTE, buf.ptr);

        delete buf;
    }

    void blitRGBData(RGBAColor[] data, int aw, int ah, int xdst = 0,
        int ydst = 0)
    {
        bool srcalpha = true;
        int fmt = IL_RGB;
        if (srcalpha)
            fmt = IL_RGBA;

        this.bind();
        ilSetPixels(xdst, ydst, 0, aw, ah, 1, fmt, IL_UNSIGNED_BYTE, data.ptr);
    }

    Image rotated(float angle, RGBAColor clearColor = RGBAColor.Transparent) {
        ILuint imgName;
        ilGenImages(1, &imgName);
        ilBindImage(imgName);

        ilCopyImage(mImg);

        ilClearColour(clearColor.r,clearColor.g,clearColor.b,clearColor.a);

        iluRotate(angle);

        int w_new = ilGetInteger(IL_IMAGE_WIDTH);
        int h_new = ilGetInteger(IL_IMAGE_HEIGHT);

        iluCrop(w_new/2-w/2,h_new/2-h/2,0,w,h,0);

        return new Image(imgName);
    }

    //flip over x-axis
    void flip() {
        this.bind();
        iluFlipImage();
    }

    //mirror along y-axis
    void mirror() {
        this.bind();
        iluMirror();
    }

    RGBAColor getPixel(int x, int y) {
        RGBAColor ret;
        this.bind();
        ilCopyPixels(x, y, 0, 1, 1, 1, IL_RGBA, IL_UNSIGNED_BYTE, &ret);
        return ret;
    }

    void clear(RGBAColor clearColor = RGBAColor.Transparent) {
        clear(clearColor.r,clearColor.g,clearColor.b,clearColor.a);
    }

    void clear(ubyte r, ubyte g, ubyte b, ubyte a) {
        bind();
        ilClearColour(r, g, b, a);
        ilClearImage();
        ilClearColour(0, 0, 0, 0);
    }

    //set alpha values of this image to b/w values of another
    //mask will be converted to RGB, current image to RGBA
    //invert: Set to true to make white transparent (else black)
    void applyAlphaMask(Image mask, bool invert = false) {
        assert(mask.w == w && mask.h == h);
        mask.bind();
        ilConvertImage(IL_RGB, IL_UNSIGNED_BYTE);
        ubyte* maskData = mask.data();

        this.bind();
        //add alpha channel
        ilConvertImage(IL_RGBA, IL_UNSIGNED_BYTE);
        ubyte* curData = data();
        curData += 3;
        for (int i = 0; i < w*h; i ++) {
            *curData = *maskData;
            if (invert)
                *curData = 255 - *curData;
            maskData += 3;
            curData += 4;
        }
        alpha = true; //lolwut?
    }

    ubyte* data() {
        this.bind();
        return ilGetData();
    }

    ILint format() {
        this.bind();
        return ilGetInteger(IL_IMAGE_FORMAT);
    }

    void save(char[] filename) {
        ilBindImage(mImg);

        ilEnable(IL_FILE_OVERWRITE);
        ilRegisterOrigin(IL_ORIGIN_UPPER_LEFT);

        if (!ilSave(IL_PNG, str.toStringz(filename))) {
            throw new Exception("Failed to write image file " ~ filename ~
                " : " ~ str.toString(ilGetError()));
        }
    }

    private void checkInit() {
        if (!devilInitialized) {
            Derelict_SetMissingProcCallback(&DerelictMissingProcCallback);
            DerelictIL.load();
            DerelictILU.load();

            ilInit();
            iluInit();

            devilInitialized = true;
        }
    }

    this (ILuint img) {
        checkInit();
        mImg = img;
        ilBindImage(mImg);
        w = ilGetInteger(IL_IMAGE_WIDTH);
        h = ilGetInteger(IL_IMAGE_HEIGHT);
        int fmt = ilGetInteger(IL_IMAGE_FORMAT);
        alpha = fmt == IL_RGBA || fmt == IL_BGRA;
    }

    this(char[] file) {
        checkInit();
        this(loadImage(file));
    }

    this(int aw, int ah) {
        bool alpha = true;
        checkInit();
        w = aw; h = ah;
        this.alpha = alpha;

        ilGenImages(1, &mImg);
        ilBindImage(mImg);

        int fmt = IL_RGB;
        int c = 3;
        if (alpha) {
            fmt = IL_RGBA;
            c = 4;
        }
        ilTexImage(w, h, 1, c, fmt, IL_UNSIGNED_BYTE, null);
    }

    void free() {
        w = h = 0;
        ilDeleteImages(1, &mImg);
        mImg = 0;
    }
}

bool DerelictMissingProcCallback(char[] libName, char[] procName)  {
    //those fail to load from official windows dlls (tested 1.7.3 and 1.7.5)
    if (procName == "iluConvolution") return true;
    if (procName == "iluSetLanguage") return true;
    return false;
}
