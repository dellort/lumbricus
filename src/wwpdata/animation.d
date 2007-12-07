module wwpdata.animation;

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

    int savePacked(char[] outPath, char[] fnBase, bool tosubdir = true,
        Vector2i pageSize = Vector2i(512,512), bool[int] filter = null)
    {
        scope packer = new BoxPacker;
        packer.pageSize = pageSize;
        Image[] pageImages;
        int maxPage = -1;

        //pack and draw individual frames onto block images of size pageSize
        foreach (int i, Animation a; animations) {
            if ((filter.length > 0) && !(i in filter)) {
                continue;
            }
            //write animation descriptor to metadata file
            foreach (int iframe, inout Animation.FrameInfo fi; a.frames) {
                //request page and offset for frame from packer
                Block* newBlock = packer.getBlock(Vector2i(fi.w, fi.h));
                if (newBlock.page >= pageImages.length) {
                    //a new page has been started, create a new image
                    auto img = new Image(pageSize.x, pageSize.y, false);
                    img.clear(COLORKEY.r, COLORKEY.g, COLORKEY.b, 1);
                    pageImages ~= img;
                    maxPage = newBlock.page;
                }
                //blit frame data from animation onto page image
                pageImages[newBlock.page].blitRGBData(fi.data.ptr, fi.w, fi.h,
                    newBlock.origin.x, newBlock.origin.y, false);
                fi.pageIndex = newBlock.page;
                fi.pageOffsetx = newBlock.origin.x;
                fi.pageOffsety = newBlock.origin.y;
            }
        }
        //save all generated block images to disk
        foreach (int i, img; pageImages) {
            char[] pagefn, pagepath;
            if (tosubdir) {
                pagefn = "page_" ~ str.toString(i);
                pagepath = outPath ~ path.sep ~ fnBase;
                try { mkdir(pagepath); } catch {};
            } else {
                pagefn = fnBase ~ str.toString(i);
                pagepath = outPath;
            }
            img.save(pagepath ~ path.sep ~ pagefn ~ ".png");
            writef("Saving %d/%d   \r",i+1, pageImages.length);
            fflush(stdout);
        }
        return maxPage;
    }
}

class Animation {
    int boxWidth, boxHeight;
    bool repeat, backwards;

    struct FrameInfo {
        int x, y, w, h;
        int pageIndex, pageOffsetx, pageOffsety;
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
            img.blitRGBData(fi.data.ptr, fi.w, fi.h, i*boxWidth+fi.x, fi.y, false);
        }
        img.save(outPath ~ path.sep ~ fnBase ~ ".png");
    }
}
