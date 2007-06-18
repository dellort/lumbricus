module framework.timesource;
import utils.time;

final class TimeSource {
    private {
        //current time source (set using nextFrame())
        Time mExternalTime;

        //current time
        Time mSimTime, mLastSimTime;

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
    }

    this(Time aCurrentTime) {
        initTime(aCurrentTime);
    }

    //initialize time to 0
    //aCurrentTime = the external time (same time as for update())
    void initTime(Time aCurrentTime) {
        mExternalTime = aCurrentTime;

        mPauseMode = false;
        mStartTime = mExternalTime;
        mPseudoTime = timeSecs(0);
        mPausedTime = timeSecs(0);

        mLastRealTime = timeSecs(0);
        mSimTime = timeSecs(0);
        mSimTime = timeSecs(0);
        mLastSimTime = timeSecs(0);
        mLastTime = timeSecs(0);
        slowDown = 1;
    }

    //reset to time 0 with current external time
    void resetTime() {
        initTime(mExternalTime);
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

        auto realtime = mPseudoTime;

        //make old value absolute
        mLastTime = mSimTime;
        mLastRealTime = realtime;

        mSlowDown = factor;
    }
    float slowDown() {
        return mSlowDown;
    }

    //simulated time (don't forget to call update())
    Time current() {
        return mSimTime;
    }

    Time difference() {
        return mLastSimTime - mSimTime;
    }

    //update time!
    //after this, a new deltaT and/or frameCount
    public void update(Time currentTime) {
        mExternalTime = currentTime;

        mLastSimTime = mSimTime;

        if (!mPauseMode) {
            mPseudoTime = mExternalTime - mStartTime - mPausedTime;

            auto realtime = mPseudoTime;

            mSimTime = mLastTime + (realtime - mLastRealTime) * mSlowDown;
        }
    }
}
