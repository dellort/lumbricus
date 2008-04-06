module utils.perf;

import std.perf;
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
    PerformanceCounter counter;
    this() {
        counter = new PerformanceCounter();
        counter.start();
    }
    Time time() {
        //abuse the fact how PerformanceCounter works internally
        //(.stop() doesn't change any state; only updates the current duration)
        counter.stop();
        return timeMusecs(counter.microseconds());
    }
}

version (UseFishyStuff) {

version (Windows) {
    //actually almost exactly the same as PerfTimerImpl
    //also, std.perf seems to implement this for Windows only
    class ThreadTimerImpl : TimerImpl {
        ThreadTimesCounter counter;
        this() {
            counter = new ThreadTimesCounter();
            counter.start();
        }
        Time time() {
            counter.stop();
            return timeMusecs(counter.microseconds());
        }
    }
} else {
    //this uses the POSIX.1-2001 API, which might not be available on all
    //systems; it has undefined effects there...
    //also, Phobos doesn't provide all the necessary declarations
    //NOTE: instead of using getcpuclockid, one could also use
    //  clock_gettime(CLOCK_THREAD_CPUTIME_ID, ...), I guess
    version (GNU) {
        import std.c.unix.unix;
    } else {
        import std.c.linux.pthread;
    }

    extern(C) {
        int clock_gettime(clockid_t clk_id, timespec *tp);
    }

    class ThreadTimerImpl : TimerImpl {
        clockid_t timerid;
        debug pthread_t thread;
        this() {
            pthread_t me = pthread_self();
            auto res = pthread_getcpuclockid(me, &timerid);
            if (res != 0) {
                assert(false, "not supported on your system?");
            }
            debug thread = me;
        }
        Time time() {
            debug assert(thread == pthread_self(), "must be called on the same"
                " thread");
            timespec tp;
            auto res = clock_gettime(timerid, &tp);
            if (res != 0) {
                assert(false); //should never happen if getcpuclockid was ok?
            }
            long nsecs = tp.tv_nsec;
            const ulong cSecInNs = 1000UL*1000*1000;
            nsecs = nsecs + tp.tv_sec*cSecInNs;
            return timeNsecs(nsecs);
        }
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
