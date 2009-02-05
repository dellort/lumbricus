module framework.timesource;
import utils.misc;
import utils.time;
import utils.log;
import utils.reflection;

debug import tango.io.Stdout;

//(changed in r533, I hate interfaces, but love useless microoptimizations)
class TimeSourcePublic {
    protected {
        //current time
        Time mSimTime;
    }

    this() {
    }
    this(ReflectCtor c) {
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
        static LogStruct!("timesource") log;

        //current time source (set using update())
        Time mExternalTime;
        Time mFixedTime;  //absolute time of last fixpoint

        Time mLastSimTime;
        Time mLastExternalTime;
        Time mFixDelta;   //SimTime of last fixpoint

        bool mPauseMode;

        //slowdown scale value
        //should at least internally be double to avoid precission issues
        double mSlowDown = 1.0;

        //maximum time one frame can last before an error is detected
        //(i.e. longer frames do not count)
        const cMaxFrameTime = timeSecs(1);

        TimeSourcePublic mParent;
    }

    //if parent is null, timeCurrentTime() is used as source
    this(TimeSourcePublic parent = null) {
        mParent = parent;
        initTime();
    }
    this(ReflectCtor c) {
    }

    //initialize time to 0 (or the given time)
    void initTime(Time timeoffset = Time.Null) {
        mExternalTime = sampleExternal();
        mLastExternalTime = mExternalTime;

        mPauseMode = false;

        mSimTime = mLastSimTime = timeoffset;
        internalFixTime();
        slowDown = 1.0;
    }

    //reset to time 0 with current external time
    void resetTime() {
        initTime();
    }

    void paused(bool p) {
        if (p == mPauseMode)
            return;

        mPauseMode = p;
        if (!mPauseMode) {
            internalFixTime();
        }
    }
    bool paused() {
        return mPauseMode;
    }

    //set the slowdown multiplier, 1 = normal, <1 = slower, >1 = faster
    void slowDown(float factor) {
        assert(factor == factor);
        assert(factor >= 0.0f);

        //make old value absolute
        internalFixTime();

        mSlowDown = factor;
    }
    float slowDown() {
        return mSlowDown;
    }

    Time difference() {
        return mSimTime - mLastSimTime;
    }

    //update mFixedTime to current external time
    //(i.e. create a new fixpoint from which calculation starts from now)
    private void internalFixTime() {
        mFixedTime = mExternalTime;
        mFixDelta = mSimTime;
    }

    private Time sampleExternal() {
        if (mParent)
            return mParent.current();
        return timeCurrentTime();
    }

    //update time!
    public void update() {
        mExternalTime = sampleExternal();

        //happens when I suspend+resume my Linux system xD
        if (mExternalTime < mLastExternalTime) {
            Time error = mLastExternalTime - mExternalTime;
            log("WARNING: time goes backward by {}!", error);
            //compensate and do as if no time passed
            internalFixTime();
        }
        if (mExternalTime - mLastExternalTime > cMaxFrameTime) {
            Time error = mExternalTime - mLastExternalTime;
            log("Time just jumped by {}, discarding frame", error);
            //frame was too long, assume there was a hang/serialize
            //and don't count it
            internalFixTime();
        }

        mLastExternalTime = mExternalTime;
        mLastSimTime = mSimTime;

        if (!mPauseMode) {
            Time diff = mExternalTime - mFixedTime;

            //because of floating point precission issues; I guess this would
            //solve it... or so
            /*if (diff > timeSecs(3)) {
                slowDown(slowDown());
                diff = Time.Null;
            }*/

            mSimTime = mFixDelta + diff * mSlowDown;

            assert(mSimTime >= mLastSimTime);
        }
    }
}
