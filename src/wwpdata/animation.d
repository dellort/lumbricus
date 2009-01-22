module wwpdata.animation;

import aconv.atlaspacker;
import devil.image;
import path = stdx.path;
import str = stdx.string;
import stdx.file;
import stdx.stream;
import stdx.stdio;
import wwpdata.common;
import utils.boxpacker;
import utils.vector2;

class AnimList {
    Animation[] animations;

    void save(char[] outPath, char[] fnBase, bool tosubdir = true) {
        scope stMeta = new File(outPath ~ path.sep ~ fnBase ~ ".meta",
            FileMode.OutNew);
        foreach (int i, Animation a; animations) {
            char[] afn, apath;
            if (tosubdir) {
                afn = "anim_" ~ str.toString(i);
                apath = outPath ~ path.sep ~ fnBase;
                try { mkdir(apath); } catch {};
            } else {
                afn = fnBase;
                apath = outPath;
            }
            a.save(apath, afn);
            writef("Saving %d/%d   \r",i+1, animations.length);
            //fflush(stdout);
        }
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
            RGBColor[] frameData)
        {
            auto img = new Image(w, h, false);
            img.blitRGBData(frameData.ptr, w, h, 0, 0, false);
            return opCall(x, y, img);
        }

        void blitOn(Image dest, int x, int y) {
            dest.blit(frameImg, 0, 0, w, h, x, y);
        }

        ///saves only this frames' bitmap colorkeyed without filling box
        void save(char[] filename) {
            auto img = new Image(w, h, false);
            img.clear(COLORKEY.r, COLORKEY.g, COLORKEY.b, 1);
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

    void addFrame(int x, int y, int w, int h, RGBColor[] frameData) {
        frames ~= FrameInfo(x, y, w, h, frameData);
    }

    void addFrame(int x, int y, Image frameImg) {
        frames ~= FrameInfo(x, y, frameImg);
    }

    void save(char[] outPath, char[] fnBase) {
        auto img = new Image(boxWidth*frames.length, boxHeight, false);
        img.clear(COLORKEY.r, COLORKEY.g, COLORKEY.b, 1);
        foreach (int i, FrameInfo fi; frames) {
            fi.blitOn(img, i*boxWidth+fi.x, fi.y);
        }
        img.save(outPath ~ path.sep ~ fnBase ~ ".png");
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
