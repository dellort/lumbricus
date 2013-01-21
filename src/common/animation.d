module common.animation;

import common.scene;
import framework.drawing;
import utils.misc;
import utils.timesource;
import utils.rect2;
import utils.time;
import utils.vector2;

enum int cDefFrameTimeMS = 50;

//--- animation display

class Animator : SceneObjectCentered {
    private {
        Animation mData;
        Time mStarted;
        Time mLastNow;
        TimeSourcePublic mTimeSource;

        Time now() {
            auto n = mTimeSource.current;
            //this can happen with interpolation, but maybe the code below
            //  can't handle it
            /*debug {
                assert(n >= mLastNow, "time running backwards lol");
                mLastNow = n;
            }*/
            if (n < mLastNow)
                n = mLastNow;
            mLastNow = n;
            return n;
        }
    }

    AnimationParams params;
    bool auto_remove;

    final TimeSourcePublic timeSource() {
        return mTimeSource;
    }

    this(TimeSourcePublic ts) {
        assert(!!ts); //for now, be nazi about it
        mTimeSource = ts;
    }

    //set new animation; or null to stop all
    void setAnimation(Animation d, Time startAt = Time.Null) {
        setAnimation2(d, now - startAt);
    }
    //with absolute start time
    void setAnimation2(Animation d, Time startTime) {
        mStarted = startTime;
        //xxx
        if (mStarted > now())
            mStarted = now();
        mData = d;
    }

    bool hasFinished() {
        if (!mData)
            return true;
        return (mData.finished(now() - mStarted));
    }

    int curFrame() {
        if (!mData)
            return -1;
        return mData.getFrameIdx(now() - mStarted);
    }

    override void draw(Canvas canvas) {
        if (!mData)
            return;
        Time t = now() - mStarted;
        if (auto_remove && mData.finished(t)) {
            removeThis();
            return;
        }
        mData.draw(canvas, pos, params, t);
    }

    //shall return the smallest bounding box for all frame, centered around pos.
    Rect2i bounds() {
        if (mData) {
            return mData.bounds() + pos;
        }
        return Rect2i.Abnormal;
    }

    Animation animation() {
        return mData;
    }
}

//--- animation data

//used in the game (typically, meanings are not fixed):
//  p[0] = thing/worm angle
//  p[1] = weapon angle
//  p[2] = team color index + 1, or 0 when neutral
struct AnimationParams {
    int[3] p;
}

//for some derived classes see below
abstract class Animation {
    private {
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
    final Rect2i bounds() { return mBounds; }
    //time to play it (ignores repeat)
    final Time duration() { return timeMsecs(mLengthMS); }
    final int lengthMS() { return mLengthMS; }
    final int frameCount() { return mFrameCount; }
    final int frameTimeMS() { return mFrameTimeMS; }
    final Time frameTime() { return timeMsecs(mFrameTimeMS); }

    static int relFrameTimeMs(Time t, int length_ms, bool repeat) {
        if (length_ms <= 0)
            return 0;

        int ms = cast(int)t.msecs;
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
            if (mFrameCount == 0 || mLengthMS == 0)
                return 0;
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

    //??
    alias drawFrame draw;

    bool finished(Time t) {
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

//--- helpers

class ReversedAnimation : Animation {
    private {
        Animation mBase;
    }

    this(Animation base) {
        mBase = base;
        copyAttributes(mBase);
        doInit(mBase.frameCount, mBase.bounds, mBase.frameTimeMS());
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p, Time t) {
        mBase.drawFrame(c, pos, p, duration() - t);
    }

    //hurhur
    override Animation reversed() {
        return mBase;
    }
}

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
    //the difference to this(base, frame, frame+1) is, that the duration is 0s
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

//--- optional debugging crap

//can be implemented by an Animation descendant, used by resview.d
interface DebugAniFrames {
    string[] paramInfos();
    int[] paramCounts();
    Rect2i frameBoundingBox();
    void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3);
}
