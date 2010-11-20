module wwpdata.animation;

import framework.imgwrite;
import framework.surface;
import wwptools.atlaspacker;
import wwptools.image;
import utils.stream;
import wwpdata.common;
import utils.boxpacker;
import utils.rect2;
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
    WWPPalette palette;
    int boxWidth, boxHeight;
    bool repeat, backwards;
    int frameTimeMS;

    //offset of the frame images into atlas_packer (after savePacked())
    // < 0 if savePacked() wasn't called yet
    int blockOffset = -1;
    AtlasPacker atlas_packer;

    struct FrameInfo {
        Vector2i at;    //position of the frame image inside animation
        Vector2i size;  //size of the frame image (see data)
        ubyte[] data;   //image (uses palette)

        FrameInfo dup() {
            FrameInfo n = *this;
            n.data = data.dup;
            return n;
        }
    }

    FrameInfo[] frames;

    this(WWPPalette palette, int boxWidth, int boxHeight, bool repeat,
        bool backwards, int frameTimeMS = 0)
    {
        this.palette = palette;
        this.boxWidth = boxWidth;
        this.boxHeight = boxHeight;
        this.repeat = repeat;
        this.backwards = backwards;
        this.frameTimeMS = frameTimeMS;
    }

    void addFrame(int x, int y, int w, int h, ubyte[] frameData) {
        assert(frameData.length == w*h);
        frames ~= FrameInfo(Vector2i(x, y), Vector2i(w, h), frameData);
    }

    void save(char[] outPath, char[] fnBase) {
        saveImageToFile(toBitmap(), outPath ~ pathsep ~ fnBase ~ ".png");
    }

    Surface frameToBitmap(FrameInfo frame) {
        auto res = new Surface(frame.size);
        blitPALData(res, palette, frame.data, Rect2i(frame.size));
        return res;
    }

    Surface toBitmap() {
        auto img = new Surface(Vector2i(boxWidth*frames.length, boxHeight));
        foreach (int i, FrameInfo fi; frames) {
            blitPALData(img, palette, fi.data, Rect2i.Span(
                Vector2i(i*boxWidth+fi.at.x, fi.at.y), fi.size));
        }
        return img;
    }

    //store all animation bitmaps into the given texture atlas
    //simply updates the blockIndex field for each frame (of all animations)
    void savePacked(AtlasPacker packer) {
        //already dumped=
        if (blockOffset >= 0)
            return;
        atlas_packer = packer;
        //NOTE: packer guarantees to number the blocks continuously
        blockOffset = packer.blockCount();
        foreach (int iframe, inout FrameInfo fi; frames) {
            //request page and offset for frame from packer
            Block block = packer.alloc(fi.size);
            //blit frame data from animation onto page image
            blitPALData(packer.page(block.page), palette, fi.data,
                Rect2i.Span(block.origin, fi.size));
        }
    }

    void free() {
        foreach (ref f; frames) {
            delete f.data;
        }
        delete frames;
    }
}
