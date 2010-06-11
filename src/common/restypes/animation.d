module common.restypes.animation;

import common.resfileformats;
import common.resources;
import common.resset;
import common.restypes.frames;
import framework.drawing;
import framework.framework;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;
import utils.factory;
import utils.strparser;

import str = utils.string;
import math = tango.math.Math;
import mymath = utils.math;


//xxx the following two types should be in common.animation

//used in the game (typically, not fixed):
//  p1 = thing/worm angle
//  p2 = weapon angle
//  p3 = team color index + 1, or 0 when neutral
struct AnimationParams {
    int p1, p2, p3;
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
        bool mDidInit;
    }

    //read-only lol
    bool repeat = true;//animation is repeated (starting again after last frame)

    abstract void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t);

    private void postInit() {
        mLengthMS = mFrameTimeMS * mFrameCount;
    }

    //must call this
    protected void doInit(int aframeCount, Rect2i abounds,
        int aframeTimeMS = cDefFrameTimeMS)
    {
        assert(!mDidInit);

        //0 as frame time is indeed valid (makes only sense with framecount=1)
        argcheck(aframeTimeMS >= 0);
        argcheck(aframeCount > 0);

        mFrameCount = aframeCount;
        mBounds = abounds;
        mFrameTimeMS = aframeTimeMS;

        postInit();

        mDidInit = true;
    }

    //copy all animation attributes (except frame count) from other
    protected void copyAttributes(Animation other) {
        repeat = other.repeat;
        mBounds = other.mBounds;
        mFrameTimeMS = other.mFrameTimeMS;
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

    int lengthMS() {
        return mLengthMS;
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

    static int relFrameTimeMs(Time t, int length_ms, bool repeat) {
        assert(length_ms != 0);
        int ms = t.msecs;
        if (ms < 0) {
            //negative time needed for reversed animations
            //maybe also needed to set an animation start offset
            if (!repeat)
                return 0;
            ms = realmod(ms, length_ms);
        }
        if (ms >= length_ms) {
            //if this has happened, we either need to show a new frame,
            //disappear or just stop it
            if (!repeat) {
                return length_ms;
            }
            return ms % length_ms;
        }
        return ms;
    }

    int getFrameIdx(Time t) {
        assert(mDidInit);

        int ft = relFrameTimeMs(t, mLengthMS, repeat);
        assert(ft <= mLengthMS);
        if (ft == mLengthMS) {
            assert(!repeat);
            //always show last frame - gets rid of animation transition "gaps"
            //if you really want the animation to disappear after done, add an
            //  empty frame to the animation (using animconv), or just stop
            //  calling draw()
            return mFrameCount - 1;
        }
        int frame = ft / mFrameTimeMS;
        assert(frame >= 0 && frame < mFrameCount);
        return frame;
    }

    void draw(Canvas c, Vector2i pos, ref AnimationParams p, Time t) {
        drawFrame(c, pos, p, t);
    }

    bool finished(Time t) {
        //if (repeat)
        //    return false;
        return t.msecs >= mLengthMS;
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
        copyAttributes(mBase);
        doInit(mBase.frameCount, mBase.bounds, mBase.frameTimeMS());
    }

    void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p, Time t) {
        mBase.drawFrame(c, pos, p, duration() - t);
    }

    //hurhur
    Animation reversed() {
        return mBase;
    }
}

//this is silly, but I just needed that hack, feel free to replace+improve
class SubAnimation : Animation {
    private {
        Animation mBase;
        Time mFrameStart;
    }

    //subrange (frame_end is exclusive)
    this(Animation base, int frame_start, int frame_end) {
        mBase = base;
        argcheck(frame_start >= 0);
        argcheck(frame_end <= mBase.frameCount);
        argcheck(frame_start < frame_end); //also must be at least 1 frame
        copyAttributes(mBase);
        doInit(frame_end - frame_start, mBase.bounds, mBase.frameTimeMS());
        mFrameStart = frame_start * frameTime();
    }

    //fixed display of one frame of the base animation
    //the difference to this(base, frame, frame+1) is, that the framerate is 0
    //the animation literally will be finished before it has started
    this(Animation base, int frame) {
        mBase = base;
        argcheck(frame >= 0);
        argcheck(frame < mBase.frameCount);
        copyAttributes(mBase);
        doInit(1, mBase.bounds, 0);
        mFrameStart = frame * mBase.frameTime();
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t)
    {
        mBase.drawFrame(c, pos, p, mFrameStart + t);
    }
}

