//hooks to create various statistics, which then are displayed in debugstuff.d
//this qualifies mostly as debugging crap
//maybe should be disabled in debug mode (all methods turns into NOP)
module common.stats;

import utils.time;
import utils.misc;
import utils.perf;

//high resolution timers which are updated each frame, or so
//debugstuff.d will reset them all!
PerfTimer[string] gTimers;
long[string] gCounters;
size_t[string] gSizeStats;

PerfTimer newTimer(string name) {
    auto pold = name in gTimers;
    if (pold)
        return *pold;
    auto t = new PerfTimer(true);
    gTimers[name] = t;
    return t;
}

//consider using newTimer() instead to get a PerfTimer and work on that directly
//  if you want to do this in performance-sensitive code
PerfTimer startTimer(string name) {
    auto t = newTimer(name);
    t.start();
    return t;
}

PerfTimer stopTimer(string name) {
    auto t = newTimer(name);
    t.stop();
    return t;
}

void incCounter(string name, long amount = 1) {
    long* pold = name in gCounters;
    if (!pold) {
        gCounters[name] = 0;
        pold = name in gCounters;
    }
    (*pold) += amount;
}
void setCounter(string name, long cnt) {
    gCounters[name] = cnt;
}

void setByteSizeStat(string name, size_t size) {
    gSizeStats[name] = size;
}
