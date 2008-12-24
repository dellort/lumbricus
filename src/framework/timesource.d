module framework.timesource;
import utils.misc;
import utils.time;

debug import std.stdio : writefln;

//(changed in r533, I hate interfaces, but love useless microoptimizations)
class TimeSourcePublic {
    protected {
        //current time
        Time mSimTime;
    }

    //simulated time (don't forget to call update())
    final Time current() {
        return mSimTime;
    }

    abstract Time difference();

    abstract void paused(bool p);
    abstract bool paused();

    abstract void slowDown(float factor);
    abstract float slowDown();
}

final class TimeSource : TimeSourcePublic {
    private {
        //current time source (set using nextFrame())
        Time mExternalTime;

        Time mLastSimTime;

        Time mStartTime;  //absolute time of start (pretty useless)
        //not-slowed-down time, also quite useless/dangerous to use
        Time mPseudoTime;
        Time mPauseStarted; //absolute time of pause start
        Time mPausedTime; //summed amount of time paused
        bool mPauseMode;

        //last simulated time when slowdown was set...
        Time mLastTime;
        //last real time when slowdown was set; relative to mPseudoTime...
        Time mLastRealTime;
        //slowdown scale value
        //should at least internally be double to avoid precission issues
        double mSlowDown;
        int mFixedTimeStep = 0; //0 if invalid

        Time delegate() mCurTimeDg;

        //huh
        Time mLastExternalTime;
        Time mCompensate;
    }

    this(Time delegate() curTimeDg = null) {
        mCurTimeDg = curTimeDg;
        if (!mCurTimeDg) {
            mCurTimeDg = timeCurrentTimeDg;
        }
        initTime();
    }

    //initialize time to 0 (or the given time)
    void initTime(Time timeoffset = Time.Null) {
        mExternalTime = mCurTimeDg();
        mLastExternalTime = mExternalTime;
        mCompensate = timeSecs(0);

        mPauseMode = false;
        mStartTime = mExternalTime;
        mPseudoTime = timeSecs(0);
        mPausedTime = timeSecs(0);

        mLastRealTime = timeSecs(0);
        mSimTime = mLastSimTime = mLastTime = timeoffset;
        slowDown = 1;
    }

    //reset to time 0 with current external time
    void resetTime() {
        initTime();
    }

    void paused(bool p) {
        if (p == mPauseMode)
            return;

        mPauseMode = p;
        if (mPauseMode) {
            mPauseStarted = mExternalTime;
        } else {
            mPausedTime += mExternalTime - mPauseStarted;
        }
    }
    bool paused() {
        return mPauseMode;
    }

    //set the slowdown multiplier, 1 = normal, <1 = slower, >1 = faster
    void slowDown(float factor) {
        assert(factor == factor);
        assert(factor >= 0.0f);

        auto realtime = mPseudoTime;

        //make old value absolute
        mLastTime = mSimTime;
        mLastRealTime = realtime;

        mSlowDown = factor;
    }
    float slowDown() {
        return mSlowDown;
    }

    Time difference() {
        return mSimTime - mLastSimTime;
    }

    //update time!
    public void update() {
        mExternalTime = mCurTimeDg() + mCompensate;

        //happens when I suspend+resume my Linux system xD
        if (mExternalTime < mLastExternalTime) {
            Time error = mLastExternalTime - mExternalTime;
            debug writefln("WARNING: time goes backward by %s!", error);
            //compensate and do as if no time passed
            mCompensate += error;
            mExternalTime += error;
        }

        mLastExternalTime = mExternalTime;
        mLastSimTime = mSimTime;

        if (!mPauseMode) {
            mPseudoTime = mExternalTime - mStartTime - mPausedTime;

            Time diff = mPseudoTime - mLastRealTime;

            //because of floating point precission issues; I guess this would
            //solve it... or so
            if (diff > timeSecs(3)) {
                slowDown(slowDown());
                diff = timeNull();
            }

            mSimTime = mLastTime + diff * mSlowDown;

            assert(mSimTime >= mLastSimTime);
        }
    }
}
