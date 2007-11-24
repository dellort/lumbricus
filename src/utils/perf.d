module utils.perf;

import std.perf;
import utils.time;

///wraps std.perf.PerformanceCounter
///differences: .stop doesn't reset the counter or so, and calling .start
///   while it's active doesn't mess it up
class PerfTimer {
    private {
        PerformanceCounter mCounter;
        bool mActive;
        Time mTime;
    }

    this() {
        mCounter = new PerformanceCounter();
    }

    final void start() {
        if (mActive)
            return;
        mActive = true;
        mCounter.start();
    }

    final void stop() {
        if (!mActive)
            return;
        mActive = false;
        mCounter.stop();
        mTime += timeMusecs(mCounter.microseconds());
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
