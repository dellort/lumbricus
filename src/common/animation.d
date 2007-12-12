module common.animation;

import common.common;
import common.scene;
import framework.framework;
import framework.restypes.frames;
import utils.rect2;
import utils.time;
import utils.vector2;

class AnimationData {
    private {
        int mFrameTimeMS = 20;
        int mLengthMS;
        FrameProvider mFrames;
        int mAnimId;
    }

    //repeat the animation
    bool repeat = true;

    //if not repeated: keep showing last frame when animation finished
    bool keepLastFrame = false;

    private void postInit() {
        mLengthMS = mFrameTimeMS * mFrames.frameCount(mAnimId);
    }

    /+this(ConfigFile node) {
        ....
        postInit();
    }+/

    //rather for debugging
    this(FrameProvider frameprov, int animId, bool arepeat = true,
        bool akeeplast = false)
    {
        repeat = arepeat;
        keepLastFrame = akeeplast;
        mFrames = frameprov;
        mAnimId = animId;
        assert(!!mFrames);

        postInit();
    }

    //deliver the bounds, centered around the center
    final Rect2i bounds() {
        return mFrames.bounds(mAnimId);
    }

    //time to play it (ignores repeat)
    Time duration() {
        return timeMsecs(mLengthMS);
    }

    int frameCount() {
        return mFrames.frameCount(mAnimId);
    }

    //create mirrored-animation
    //AnimationData createMirrored() {
    //    ... need to get a mirrored version of each frame's bitmap ...
    //}
    //or backwards-animation
    //AnimationData createBackwards() {
    //    ... reverse frame list ...
    //}
}

class Animation : SceneObjectCentered {
    private {
        AnimationData mData;
        Time mStarted;

        static Time now() {
            return globals.gameTimeAnimations.current;
        }
    }

    private int frameTime() {
        assert(mData && mData.mLengthMS != 0);
        int t = (now() - mStarted).msecs;
        if (t >= mData.mLengthMS) {
            //if this has happened, we either need to show a new frame,
            //disappear or just stop it
            if (!mData.repeat) {
                return mData.mLengthMS;
            }
            t = t % mData.mLengthMS;
            mStarted = now() + timeMsecs(-t);
        }
        return t;
    }

    int curFrame() {
        if (!mData)
            return -1;

        int t = frameTime();
        assert(t <= mData.mLengthMS);
        if (t == mData.mLengthMS) {
            assert(!mData.repeat);
            if (mData.keepLastFrame) {
                return mData.frameCount-1;
            } else {
                return -1;
            }
        }
        int frame = t / mData.mFrameTimeMS;
        assert(frame >= 0 && frame < mData.frameCount);
        return frame;
    }

    Time getTime() {
        return timeMsecs(frameTime);
    }

    //set new animation; or null to stop all
    void setAnimation(AnimationData d, Time startAt = Time.Null) {
        mStarted = now - startAt; //;D
        mData = d;
        if (mData) {
            //can't handle these cases
            assert(mData.frameCount > 0);
            assert(mData.mLengthMS > 0);
            assert(mData.mFrameTimeMS > 0);
        }
    }

    bool hasFinished() {
        assert(!!mData);
        return (frameTime == mData.mLengthMS);
    }

    override void draw(Canvas canvas) {
        if (!mData)
            return;
        int frame = curFrame();
        if (frame < 0)
            return;
        mData.mFrames.draw(canvas, mData.mAnimId, frame, pos);
    }

    //I wonder... should it return the current frame's bounds or what?
    Rect2i getBounds() {
        if (mData) {
            return mData.bounds();
        }
        return Rect2i.init;
    }

    AnimationData animation() {
        return mData;
    }
}