//displaying an animation is about mapping animation parameters (time, rotation,
//  and other stuff in AnimationParams) to drawing parameters (frame number,
//  rotation, mirroring)
//
//class Animation2 : Animation {
//}

//--- simple old animations

//placeholder animation when loading failed; just displays error.png
class ErrorAnimation : Animation {
    private SubSurface mError;
    this() {
        mError = gFramework.loadImage("error.png").fullSubSurface();
        doInit(1, mError.rect, 0);
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t)
    {
        c.drawSprite(mError, pos, null);
    }
}

//"Effects" manipulate drawing of simple animations (so you can do e.g. rotation
//  using OpenGL instead of hand-drawn frames)
alias StaticFactory!("AnimEffects", AnimEffect, Animation, ConfigNode)
    AnimEffectFactory;

//for parsing
enum AnimEffectParam {
    time,
    p1,
    p2,
    p3,
}
static this() {
    enumStrings!(AnimEffectParam, "time,p1,p2,p3");
}

//effect implementations derive from this class
//there's a lot of xxx here concerning parameter handling
abstract class AnimEffect {
    protected Animation mAnim;

    this(Animation parent) {
        mAnim = parent;
    }

    protected float relTime(Time t) {
        return 1.0f * Animation.relFrameTimeMs(t, mAnim.lengthMS, true)
            / mAnim.lengthMS;
    }

    abstract void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff);
}

abstract class AnimationSimple : Animation {
    private {
        SubSurface[] mFrames;
        AnimEffect[] mEffects;  //list of drawing effects
    }

    this(ConfigNode node) {
        //mFrames and mCenterOffset are loaded by subclasses
        //load generic parameters here (not related to the frame storage method)
        repeat = node.getBoolValue("repeat", repeat);
        mFrameTimeMS = node.getIntValue("frametime", cDefFrameTimeMS);
        foreach (ConfigNode sub; node) {
            if (sub.name == "effect") {
                mEffects ~= AnimEffectFactory.instantiate(sub.value, this,
                    sub);
            }
        }
    }

    //must call this in your ctor
    protected void init_frames(SubSurface[] frames) {
        assert(frames.length > 0);
        mFrames = frames;
        Vector2i frame_size;
        foreach (f; mFrames) {
            frame_size = frame_size.max(f.size);
        }
        doInit(mFrames.length, Rect2i(frame_size) - frame_size / 2,
            frameTimeMS);
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t)
    {
        //no wrap-around
        int frameIdx = getFrameIdx(t);
        if (frameIdx < 0)
            return;
        assert(frameIdx < frameCount);

        SubSurface frame = mFrames[frameIdx];
        BitmapEffect eff;
        eff.center = frame.size / 2;
        foreach (animEff; mEffects) {
            animEff.effect(pos, p, t, eff);
        }
        c.drawSprite(frame, pos, &eff);
    }
}

//supports one animation whose frames are aligned horizontally, vertically
//  or both on one bitmap
class AnimationStrip : AnimationSimple {
    //frameWidth is the x size (in pixels) of one animation frame,
    //frameHeight is the y size
    //both need to be a factor of the total image width/height
    //if frameWidth == -1 && frameHeight == -1, frames will be square (smallest)
    //else if only one given, other will be full image size
    this(ConfigNode config, char[] filename) {
        super(config);

        int frameWidth = config.getIntValue("frame_width", -1);
        int frameHeight = config.getIntValue("frame_height", -1);
        auto surface = gFramework.loadImage(filename);
        if (frameWidth < 0 && frameHeight < 0) {
            //square frames
            frameWidth = frameHeight = min(surface.size.x, surface.size.y);
        } else if (frameWidth < 0) {
            frameWidth = surface.size.x;
        } else if (frameHeight < 0) {
            frameHeight = surface.size.y;
        }
        auto frame_size = Vector2i(frameWidth, frameHeight);

        SubSurface[] frames;
        for (int y = 0; y < surface.size.y; y += frameHeight) {
            for (int x = 0; x < surface.size.x; x += frameWidth) {
                frames ~= surface.createSubSurface(Rect2i.Span(
                    Vector2i(x, y), frame_size));
            }
        }
        init_frames(frames);
    }
}

