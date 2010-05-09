module utils.perf;

import utils.time;

//to enable a per-thread CPU time counter, which does silly and hacky stuff
//it's only useful for debugging, because I don't know how to use a profiler
//version = UseFishyStuff;

class TimerImpl {
    ///timer runs continuously; use time to query the current one
    ///the start value is undefined and arbitrary
    abstract Time time();
}

class PerfTimerImpl : TimerImpl {
    Time time() {
        return timeCurrentTime();
    }
}

//per-thread counters; would require extra code for windows
version (linux) {
    version = UseFishyStuff;
}

version (UseFishyStuff) {
    //requires linking to -lrt
    //this uses the POSIX.1-2001 API, which might not be available on all
    //systems; it has undefined effects there...
    import tango.stdc.posix.pthread;

    //Tango has this commented, sigh
    extern(C) int clock_gettime(clockid_t clk_id, timespec* tp);

    class ThreadTimerImpl : TimerImpl {
        this() {
        }
        Time time() {
            timespec tp;
            auto res = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &tp);
            if (res != 0) {
                assert(false); //should never happen if getcpuclockid was ok?
            }
            long nsecs = tp.tv_nsec;
            const ulong cSecInNs = 1000UL*1000*1000;
            nsecs = nsecs + tp.tv_sec*cSecInNs;
            return timeNsecs(nsecs);
        }
    }

} else { //version (UseFishyStuff)

//the problemless "solution" which should work for everyone
alias PerfTimerImpl ThreadTimerImpl;

} //not version (UseFishyStuff)

///wraps std.perf.PerformanceCounter
///differences: .stop doesn't reset the counter or so, and calling .start
///   while it's active doesn't mess it up
class PerfTimer {
    private {
        TimerImpl mCounter;
        bool mActive;
        Time mLastStart;
        Time mTime;
    }

    this(bool thread_timer = false) {
        if (thread_timer) {
            mCounter = new ThreadTimerImpl();
        } else {
            mCounter = new PerfTimerImpl();
        }
    }

    final void start() {
        if (mActive)
            return;
        mActive = true;
        mLastStart = mCounter.time();
    }

    final void stop() {
        if (!mActive)
            return;
        mActive = false;
        auto cur = mCounter.time();
        mTime += (cur - mLastStart);
    }

    void reset() {
        stop();
        mTime = mTime.init;
    }

    bool active() {
        return mActive;
    }

    Time time() {
        //if active, stop to get the newest time
        if (mActive) {
            stop(); start();
        }
        return mTime;
    }
}
