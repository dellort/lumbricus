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
        mData.draw(canvas, pos, params, now() - mStarted);
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
