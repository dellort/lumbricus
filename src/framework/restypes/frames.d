module framework.restypes.frames;

//import common.animation;

import framework.drawing;
import framework.resfileformats;
import framework.framework;
import framework.resources;
import framework.restypes.atlas;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;

import std.stream;
debug import std.stdio;

//xxx the following two types should be in common.animation

//used in the game: p1 = thing/worm angle, p2 = weapon angle
struct AnimationParams {
    int p1, p2;
}

//for some derived classes see framework.restypes.frames
abstract class Animation {
    public /+private+/ {
        int mFrameTimeMS = 50;
        int mFrameCount;
        int mLengthMS;
        Rect2i mBounds;
    }

    //read-only lol
    bool keepLastFrame; //when animation over, the last frame is displayed
    bool repeat; //animation is repeated (starting again after last frame)

    abstract void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        int frame);

    private void postInit() {
        mLengthMS = mFrameTimeMS * mFrameCount;
    }

    //must call this
    protected void doInit(int aframeCount, Rect2i abounds, bool arepeat = true,
        bool akeeplast = false)
    {
        repeat = arepeat;
        keepLastFrame = akeeplast;
        mFrameCount = aframeCount;
        mBounds = abounds;

        postInit();
    }

    //deliver the bounds, centered around the center
    final Rect2i bounds() {
        return mBounds;
    }

    //time to play it (ignores repeat)
    Time duration() {
        return timeMsecs(mLengthMS);
    }

    int frameCount() {
        return mFrameCount;
    }
}

//--- simple old animations

//supports one animation whose frames are aligned horizontally on one bitmap
//xxx currently, no optimized mirroring support, as this would need
//     - FW support for mirrored drawing
//     - method to query FW if acceleration is available
//     - (already possible) registering a cache releaser with FW, think
//       of switching from GL to SDL driver mid-game, which would suddenly
//       require a cached mirror surface
//    or put surface mirroring support into FW
class AnimationStrip : Animation {
    private {
        Surface mSurface;
        Vector2i mFrameSize, mCenterOffset;
    }

    //frameWidth is the x size (in pixels) of one animation frame,
    //and needs to be a factor of the total image width
    //if frameWidth == -1, frames will be square (height x height)
    this(char[] filename, int frameWidth) {
        mSurface = gFramework.loadImage(filename);
        if (frameWidth < 0)
            frameWidth = mSurface.size.y;
        mFrameSize = Vector2i(frameWidth, mSurface.size.y);
        auto framecount = mSurface.size.x / frameWidth;
        mCenterOffset = -mFrameSize / 2;
        auto bounds = Rect2i(mCenterOffset, -mCenterOffset);
        doInit(framecount, bounds);
    }

    //(ignores the params p intentionally)
    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        int frameIdx)
    {
        //no wrap-around
        assert(frameIdx < frameCount);
        c.draw(mSurface, pos+mCenterOffset,
            Vector2i(mFrameSize.x*frameIdx, 0), mFrameSize);
    }
}

//--- slightly more complicated animations, with support for texture atlases

//storage for the binary parts of animations
//one instance of this class per binary files, supporting multiple animations
class AniFrames {
    struct Frames {
        Rect2i box; //animation box (not really a bounding box, see animconv)
        //for the 2 following arrays, the indices are: 0 == a, 1 == b
        int[2] mapParam; //mMapParam[index] => which of AnimationParamType
        int[2] counts; //frame counts for A and B directions
        int flags; //bitfield of FileAnimationFlags
        //rectangular array, with the dimensions as in counts[]
        FileAnimationFrame[] frames;

        FileAnimationFrame* getFrame(int a, int b) {
            assert(a >= 0 && a < counts[0]);
            assert(b >= 0 && b < counts[1]);
            return &frames[counts[0]*b+a];
        }
    }

    private {
        Frames[] mAnimations;
        Atlas mImages;
    }

    //the AniFramesResource references an atlas and a binary data file
    //the data file contains indices which must directly match the atlas data
    this(Atlas images, Stream data) {
        mImages = images;
        //xxx: I know I shouldn't use the structs directly from the stream,
        //  because the endianess etc. might be different on various platforms
        //  the sizes and alignments are ok though, so who cares?
        FileAnimations header;
        data.readExact(&header, header.sizeof);
        mAnimations.length = header.animationCount;
        foreach (inout anim; mAnimations) {
            FileAnimation fani;
            data.readExact(&fani, fani.sizeof);
            anim.mapParam[] = fani.mapParam;
            anim.counts[] = fani.frameCount;
            anim.flags = fani.flags;
            anim.frames.length = anim.counts[0] * anim.counts[1];
            data.readExact(anim.frames.ptr, anim.frames.length *
                typeof(anim.frames[0]).sizeof);

            auto size = Vector2i(fani.size[0], fani.size[1]);
            anim.box.p1 = -size/2; //(center around (0,0))
            anim.box.p2 = size + anim.box.p1;
        }
    }

    //get the frames of an animation
    final Frames frames(int frame_index) {
        return mAnimations[frame_index];
    }

    final int count() {
        return mAnimations.length;
    }