//animation from file list, each file is a frame image
class AnimationList : AnimationSimple {
    this(ConfigNode config, char[] pattern) {
        super(config);

        //dumb crap
        //shouldn't there be library functions for this?
        //actually, blame filesystem.d
        auto res = str.rfind(pattern, "/");
        char[] path, file;
        if (res < 0) {
            file = pattern;
        } else {
            path = pattern[0..res];
            file = pattern[res+1..$];
        }

        char[][] flist;
        gFS.listdir(path, file, false,
            (char[] filename) {
                //and of course we have to add the path again
                flist ~= path ~ "/" ~ filename;
                return true;
            }
        );

        if (!flist.length) {
            throw new LoadException("animation",
                myformat("no files found: '{}'", pattern));
        }

        //hopefully does the right thing; but only works if files are e.g.
        //  file01.png, file02.png, ..., file10.png
        //and not
        //  file1.png, file2.png, ..., file10.png
        flist.sort;

        SubSurface[] frames;
        foreach (f; flist) {
            Surface s = gFramework.loadImage(f);
            SubSurface sub = s.fullSubSurface();
            frames ~= sub;
        }
        init_frames(frames);
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
        //the indices mean: [0] for p1, [1] for p2, ...
        AnimationParamConvertDelegate[3] mParamConvert;
    }

    this(ConfigNode node, AniFrames frames) {
        int index = node.getIntValue("index", -1);
        int frameTimeMS = node.getIntValue("frametime", cDefFrameTimeMS);
        mFrames = frames.frames(index);
        if (!mFrames)
            throwError("frame index invalid: {}", index);
        Rect2i bb = mFrames.box; // = mFrames.boundingBox();

        void loadParamStuff(int index, char[] name) {
            auto val = node.getStringValue(name, "none");
            if (!(val in gAnimationParamConverters)) {
                assert(false, "not found; add error handling: '"~val~"'");
            }
            mParamConvert[index] = gAnimationParamConverters[val];
        }

        loadParamStuff(0, "param_1");
        loadParamStuff(1, "param_2");
        loadParamStuff(2, "param_3");

        //find out how long this is - needs reverse lookup
        //default value 1 in case time isn't used for a param (not animated)
        int framelen = 1;
        foreach (ref par; mFrames.params) {
            if (par.map == FileAnimationParamType.Time) {
                framelen = par.count;
                break;
            }
        }

        doInit(framelen, bb, frameTimeMS);

        repeat = !!(mFrames.flags & FileAnimationFlags.Repeat);
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t)
    {
        int frameIdx = getFrameIdx(t);
        if (frameIdx < 0)
            return;
        assert(frameIdx < frameCount);

        static int doParam(int function(int a, int b) dg, int v, int count) {
            v = dg(v, count);
            if (v < 0 || v >= count) {
                debug gLog.minor("WARNING: parameter out of bounds");
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
                case FileAnimationParamType.P3:
                    return doParam(mParamConvert[2], p.p3, cnt);
                default:
                    return 0;
            }
        }

        mFrames.drawFrame(c, pos, selectParam(0), selectParam(1),
            selectParam(2));
    }

    Frames frames() {
        return mFrames;
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
        try {
            char[] type = node.getStringValue("type", "");
            switch (type) {
                case "strip": {
                    char[] fn = mContext.fixPath(node["file"]);
                    mContents = new AnimationStrip(node, fn);
                    break;
                }
                //single image files, one per frame - born out of necessity
                //(to avoid dumb conversion steps like packing)
                case "list": {
                    //pat is like a filename, but with a wildcard ('*') in it
                    char[] pat = mContext.fixPath(node["pattern"]);
                    mContents = new AnimationList(node, pat);
                    break;
                }
                case "complicated":
                    auto frames = castStrict!(AniFrames)(
                        mContext.find(node["aniframes"]).get());
                    mContents = new ComplicatedAnimation(node, frames);
                    break;
                default:
                    throw new CustomException("invalid AnimationResource type");
            }
        } catch (CustomException e) {
            loadError(e);
            mContents = new ErrorAnimation();
        }
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("animations");
    }
}
