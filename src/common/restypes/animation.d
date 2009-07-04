module common.restypes.animation;

import common.resfileformats;
import common.resources;
import common.restypes.frames;
import framework.drawing;
import framework.framework;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;


//xxx the following two types should be in common.animation

//used in the game: p1 = thing/worm angle, p2 = weapon angle
struct AnimationParams {
    int p1, p2;
}

//for some derived classes see below
abstract class Animation {
    public /+private+/ {
        const int cDefFrameTimeMS = 50;
        int mFrameTimeMS;
        int mFrameCount;
        int mLengthMS;
        Rect2i mBounds;
        ReversedAnimation mReversed;
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
        bool akeeplast = false, int aframeTimeMS = cDefFrameTimeMS)
    {
        repeat = arepeat;
        keepLastFrame = akeeplast;
        mFrameCount = aframeCount;
        mBounds = abounds;
        mFrameTimeMS = aframeTimeMS;
        if (mFrameTimeMS == 0)
            mFrameTimeMS = cDefFrameTimeMS;

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

    int frameTimeMS() {
        return mFrameTimeMS;
    }

    Time frameTime() {
        return timeMsecs(mFrameTimeMS);
    }

    private int relFrameTimeMs(Time t) {
        assert(mLengthMS != 0);
        if (t.msecs >= mLengthMS) {
            //if this has happened, we either need to show a new frame,
            //disappear or just stop it
            if (!repeat) {
                return mLengthMS;
            }
            return t.msecs % mLengthMS;
        }
        return t.msecs;
    }

    int getFrameIdx(Time t) {
        int ft = relFrameTimeMs(t);
        assert(ft <= mLengthMS);
        if (ft == mLengthMS) {
            assert(!repeat);
            if (keepLastFrame) {
                return mFrameCount - 1;
            } else {
                return -1;
            }
        }
        int frame = ft / mFrameTimeMS;
        assert(frame >= 0 && frame < mFrameCount);
        return frame;
    }

    void draw(Canvas c, Vector2i pos, ref AnimationParams p, Time t) {
        int frame = getFrameIdx(t);
        if (frame < 0)
            return;
        drawFrame(c, pos, p, frame);
    }

    bool finished(Time t) {
        return (t.msecs >= mLengthMS && !repeat);
    }

    //default: create a proxy
    //of course a derived class could override this and create a normal
    //animation with a reversed frame list
    Animation reversed() {
        if (!mReversed)
            mReversed = new ReversedAnimation(this);
        return mReversed;
    }
}

class ReversedAnimation : Animation {
    private {
        Animation mBase;
    }

    this(Animation base) {
        mBase = base;
        //keepLastFrame makes no sense here (last frame becomes the first)
        doInit(mBase.frameCount, mBase.bounds, mBase.repeat,
            false, mBase.frameTimeMS);
    }

    void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p, int frame) {
        mBase.drawFrame(c, pos, p, frameCount() - 1 - frame);
    }

    //hurhur
    Animation reversed() {
        return mBase;
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
        debug gResources.ls_start("AnimationStrip:loadImage");
        mSurface = gFramework.loadImage(filename);
        debug gResources.ls_stop("AnimationStrip:loadImage");
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
        Frames mFrames;
        //the indices mean: [0] for p1, [1] for p2
        AnimationParamConvertDelegate[2] mParamConvert;
    }

    this(ConfigNode node, AniFrames frames) {
        int index = node.getIntValue("index", -1);
        int frameTimeMS = node.getIntValue("frametime", 0);
        mFrames = frames.frames(index);
        Rect2i bb = mFrames.box; // = mFrames.boundingBox();

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
        foreach (ref par; mFrames.params) {
            if (par.map == FileAnimationParamType.Time) {
                framelen = par.count;
                break;
            }
        }

        doInit(framelen, bb, true, false, frameTimeMS);

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
                debug Trace.formatln("WARNING: parameter out of bounds");
                v = 0;
            }
            return v;
        }

        int selectParam(int index) {
            int cnt = mFrames.params[index].count; //only used with params
            switch (mFrames.params[index].map) {
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

        mFrames.drawFrame(c, pos, selectParam(0), selectParam(1),
            selectParam(2));
    }
}

//resource for animation frames
//will load the anim file on get()
//config item   type = "xxx"   chooses Animation implementation
class AnimationResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        ConfigNode node = mConfig;
        assert(node !is null);
        char[] type = node.getStringValue("type", "");
        switch (type) {
            case "strip":
                char[] fn = mContext.fixPath(node["file"]);
                int frameWidth = node.getIntValue("frame_width", -1);
                auto ani = new AnimationStrip(fn, frameWidth);
                ani.repeat = node.getBoolValue("repeat", ani.repeat);
                mContents = ani;
                break;
            case "complicated":
                auto frames = castStrict!(AniFrames)(
                    mContext.find(node["aniframes"]).get());
                mContents = new ComplicatedAnimation(node, frames);
                break;
            default:
                throw new Exception("invalid AnimationResource type");
        }
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("animations");
    }
}
