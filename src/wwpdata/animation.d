module wwpdata.animation;

import framework.imgwrite;
import framework.surface;
import wwptools.atlaspacker;
import wwptools.image;
import utils.stream;
import wwpdata.common;
import utils.boxpacker;
import utils.vector2;
import utils.filetools;
import utils.misc;
import tango.io.Stdout;

//dear tango team, please make things more convenient
import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

void saveAnimations(Animation[] animations, char[] outPath, char[] fnBase,
    bool tosubdir = true)
{
    //scope stMeta = new File(outPath ~ pathsep ~ fnBase ~ ".meta",
        //  FileMode.OutNew);
    foreach (int i, Animation a; animations) {
        char[] afn, apath;
        if (tosubdir) {
            //ah, how I love those "intuitive" formatting parameters...
            afn = myformat("anim_{0:d3}", i);
            apath = outPath ~ pathsep ~ fnBase;
            trymkdir(apath);
        } else {
            afn = fnBase;
            apath = outPath;
        }
        a.save(apath, afn);
        Stdout.format("Saving {}/{}   \r",i+1 , animations.length);
        Stdout.flush();
    }
    Stdout.newline; //??
}

//free the data violently (with delete)
void freeAnimations(ref Animation[] animations) {
    foreach (a; animations) {
        a.free();
    }
    delete animations;
}

class Animation {
    int boxWidth, boxHeight;
    bool repeat, backwards;
    int frameTimeMS;

    //if bitmaps already were written out
    bool wasDumped;

    struct FrameInfo {
        //w,h == frameImg.size
        int x, y, w, h;
        int atlasIndex; //page in the atlas it was packaged into (never needed??)
        int blockIndex; //index of the texture in the atlas
        Surface frameImg;

        static FrameInfo opCall(int x, int y, Surface frameData) {
            FrameInfo ret;
            ret.x = x;
            ret.y = y;
            ret.w = frameData.size.x;
            ret.h = frameData.size.y;
            ret.frameImg = frameData;
            return ret;
        }

        static FrameInfo opCall(int x, int y, int w, int h,
            RGBAColor[] frameData)
        {
            auto img = new Surface(Vector2i(w, h));
            blitRGBData(img, frameData, w, h);
            return opCall(x, y, img);
        }

        void blitOn(Surface dest, int x, int y) {
            dest.copyFrom(frameImg, Vector2i(x, y), Vector2i(0), frameImg.size);
        }

        void save(char[] filename) {
            saveImageToFile(frameImg, filename);
        }

        FrameInfo dup() {
            FrameInfo n = *this;
            n.frameImg = frameImg.clone;
            return n;
        }
    }

    FrameInfo[] frames;

    this(int boxWidth, int boxHeight, bool repeat, bool backwards,
        int frameTimeMS = 0)
    {
        this.boxWidth = boxWidth;
        this.boxHeight = boxHeight;
        this.repeat = repeat;
        this.backwards = backwards;
        this.frameTimeMS = frameTimeMS;
    }

    void addFrame(int x, int y, int w, int h, RGBAColor[] frameData) {
        frames ~= FrameInfo(x, y, w, h, frameData);
    }

    void addFrame(int x, int y, Surface frameImg) {
        frames ~= FrameInfo(x, y, frameImg);
    }

    void save(char[] outPath, char[] fnBase) {
        saveImageToFile(toBitmap(), outPath ~ pathsep ~ fnBase ~ ".png");
    }

    Surface toBitmap() {
        auto img = new Surface(Vector2i(boxWidth*frames.length, boxHeight));
        clearImage(img);
        foreach (int i, FrameInfo fi; frames) {
            fi.blitOn(img, i*boxWidth+fi.x, fi.y);
        }
        return img;
    }

    //store all animation bitmaps into the given texture atlas
    //simply updates the atlasIndex field for each frame (of all animations)
    void savePacked(AtlasPacker packer) {
        if (wasDumped)
            return;
        //NOTE: packer guarantees to number the blocks continuously
        int blockoffset = packer.blockCount();
        foreach (int iframe, inout FrameInfo fi; frames) {
            //request page and offset for frame from packer
            Block block = packer.alloc(Vector2i(fi.w, fi.h));
            fi.atlasIndex = block.page;
            fi.blockIndex = blockoffset + iframe;
            //blit frame data from animation onto page image
            fi.blitOn(packer.page(fi.atlasIndex), block.origin.x,
                block.origin.y);
        }
        wasDumped = true;
    }

    void free() {
        foreach (ref f; frames) {
            delete f.frameImg;
        }
        delete frames;
    }
}
