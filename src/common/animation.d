module common.animation;

import common.common;
import common.scene;
import framework.framework;
import utils.timesource;
public import common.restypes.animation;
import utils.rect2;
import utils.time;
import utils.vector2;

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
