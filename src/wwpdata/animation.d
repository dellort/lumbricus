module wwpdata.animation;

import aconv.atlaspacker;
import aconv.metadata;
import devil.image;
import path = std.path;
import str = std.string;
import std.file;
import std.stream;
import std.stdio;
import wwpdata.common;
import utils.boxpacker;
import utils.vector2;

class AnimList {
    Animation[] animations;

    void save(char[] outPath, char[] fnBase, bool tosubdir = true) {
        MyAnimationDescriptor animdesc;
        MyFrameDescriptor framedesc;
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
            animdesc.framecount = a.frames.length;
            animdesc.w = a.boxWidth;
            animdesc.h = a.boxHeight;
            animdesc.flags = (a.repeat?ANIMDESC_FLAGS_REPEAT:0)
                | (a.backwards?ANIMDESC_FLAGS_BACKWARDS:0);
            stMeta.writeBlock(&animdesc, MyAnimationDescriptor.sizeof);
            foreach (int iframe, Animation.FrameInfo fi; a.frames) {
                framedesc.offsetx = iframe*a.boxWidth + fi.x;
                framedesc.offsety = fi.y;
                framedesc.width = fi.w;
                framedesc.height = fi.h;
                stMeta.writeBlock(&framedesc, MyFrameDescriptor.sizeof);
            }
            writef("Saving %d/%d   \r",i+1, animations.length);
            fflush(stdout);
        }
    }
}

class Animation {
    int boxWidth, boxHeight;
    bool repeat, backwards;

    //if bitmaps already were written out
    bool wasDumped;

    struct FrameInfo {
        int x, y, w, h;
        int atlasIndex; //page in the atlas it was packaged into (never needed??)
        int blockIndex; //index of the texture in the atlas
        RGBColor[] data;

        static FrameInfo opCall(int x, int y, int w, int h, RGBColor[] frameData) {
            FrameInfo ret;
            ret.x = x;
            ret.y = y;
            ret.w = w;
            ret.h = h;
            ret.data = frameData;
            return ret;
        }

        void blitOn(Image dest, int x, int y) {
            dest.blitRGBData(data.ptr, w, h, x, y, false);
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

    this(int boxWidth, int boxHeight, bool repeat, bool backwards) {
        this.boxWidth = boxWidth;
        this.boxHeight = boxHeight;
        this.repeat = repeat;
        this.backwards = backwards;
    }

    void addFrame(int x, int y, int w, int h, RGBColor[] frameData) {
        frames ~= FrameInfo(x, y, w, h, frameData);
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
}
