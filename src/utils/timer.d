module utils.timer;

import utils.time;

alias void delegate(Timer sender) TimerEvent;

///simple timer that fires an event regularly
///can be linked to a TimeSource's current() method
class Timer {
    private {
        Time delegate() mCurTimeDg;
        //timer interval
        Time mInterval;
        //is the timer active (i.e. firing events)
        bool mEnabled;
        //should the event only be called once
        bool mOneTime;

        Time mTimeLast;
        //event has been fired (if mOneTime == true)
        bool mOneTimeDone;
    }

    ///event that is called every interval
    TimerEvent onTimer;

    this(Time interval, TimerEvent ev, Time delegate() curTimeDg = null) {
        mInterval = interval;
        mCurTimeDg = curTimeDg;
        if (!mCurTimeDg) {
            mCurTimeDg = getCurrentTimeDelegate;
        }
        onTimer = ev;
        reset();
    }

    ///get/set if timer is active (i.e. firing events)
    public void enabled(bool en) {
        if (!mEnabled && en)
            reset();
        mEnabled = en;
    }
    public bool enabled() {
        return mEnabled;
    }

    ///set if the timer event should only be called once
    public void oneTime(bool ot) {
        mOneTime = ot;
    }
    public bool oneTime() {
        return mOneTime;
    }

    ///get/set timer interval
    public Time interval() {
        return mInterval;
    }
    public void interval(Time intv) {
        mInterval = intv;
    }

    ///reset progress of current interval and event status (for oneTime)
    public void reset() {
        mTimeLast = mCurTimeDg();
        mOneTimeDone = false;
    }

    private void doOnTimer() {
        if (mOneTimeDone)
            return;
        if (onTimer)
            onTimer(this);
        if (mOneTime)
            mOneTimeDone = true;
    }

    ///update timer with current time values and call event if time expired
    public void update() {
        if (!mEnabled)
            return;

        Time tcur = mCurTimeDg();
        if (tcur - mTimeLast >= mInterval) {
            doOnTimer();
            mTimeLast += mInterval;
        }
    }
}
