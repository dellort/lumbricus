import derelict.devil.il;
import derelict.devil.ilu;
import str = std.string;

pragma(lib,"DerelictIL");
pragma(lib,"DerelictILU");
pragma(lib,"DerelictUtil");

ILuint loadImage(char[] filename) {
    ILuint imgName;
    ilGenImages(1, &imgName);
    ilBindImage(imgName);

    if (!ilLoadImage(str.toStringz(filename))) {
        throw new Exception("Failed to load image " ~ filename ~ " : " ~
            str.toString(ilGetError()));
    }

    return imgName;
}

ILuint rotateToNew(ILuint img, float angle) {
    ilBindImage(img);
    int w = ilGetInteger(IL_IMAGE_WIDTH);
    int h = ilGetInteger(IL_IMAGE_HEIGHT);

    ILuint imgName;
    ilGenImages(1, &imgName);
    ilBindImage(imgName);

    ilCopyImage(img);

    //ilClearColour(0,0,0,0);

    iluRotate(angle);

    int w_new = ilGetInteger(IL_IMAGE_WIDTH);
    int h_new = ilGetInteger(IL_IMAGE_HEIGHT);

    iluCrop(w_new/2-w/2,h_new/2-h/2,0,w,h,0);

    return imgName;
}

void saveImage(ILuint img, char[] filename) {
    ilBindImage(img);

    ilEnable(IL_FILE_OVERWRITE);

    if (!ilSave(IL_PNG, str.toStringz(filename))) {
        throw new Exception("Failed to write image file " ~ filename ~
            " : " ~ str.toString(ilGetError()));
    }
}

ILuint newImage(int w, int h) {
    ILuint imgName;
    ilGenImages(1, &imgName);
    ilBindImage(imgName);

    ilTexImage(w, h, 1, 4, IL_RGBA, IL_UNSIGNED_BYTE, null);

    return imgName;
}

void blitAt(ILuint src, ILuint dst, int xsrc, int ysrc, int w, int h, int xdst, int ydst) {
    ubyte[] buf;
    buf.length = w*h*4;

    ilBindImage(src);
    ilCopyPixels(xsrc, ysrc, 0, w, h, 1, IL_RGBA, IL_UNSIGNED_BYTE, buf.ptr);

    ilBindImage(dst);
    ilSetPixels(xdst, ydst, 0, w, h, 1, IL_RGBA, IL_UNSIGNED_BYTE, buf.ptr);
}

int main(char[][] args)
{
    DerelictIL.load();
    DerelictILU.load();

    ilInit();
    iluInit();

    ILuint img = loadImage(args[1]);
    ilBindImage(img);
    int w = ilGetInteger(IL_IMAGE_WIDTH);
    int h = ilGetInteger(IL_IMAGE_HEIGHT);

    ILuint[36] outImgs;

    for (int i = 0; i < 36; i++) {
        outImgs[i] = rotateToNew(img, i*10);
        //saveImage("anim"~str.toString(i)~".png");
    }

    ILuint finalImg = newImage(w*36,h);
    for (int i = 0; i < 36; i++) {
        blitAt(outImgs[i], finalImg, 0, 0, w, h, w*i, 0);
    }
    saveImage(finalImg, "anim.png");


    return 0;
}