    final Atlas images() {
        return mImages;
    }

    //calculate bounds, xxx slight code duplication with drawFrame()
    Rect2i framesBoundingBox(int frame_index) {
        Rect2i bnds = Rect2i.Empty();
        foreach (inout frame; frames(frame_index).frames) {
            auto image = images.texture(frame.bitmapIndex);
            auto origin = Vector2i(frame.centerX, frame.centerY);
            bnds.extend(origin);
            bnds.extend(origin + image.size);
        }
        return bnds;
    }
}

class AniFramesResource : ResourceBase!(AniFrames) {
    private {
        AtlasResource mAtlas; //"preload"
        ConfigNode mNode;
    }

    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
        mNode = castStrict!(ConfigNode)(mConfig);
        mAtlas = gFramework.resources.resource!(AtlasResource)(
            mNode.getPathValue("atlas"));
    }

    protected void load() {
        mContents = new AniFrames(mAtlas.get(),
            gFramework.fs.open(mNode.getPathValue("datafile")));
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("aniframes");
    }
}

//handlers to convert a parameter to an actual frame
//  p = the source parameter
//  count = number of frames available
//  returns sth. useful between [0, count)
//wonderful type name!
alias int function(int p, int count) AnimationParamConvertDelegate;
AnimationParamConvertDelegate[char[]] gAnimationParamConverters;

//complicated version which supports parameters and loading from atlas/animation
//files (i.e. the frames are stored in a binary stream)
class ComplicatedAnimation : Animation {
    private {
        //animation data
        AniFrames.Frames mFrames;
        //the indices mean: [0] for p1, [1] for p2
        AnimationParamConvertDelegate[2] mParamConvert;
        Atlas mImages;
    }

    this(ConfigNode node) {
        AniFrames frames = gFramework.resources.resource!(AniFramesResource)
            (node.getPathValue("aniframes")).get();
        mImages = frames.images;
        int index = node.getIntValue("index", -1);
        mFrames = frames.frames(index);
        Rect2i bb = mFrames.box; // = frames.framesBoundingBox(index);

        void loadParamStuff(int index, char[] name) {
            auto val = node.getStringValue(name, "none");
            if (!(val in gAnimationParamConverters)) {
                assert(false, "not found; add error handling");
            }
            mParamConvert[index] = gAnimationParamConverters[val];
        }

        loadParamStuff(0, "param_1");
        loadParamStuff(1, "param_2");

        //find out how long this is - needs reverse lookup
        //default value 1 in case time isn't used for a param (not animated)
        int framelen = 1;
        for (int i = 0; i < 2; i++) {
            if (mFrames.mapParam[i] == FileAnimationParamType.Time) {
                framelen = mFrames.counts[i];
                break;
            }
        }

        doInit(framelen, bb);

        repeat = !!(mFrames.flags & FileAnimationFlags.Repeat);
        keepLastFrame = !!(mFrames.flags & FileAnimationFlags.KeepLastFrame);
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        int frameIdx)
    {
        assert(frameIdx < frameCount);

        static int doParam(int function(int a, int b) dg, int v, int count) {
            v = dg(v, count);
            if (v < 0 || v >= count) {
                debug writefln("WARNING: parameter out of bounds");
                v = 0;
            }
            return v;
        }

        int selectParam(int index) {
            int cnt = mFrames.counts[index]; //only used with params
            switch (mFrames.mapParam[index]) {
                case FileAnimationParamType.Time:
                    return frameIdx;
                case FileAnimationParamType.P1:
                    return doParam(mParamConvert[0], p.p1, cnt);
                case FileAnimationParamType.P2:
                    return doParam(mParamConvert[1], p.p2, cnt);
                default:
                    return 0;
            }
        }

        auto frame = mFrames.getFrame(selectParam(0), selectParam(1));
        auto image = mImages.texture(frame.bitmapIndex);

        c.draw(image.surface, pos+Vector2i(frame.centerX, frame.centerY),
            image.origin, image.size,
            !!(frame.drawEffects & FileDrawEffects.MirrorY));
    }
}

//resource for animation frames
//will load the anim file on get()
//config item   type = "xxx"   chooses Animation implementation
class AnimationResource : ResourceBase!(Animation) {
    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
    }

    protected void load() {
        ConfigNode node = cast(ConfigNode)mConfig;
        assert(node !is null);
        char[] type = node.getStringValue("type", "");
        switch (type) {
            case "strip":
                char[] fn = node.getPathValue("file");
                int frameWidth = node.getIntValue("frame_width", -1);
                mContents = new AnimationStrip(fn, frameWidth);
                break;
            case "complicated":
                mContents = new ComplicatedAnimation(node);
                break;
            default:
                //assuming the "prehistoric" thingy used in level themes
                char[] fn = node.getPathValue("image");
                int frameWidth = node.getIntValue("width", -1);
                mContents = new AnimationStrip(fn, frameWidth);
                mContents.repeat = node.getBoolValue("repeat", true);
                break;
                //assert(false, "Invalid frame resource type");
        }
    }

    override protected void doUnload() {
        mContents = null; //let the GC do the work
        super.doUnload();
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("animations");
    }
}
