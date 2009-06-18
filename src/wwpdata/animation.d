module wwpdata.animation;

import aconv.atlaspacker;
import devil.image;
import stdx.stream;
import wwpdata.common;
import utils.boxpacker;
import utils.vector2;
import utils.filetools;
import utils.misc;
import tango.io.Stdout;

//dear tango team, please make things more convenient
import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

class AnimList {
    Animation[] animations;

    void save(char[] outPath, char[] fnBase, bool tosubdir = true) {
        scope stMeta = new File(outPath ~ pathsep ~ fnBase ~ ".meta",
            FileMode.OutNew);
        foreach (int i, Animation a; animations) {
            char[] afn, apath;
            if (tosubdir) {
                afn = myformat("anim_{}", i);
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
    void free() {
        foreach (a; animations) {
            a.free();
        }
        delete animations;
    }
}

class Animation {
    int boxWidth, boxHeight;
    bool repeat, backwards;
    int frameTimeMS;

    //if bitmaps already were written out
    bool wasDumped;

    struct FrameInfo {
        int x, y, w, h;
        int atlasIndex; //page in the atlas it was packaged into (never needed??)
        int blockIndex; //index of the texture in the atlas
        Image frameImg;

        static FrameInfo opCall(int x, int y, Image frameData) {
            FrameInfo ret;
            ret.x = x;
            ret.y = y;
            ret.w = frameData.w;
            ret.h = frameData.h;
            ret.frameImg = frameData;
            return ret;
        }

        static FrameInfo opCall(int x, int y, int w, int h,
            RGBAColor[] frameData)
        {
            auto img = new Image(w, h);
            img.blitRGBData(frameData, w, h);
            return opCall(x, y, img);
        }

        void blitOn(Image dest, int x, int y) {
            dest.blit(frameImg, 0, 0, w, h, x, y);
        }

        ///saves only this frames' bitmap colorkeyed without filling box
        void save(char[] filename) {
            auto img = new Image(w, h);
            img.clear(0, 0, 0, 0);
            blitOn(img, 0, 0);
            img.save(filename);
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

    void addFrame(int x, int y, Image frameImg) {
        frames ~= FrameInfo(x, y, frameImg);
    }

    void save(char[] outPath, char[] fnBase) {
        auto img = new Image(boxWidth*frames.length, boxHeight);
        img.clear(0, 0, 0, 0);
        foreach (int i, FrameInfo fi; frames) {
            fi.blitOn(img, i*boxWidth+fi.x, fi.y);
        }
        img.save(outPath ~ pathsep ~ fnBase ~ ".png");
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
