module common.restypes.frames;

import common.config;
import common.resfileformats;
import common.resources;
import common.restypes.atlas;
import framework.drawing;
import framework.framework;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;

import utils.stream;

///one animation, contained in an AniFrames instance
//xxx better name?
abstract class Frames {
    struct ParamData {
        int map;   //which of AnimationParamType
        int count; //frame counts for A and B directions
    }

    Rect2i box; //animation box (not really a bounding box, see animconv)
    //for the following array, the indices are: 0 == a, 1 == b
    ParamData[3] params;
    int flags; //bitfield of FileAnimationFlags

    protected int getFrameIdx(int a, int b, int c) {
        assert(a >= 0 && a < params[0].count);
        assert(b >= 0 && b < params[1].count);
        assert(c >= 0 && c < params[2].count);
        return params[0].count*params[1].count*c + params[0].count*b + a;
    }

    ///The total number of frames in this animation
    int frameCount() {
        return params[0].count*params[1].count*params[2].count;
    }

    ///draw a frame of this animation, selected by parameters
    ///the center of the animation will be at pos
    abstract void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3);

    ///"correct" bounding box, calculated over all frames
    ///The animation center is at (0, 0) of this box
    abstract Rect2i boundingBox();
}

///just a container for a bunch of animations
abstract class AniFrames {
    protected {
        Frames[] mAnimations;
    }

    ///get the frames of an animation
    final Frames frames(int anim_index) {
        return mAnimations[anim_index];
    }

    ///the number of animations contained
    final int count() {
        return mAnimations.length;
    }
}

//--- slightly more complicated animations, with support for texture atlases

//storage for the binary parts of animations
//one instance of this class per binary files, supporting multiple animations
class AniFramesAtlas : AniFrames {
    private {
        class AtlasFrames : Frames {
            //rectangular array, with the dimensions as in params[].count
            FileAnimationFrame[] frames;

            void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3) {
                int idx = getFrameIdx(p1, p2, p3);
                FileAnimationFrame* frame = &frames[idx];
                auto image = mImages.texture(frame.bitmapIndex);

                c.draw(image.surface, pos+Vector2i(frame.centerX, frame.centerY),
                    image.origin, image.size,
                    !!(frame.drawEffects & FileDrawEffects.MirrorY));
            }

            //calculate bounds, xxx slight code duplication with drawFrame()
            Rect2i boundingBox() {
                Rect2i bnds = Rect2i.Empty();
                foreach (inout frame; frames) {
                    auto image = mImages.texture(frame.bitmapIndex);
                    auto origin = Vector2i(frame.centerX, frame.centerY);
                    bnds.extend(origin);
                    bnds.extend(origin + image.size);
                }
                return bnds;
            }
        }

        Atlas mImages;
    }

    //the AniFramesAtlasResource references an atlas and a binary data file
    //the data file contains indices which must directly match the atlas data
    this(Atlas images, Stream data) {
        debug gResources.ls_start("aniframes: parse");
        debug scope(exit) debug gResources.ls_stop("aniframes: parse");
        mImages = images;
        //xxx: I know I shouldn't use the structs directly from the stream,
        //  because the endianess etc. might be different on various platforms
        //  the sizes and alignments are ok though, so who cares?
        FileAnimations header;
        data.readExact(cast(ubyte[])(&header)[0..1]);
        for (int idx = 0; idx < header.animationCount; idx++) {
            AtlasFrames anim = new AtlasFrames();
            FileAnimation fani;
            data.readExact(cast(ubyte[])(&fani)[0..1]);
            foreach (int i, ref par; anim.params) {
                if (i < fani.mapParam.length) {
                    par.map = fani.mapParam[i];
                    par.count = fani.frameCount[i];
                } else {
                    par.map = 0;
                    par.count = 1;
                }
            }
            anim.flags = fani.flags;
            anim.frames.length = anim.frameCount();
            data.readExact(cast(ubyte[])anim.frames);

            auto size = Vector2i(fani.size[0], fani.size[1]);
            anim.box.p1 = -size/2; //(center around (0,0))
            anim.box.p2 = size + anim.box.p1;
            mAnimations ~= anim;
        }
    }
}

class AniFramesAtlasResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        auto node = mConfig;
        auto atlas = castStrict!(Atlas)(mContext.find(node["atlas"]).get());
        debug gResources.ls_start("aniframes: open");
        auto file = gFS.open(mContext.fixPath(node["datafile"]));
        scope(exit) file.close();
        debug gResources.ls_stop("aniframes: open");
        mContents = new AniFramesAtlas(atlas, file);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("aniframes");
    }
}

/+
class AniFramesSingle : AniFrames {
    class SingleFrames : Frames {
        struct SingleAnimationFrame {
            Surface img;
            bool mirrorY;
        }
        SingleAnimationFrame[] frames;

        void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3) {
            int idx = getFrameIdx(p1, p2, p3);
            SingleAnimationFrame* frame = &frames[idx];
            c.draw(frame.img, pos - frame.img.size/2, Vector2i(0),
                frame.img.size, frame.mirrorY);
        }

        Rect2i boundingBox() {
            return box;
        }
    }

    this(char[] path, ConfigNode node) {
        char[][] frameFiles = node.getValue!(char[][])("frames");
        char[] digits = node.getStringValue("digits", "3");
        int count = node.getValue!(int)("count");
        char[][] map = node.getValue!(char[][])("map");
        bool repeat = node.getValue!(bool)("repeat");
        bool keepLast = node.getValue!(bool)("keeplast");
        auto anim = new SingleFrames();
        anim.flags = (repeat?FileAnimationFlags.Repeat:0)
            | (keepLast?FileAnimationFlags.KeepLastFrame:0);
        foreach (int idx, char[] ps; map) {
            switch (ps) {
                case "time":
                    anim.params[idx].map = FileAnimationParamType.Time;
                    break;
                case "p1":
                    anim.params[idx].map = FileAnimationParamType.P1;
                    break;
                case "p2":
                    anim.params[idx].map = FileAnimationParamType.P2;
                    break;
                default:
            }
        }
        assert(anim.params[2].map == FileAnimationParamType.Null, "Unsupported");

        anim.params[0].count = count;
        anim.params[1].count = frameFiles.length;
        anim.params[2].count = 1;
        anim.frames.length = anim.frameCount;

        int curFrame = 0;
        foreach (int idx, char[] fn; frameFiles) {
            for (int frameIdx = 1; frameIdx <= count; frameIdx++) {
                assert(curFrame < anim.frames.length);
                Surface s = gFramework.loadImage(myformat("{}/{}{:d" ~ digits
                    ~ "}.png", path, fn, frameIdx));
                if (idx == 0 && frameIdx == 1) {
                    anim.box.p1 = -s.size/2;
                    anim.box.p2 = s.size + anim.box.p1;
                }
                anim.frames[curFrame].img = s;
                curFrame++;
            }
        }
        mAnimations ~= anim;
    }
}

class AniFramesSingleResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        auto node = mConfig;
        mContents = new AniFramesSingle(mContext.fixPath(node.name), node);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("singleframes");
    }
}
+/
