module framework.timesource;
import utils.misc;
import utils.time;
import utils.log;
import utils.reflection;

//(changed in r533, I hate interfaces, but love useless microoptimizations)
class TimeSourcePublic {
    protected {
        //current time
        Time mSimTime;
        Time mLastSimTime;
        char[] mName;
    }

    this(char[] a_name) {
        mName = a_name;
    }
    this(ReflectCtor c) {
    }

    //simulated time (don't forget to call update())
    final Time current() {
        return mSimTime;
    }

    //xxx: this function looks dangerous, should remove?
    final Time difference() {
        return mSimTime - mLastSimTime;
    }

    ///warning: if you have chained time sources, these values only refer to
    ///         the local settings, e.g. the time could be paused even when this
    ///         paused() property returns false
    abstract void paused(bool p);
    abstract bool paused();
    abstract void slowDown(float factor);
    abstract float slowDown();

    //?
    abstract Time lastExternalTime();
}

final class TimeSource : TimeSourcePublic {
    private {
        static LogStruct!("timesource") log;

        //current time source (set using update())
        Time mExternalTime;
        Time mFixedTime;  //absolute time of last fixpoint

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
    this(char[] a_name, TimeSourcePublic parent, Time timeoffset = Time.Null) {
        super(a_name);
        mParent = parent;
        initTime(timeoffset);
    }
    this(char[] a_name, Time timeoffset = Time.Null) {
        this(a_name, null, timeoffset);
    }
    this(ReflectCtor c) {
        super(c);
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

    //(setting paused=true doesn't call update())
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

    Time lastExternalTime() {
        return mLastExternalTime;
    }

    //update time!
    public void update() {
        mExternalTime = sampleExternal();

        //happens when I suspend+resume my Linux system xD
        if (mExternalTime < mLastExternalTime) {
            Time error = mLastExternalTime - mExternalTime;
            log("[{}] WARNING: time goes backward by {}!", mName, error);
            //compensate and do as if no time passed
            internalFixTime();
        }
        if (mExternalTime - mLastExternalTime > cMaxFrameTime) {
            Time error = mExternalTime - mLastExternalTime;
            log("[{}] Time just jumped by {}, discarding frame", mName, error);
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
            if (diff > timeSecs(3)) {
                internalFixTime();
                diff = Time.Null;
            }

            mSimTime = mFixDelta + diff * mSlowDown;

            assert(mSimTime >= mLastSimTime);
        }
    }
}

///trivial proxy object to implement fixed framerate
///(so trivial it's annoying, duh; maybe move this into TimeSource)
///the paused/slowDown states even work correctly if modified during the frame
///code (that is, while is_update() is called by update())
class TimeSourceFixFramerate : TimeSourcePublic {
    private {
        TimeSourcePublic mParent;
        TimeSource mChain;
        //to correctly manage paused()/slowDown()
        //deriving TimeSourceFixFramerate from TimeSource was not an option
        Time mFrameLength;
    }

    /// parent = anything
    /// frameLength = fixed length of each frame, see update()
    this(char[] a_name, TimeSourcePublic parent, Time frameLength) {
        super(a_name);
        assert (!!parent);
        mParent = parent;
        mFrameLength = frameLength;
        mChain = new TimeSource("chain-" ~ mName, mParent);
        resetTime();
    }
    this(ReflectCtor c) {
        super(c);
    }

    ///reset the time to the caller's
    ///(after this call, this.current should return parent.current)
    void resetTime() {
        mChain.initTime(mParent.current);
        mSimTime = mLastSimTime = mChain.current;
        assert(this.current == mParent.current);
    }

    override void paused(bool p) {
        mChain.paused = p;
    }
    override bool paused() {
        return mChain.paused;
    }
    override void slowDown(float factor) {
        mChain.slowDown = factor;
    }
    override float slowDown() {
        return mChain.slowDown;
    }

    override Time lastExternalTime() {
        return mChain.lastExternalTime;
    }

    ///runs n frames in increments of the fixed frame length, and calls
    ///do_update() for each frame; the time is stepped before each do_update()
    void update(void delegate() do_update) {
        mChain.update();
        //xxx: is it ok that mSimTime still can be < mParent.current after this?
        while (mSimTime + mFrameLength <= mChain.current) {
            mLastSimTime = mSimTime;
            mSimTime += mFrameLength;
            do_update();
            mChain.update(); //?
        }
    }
}
