// abstract devil a bit
module devil.image;

import str = std.string;
import derelict.devil.il;
import derelict.devil.ilu;

//pragma(lib,"DerelictIL");
//pragma(lib,"DerelictILU");
//pragma(lib,"DerelictUtil");

struct RGBAColor {
    ubyte r, g, b, a;
}

class Image {
    int w, h;
    private ILuint mImg;
    bool alpha;

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

    void blitRGBData(void* data, int aw, int ah, int xdst, int ydst, bool srcalpha) {
        int fmt = IL_RGB;
        if (srcalpha)
            fmt = IL_RGBA;

        this.bind();
        ilSetPixels(xdst, ydst, 0, aw, ah, 1, fmt, IL_UNSIGNED_BYTE, data);
    }

    Image rotated(float angle) {
        ILuint imgName;
        ilGenImages(1, &imgName);
        ilBindImage(imgName);

        ilCopyImage(mImg);

        //ilClearColour(0,0,0,0);

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

    void clear(ubyte r, ubyte g, ubyte b, ubyte a) {
        bind();
        ilClearColour(r, g, b, a);
        ilClearImage();
        ilClearColour(0, 0, 0, 0);
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

    this (ILuint img) {
        mImg = img;
        ilBindImage(mImg);
        w = ilGetInteger(IL_IMAGE_WIDTH);
        h = ilGetInteger(IL_IMAGE_HEIGHT);
        int fmt = ilGetInteger(IL_IMAGE_FORMAT);
        alpha = fmt == IL_RGBA || fmt == IL_BGRA;
    }

    this(char[] file) {
        this(loadImage(file));
    }

    this(int aw, int ah, bool alpha) {
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
}

static this() {
    DerelictIL.load();
    DerelictILU.load();

    ilInit();
    iluInit();
}
