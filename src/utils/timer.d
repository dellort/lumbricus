module utils.timer;

import utils.misc;
import utils.time;

alias void delegate(Timer sender) TimerEvent;

///Timer operation modes
enum TimerMode {
    ///[default] guarantee an average delay of set interval between events
    ///one call to update() may fire multiple events
    accurate,
    ///waits at least one interval after an event until the next one fires
    ///no compensation for over-wait, one update() throws exaclty one event
    fixedDelay,
}

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
        //lazy or accurate mode (see TimerMode comment)
        TimerMode mMode = TimerMode.accurate;
    }

    ///event that is called every interval
    TimerEvent onTimer;

    this(Time interval, TimerEvent ev, Time delegate() curTimeDg = null) {
        mInterval = interval;
        mCurTimeDg = curTimeDg;
        if (!mCurTimeDg) {
            mCurTimeDg = timeCurrentTimeDg;
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

    ///Timer mode, see TimerMode comments
    public TimerMode mode() {
        return mMode;
    }
    public void mode(TimerMode m) {
        mMode = m;
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
        while (tcur - mTimeLast >= mInterval) {
            //mInterval may change in event procedure, so evaluate before
            if (mMode == TimerMode.accurate)
                mTimeLast += mInterval;
            else
                mTimeLast = tcur;
            doOnTimer();
            if (!mEnabled)
                return;   //timer got disabled in event call
        }
    }
}
