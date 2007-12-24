module common.animation;

import common.common;
import common.scene;
import framework.framework;
public import framework.restypes.frames;
import utils.rect2;
import utils.time;
import utils.vector2;

class Animator : SceneObjectCentered {
    private {
        Animation mData;
        AnimationParams mParams;
        Time mStarted;
        debug Time mLastNow;

        Time now() {
            auto n = globals.gameTimeAnimations.current;
            debug {
                assert(n >= mLastNow, "time running backwards lol");
                mLastNow = n;
            }
            return n;
        }
    }

    void setParams(AnimationParams p) {
        mParams = p;
    }

    private int frameTime() {
        assert(mData && mData.mLengthMS != 0);
        int t = (now() - mStarted).msecs;
        if (t >= mData.mLengthMS) {
            //if this has happened, we either need to show a new frame,
            //disappear or just stop it
            //xxx
            if (false && !mData.repeat) {
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
    void setAnimation(Animation d, Time startAt = Time.Null) {
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
        mData.drawFrame(canvas, pos, mParams, frame);
    }

    //shall return the smallest bounding box for all frame, centered around 0/0
    Rect2i bounds() {
        if (mData) {
            return mData.bounds();
        }
        return Rect2i.init;
    }

    Animation animation() {
        return mData;
    }
}

