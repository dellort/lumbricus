module common.restypes.frames;

import common.resfileformats;
import common.resources;
import common.restypes.atlas;
import framework.config;
import framework.filesystem;
import framework.drawing;
import framework.surface;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;

import utils.stream;

//overview over the indirection crap:
//- a ComplicatedAnimation uses one item of AniFramesAtlas (a Frames instance)
//- an AniFramesAtlas is a list of Frames (each describes an animation), and
//  references an Atlas (list of bitmaps)
//- each Frames describes how an animation and its parameters map to the Atlas
//- the reason is that we thought putting all animations into a single Atlas
//  would be more efficient, because space is better used and you can batch-
//  load the animation graphics at once (each Atlas page is big => less
//  overhead due to loading small files)
//- also, OpenGL is more efficient if you use large texture pages
//- at least that was the theory
//- actually, if you'd care about efficiency, you'd have to pack atlas/texture
//  pages according to use (it's most important to minimize GL texture changes)
//
//all this stuff is relatively animconv specific, which exist just to deal with
//  the WWP data

///one animation, contained in an AniFrames instance
//represents frame/image data for 1 animation
//xxx better name?
abstract class Frames {
    struct ParamData {
        int map;   //which of AnimationParamType
        int count; //frame counts for A and B directions
        char[] conv; //converter to map input parameter to frame number
    }

    Rect2i box; //animation box (not really a bounding box, see animconv)
    //for the following array, the indices are: 0 == a, 1 == b
    ParamData[3] params;
    int flags; //bitfield of FileAnimationFlags
    int frameTimeMS; //framerate

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
    ///get the frames of an animation (return null on out-of-bounds)
    abstract Frames frames(int anim_index);
    abstract int count();
}

class ErrorAniFrames : AniFrames {
    Frames frames(int anim_index) {
        return null;
    }
    override int count() {
        return 0;
    }
}

//--- slightly more complicated animations, with support for texture atlases

class AtlasFrames : Frames {
    //rectangular array, with the dimensions as in params[].count
    FileAnimationFrame[] frames;
    Atlas atlas;

    //takes over ownership of a_frames' memory
    this(Atlas a_atlas, AnimationData a_data) {
        atlas = a_atlas;

        foreach (int i, ref par; params) {
            //xxx what was the point? params.length==mapParam.length==const 3
            assert(i < a_data.info.mapParam.length);
            par.map = a_data.info.mapParam[i];
            par.count = a_data.info.frameCount[i];
            par.conv = a_data.param_conv[i];
        }

        flags = a_data.info.flags;
        frameTimeMS = a_data.info.frametime_ms;

        frames = a_data.frames;
        argcheck(frames.length == frameCount());

        auto size = Vector2i(a_data.info.size[0], a_data.info.size[1]);
        box.p1 = -size/2; //(center around (0,0))
        box.p2 = size + box.p1;
    }

    void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3) {
        int idx = getFrameIdx(p1, p2, p3);
        FileAnimationFrame* frame = &frames[idx];
        auto image = atlas.texture(frame.bitmapIndex);

        //error
        if (!image)
            return;

        BitmapEffect eff;
        eff.mirrorY = !!(frame.drawEffects & FileDrawEffects.MirrorY);

        c.drawSprite(image, pos+Vector2i(frame.centerX, frame.centerY), &eff);
    }

    //calculate bounds, xxx slight code duplication with drawFrame()
    Rect2i boundingBox() {
        Rect2i bnds = Rect2i.Abnormal();
        foreach (inout frame; frames) {
            auto image = atlas.texture(frame.bitmapIndex);
            if (image) {
                auto origin = Vector2i(frame.centerX, frame.centerY);
                bnds.extend(origin);
                bnds.extend(origin + image.size);
            }
        }
        return bnds;
    }
}


//storage for the binary parts of animations
//one instance of this class per binary files, supporting multiple animations
class AniFramesAtlas : AniFrames {
    private {
        Frames[] mAnimations;
    }

    //the AniFramesAtlasResource references an atlas and a binary data file
    //the data file contains indices which must directly match the atlas data
    this(Atlas images, Stream data) {
        AnimationData[] anis = readAnimations(data);
        foreach (ref ani; anis) {
            mAnimations ~= new AtlasFrames(images, ani);
        }
        delete anis;
    }

    override Frames frames(int anim_index) {
        if (indexValid(mAnimations, anim_index))
            return mAnimations[anim_index];
        else
            return null;
    }

    override int count() {
        return mAnimations.length;
    }
}

class AniFramesAtlasResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        try {
            auto node = mConfig;
            auto atlas = mContext.findAndGetT!(Atlas)(node["atlas"]);
            auto file = gFS.open(mContext.fixPath(node["datafile"]));
            scope(exit) file.close();
            mContents = new AniFramesAtlas(atlas, file);
        } catch (CustomException e) {
            loadError(e);
            mContents = new ErrorAniFrames();
        }
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("aniframes");
    }
}
