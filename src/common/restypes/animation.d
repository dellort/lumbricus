module common.restypes.animation;

import common.animation;
import common.resfileformats;
import common.resources;
import common.resset;
import framework.drawing;
import framework.filesystem;
import framework.surface;
import framework.imgread;
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


//placeholder animation when loading failed; just displays error.png
class ErrorAnimation : Animation {
    private SubSurface mError;
    this() {
        mError = loadImage("error.png").fullSubSurface();
        doInit(1, mError.rect.centeredAt(Vector2i(0)), 0);
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
        if (mAnim.lengthMS <= 0)
            return 1.0f;

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
        int frameCount = config.getIntValue("frame_count", -1);
        auto surface = loadImage(filename);
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
        outer: for (int y = 0; y < surface.size.y; y += frameHeight) {
            for (int x = 0; x < surface.size.x; x += frameWidth) {
                if (frameCount >= 0 && frames.length >= frameCount)
                    break outer;
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
            Surface s = loadImage(f);
            SubSurface sub = s.fullSubSurface();
            frames ~= sub;
        }
        init_frames(frames);
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
