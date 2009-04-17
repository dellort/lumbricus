module common.animation;

import common.common;
import common.scene;
import framework.framework;
import framework.timesource;
public import common.restypes.animation;
import utils.rect2;
import utils.time;
import utils.vector2;

class Animator : SceneObjectCentered {
    private {
        Animation mData;
        Time mStarted;
        debug Time mLastNow;
        TimeSourcePublic mTimeSource;

        Time now() {
            auto n = mTimeSource.current;
            debug {
                assert(n >= mLastNow, "time running backwards lol");
                mLastNow = n;
            }
            return n;
        }
    }

    AnimationParams params;

    final TimeSourcePublic timeSource() {
        return mTimeSource;
    }

    this(TimeSourcePublic ts) {
        assert(!!ts); //for now, be nazi about it
        mTimeSource = ts;
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
        if (mData) {
            //can't handle these cases
            assert(mData.frameCount > 0);
            assert(mData.mLengthMS > 0);
            assert(mData.mFrameTimeMS > 0);
        }
    }

    bool hasFinished() {
        if (!mData)
            return true;
        return (frameTime == mData.mLengthMS);
    }

    override void draw(Canvas canvas) {
        if (!mData)
            return;
        int frame = curFrame();
        if (frame < 0)
            return;
        mData.drawFrame(canvas, pos, params, frame);
    }

    //shall return the smallest bounding box for all frame, centered around pos.
    Rect2i bounds() {
        if (mData) {
            return mData.bounds() + pos;
        }
        return Rect2i.Empty;
    }

    Animation animation() {
        return mData;
    }
}
