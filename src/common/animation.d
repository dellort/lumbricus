module common.animation;

import common.common;
import common.scene;
import framework.framework;
import utils.rect2;
import utils.time;
import utils.vector2;

class AnimationData {
    private {
        Frame[] mFrameList;
        int mFrameTimeMS = 20;
        int mLengthMS;
        Rect2i mBounds;
    }

    //repeat the animation
    bool repeat = true;

    //if not repeated: keep showing last frame when animation finished
    bool keepLastFrame = false;

    struct Frame {
        Surface bitmap;
        //size of that frame (the rest is considered to eb transparent)
        Vector2i size;
        //position in bitmap
        Vector2i sourcePos;
        //position-bias on screen
        Vector2i destPos;
    }

    private void postInit() {
        mLengthMS = mFrameTimeMS * mFrameList.length;
        mBounds = Rect2i.Empty();
        foreach (inout f; mFrameList) {
            assert(!!f.bitmap);
            mBounds.extend(f.destPos);
            mBounds.extend(f.destPos+f.size);
        }
        assert(mBounds.isNormal());
    }

    /+this(ConfigFile node) {
        ....
        postInit();
    }+/

    //rather for debugging
    //assumes it's quadratic => width/height = nframes
    this(Surface anistrip, bool arepeat = true, bool akeeplast = false) {
        repeat = arepeat;
        keepLastFrame = akeeplast;

        auto w = anistrip.size.y; //quadratic
        mFrameList.length = anistrip.size.x / w;

        foreach (int index, inout frame; mFrameList) {
            frame.bitmap = anistrip;
            frame.sourcePos = Vector2i(index*w, 0);
            frame.size = Vector2i(w, anistrip.size.y);
            //position you need to add to the center of the animation to
            //position the frame right
            frame.destPos = -frame.size/2; //frame is in the center
        }

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
        return mFrameList.length;
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
                return mData.mFrameList.length-1;
            } else {
                return -1;
            }
        }
        int frame = t / mData.mFrameTimeMS;
        assert(frame >= 0 && frame < mData.mFrameList.length);
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
            assert(mData.mFrameList.length > 0);
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
        AnimationData.Frame* pFrame = &mData.mFrameList[frame];
        canvas.draw(pFrame.bitmap, pos + pFrame.destPos, pFrame.sourcePos,
            pFrame.size);
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

