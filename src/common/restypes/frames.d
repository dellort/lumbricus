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
