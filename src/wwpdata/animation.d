module wwpdata.animation;

import framework.imgwrite;
import framework.surface;
import framework.texturepack;
import wwptools.image;
import utils.stream;
import wwpdata.common;
import utils.boxpacker;
import utils.rect2;
import utils.vector2;
import utils.filetools;
import utils.misc;

//XXXTANGO
enum pathsep = "/";

//xxx should be moved somewhere else, no reason to compile this into the game
void saveAnimations(RawAnimation[] animations, char[] outPath, char[] fnBase,
    bool tosubdir = true)
{
    //scope stMeta = new File(outPath ~ pathsep ~ fnBase ~ ".meta",
        //  FileMode.OutNew);
    foreach (int i, a; animations) {
        char[] afn, apath;
        if (tosubdir) {
            //ah, how I love those "intuitive" formatting parameters...
            afn = myformat("anim_%03d", i);
            apath = outPath ~ pathsep ~ fnBase;
            trymkdir(apath);
        } else {
            afn = fnBase;
            apath = outPath;
        }
        saveImageToFile(a.toBitmap(), apath ~ pathsep ~ afn ~ ".png");
        Stdout.format("Saving %s/%s   \r",i+1 , animations.length);
        Stdout.flush();
    }
    Stdout.newline; //??
}

//free the data violently (with delete)
void freeAnimations(ref RawAnimation[] animations) {
    foreach (a; animations) {
        a.free();
    }
    delete animations;
}

class RawAnimation {
    WWPPalette palette;
    Vector2i box;
    bool repeat, backwards;
    int frameTimeMS;

    //packer that was used with savePacked()
    //is null if savePacked() wasn't called yet
    TexturePack packer;

    //hack to check for unused animations
    bool seen;

    struct FrameInfo {
        Vector2i at;    //position of the frame image inside animation
        Vector2i size;  //size of the frame image (see data)
        ubyte[] data;   //image (uses palette)
        SubSurface image; //converted image (valid if savePacked() was used)

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
        this.box = Vector2i(boxWidth, boxHeight);
        this.repeat = repeat;
        this.backwards = backwards;
        this.frameTimeMS = frameTimeMS;
    }

    void addFrame(int x, int y, int w, int h, ubyte[] frameData) {
        assert(frameData.length == w*h);
        frames ~= FrameInfo(Vector2i(x, y), Vector2i(w, h), frameData);
    }

    Surface frameToBitmap(FrameInfo frame) {
        auto res = new Surface(frame.size);
        blitPALData(res, palette, frame.data, Rect2i(frame.size));
        return res;
    }

    //store as strip (only useful for inspecting animations with unworms)
    Surface toBitmap() {
        auto img = new Surface(Vector2i(box.x*frames.length, box.y));
        foreach (int i, FrameInfo fi; frames) {
            blitPALData(img, palette, fi.data, Rect2i.Span(
                Vector2i(i*box.x+fi.at.x, fi.at.y), fi.size));
        }
        return img;
    }

    //like toBitmap(), but tile in both directions in order to avoid extreme
    //  bitmap widths that would cause trouble with some OpenGL drivers
    Surface toBitmapCompact() {
        assert(box.x > 0 && box.y > 0);
        //approximate LOL-estimate for min width/height
        auto len = cast(int)sqrt(frames.length*box.x*box.y*1.0);
        while ((len/box.x) * (len/box.y) < frames.length)
            len++;
        auto img = new Surface(Vector2i(len));
        //and tile the frames
        int cur = 0;
        for (int y = 0; y < img.size.y; y += box.y) {
            for (int x = 0; x < img.size.x; x += box.x) {
                if (cur < frames.length) {
                    auto fi = frames[cur];
                    blitPALData(img, palette, fi.data,
                        Rect2i.Span(Vector2i(x, y) + fi.at, fi.size));
                    cur++;
                }
            }
        }
        return img;
    }

    //store all animation bitmaps into the given texture atlas
    //simply updates the blockIndex field for each frame (of all animations)
    void savePacked(TexturePack packer) {
        //already dumped?
        if (this.packer)
            return;
        this.packer = packer;
        foreach (int iframe, ref FrameInfo fi; frames) {
            //request page and offset for frame from packer
            auto sub = packer.add(fi.size);
            //blit frame data from animation onto page image
            blitPALData(sub.surface, palette, fi.data, sub.rect);
            fi.image = sub;
        }
    }

    void free() {
        foreach (ref f; frames) {
            delete f.data;
        }
        delete frames;
    }
}
