module utils.time;

import str = std.string;

//internal type for storing a time value
private alias long TType_Int;

public struct Time {
    //represents the time value in microseconds
    private TType_Int timeVal;

    public const Time Null = {0};

    //create a new Time structure from an internal value
    //not to be called from another class
    private static Time opCall(TType_Int tVal) {
        Time ret;
        ret.timeVal = tVal;
        return ret;
    }

    ///add two Time values
    public Time opAdd(Time t2) {
        return Time(timeVal + t2.timeVal);
    }
    public void opAddAssign(Time t2) {
        timeVal += t2.timeVal;
    }

    ///get difference between Time values
    public Time opSub(Time t2) {
        return Time(timeVal - t2.timeVal);
    }
    public void opSubAssign(Time t2) {
        timeVal -= t2.timeVal;
    }

    ///divide Time value by constant (int)
    public Time opMul(int i) {
        return Time(cast(TType_Int)(timeVal * i));
    }
    public void opMulAssign(int i) {
        timeVal *= i;
    }

    ///divide Time value by constant (float)
    public Time opMul(float f) {
        return Time(cast(TType_Int)(timeVal * f));
    }

    public Time opMul(double f) {
        return Time(cast(TType_Int)(timeVal * f));
    }

    ///multiply Time value by constant (int)
    public Time opDiv(int i) {
        return Time(cast(TType_Int)(timeVal / i));
    }

    ///multiply Time value by constant (float)
    public Time opDiv(float f) {
        return Time(cast(TType_Int)(timeVal / f));
    }

    public int opEquals(Time t2) {
        return timeVal == t2.timeVal;
    }

    public int opCmp(Time t2) {
        //NOTE: "timeVal - t2.timeVal" is wrong, it wraps around too early!
        if (timeVal > t2.timeVal)
            return 1;
        else if (timeVal < t2.timeVal)
            return -1;
        else
            return 0;
    }

    ///return string representation of value
    public char[] toString() {
        //xxx add more formatting
        //xxx negative time?
        if (timeVal < 1000) {
            return str.format("%d us", timeVal);
        } else if (timeVal < 1000*1000) {
            return str.format("%.3f ms", cast(float)timeVal / 1000.0f);
        } else {
            return str.format("%.3f s", cast(float)timeVal / (1000.0f*1000.0f));
        }
    }

    ///Get: Time value as microseconds
    public long musecs() {
        return timeVal;
    }

    ///Set: Time value as microseconds
    public void musecs(long val) {
        timeVal = val;
    }

    ///Get: Time value as milliseconds
    public long msecs() {
        return timeVal / 1000;
    }

    ///Set: Time value as milliseconds
    public void msecs(long val) {
        timeVal = val * 1000;
    }

    ///Get: Time value as seconds
    public long secs() {
        return timeVal / (1000 * 1000);
    }

    public float secsf() {
        return cast(float)timeVal / (1000.0f * 1000.0f);
    }

    ///Set: Time value as seconds
    public void secs(long val) {
        timeVal = val * (1000 * 1000);
    }

    ///Get: Time value as minutes
    public long mins() {
        return timeVal / (60 * 1000 * 1000);
    }

    ///Set: Time value as minutes
    public void mins(long val) {
        timeVal = val * (60 * 1000 * 1000);
    }

    ///Get: Time value as hours
    public long hours() {
        return timeVal / (60 * 60 * 1000 * 1000);
    }

    ///Set: Time value as hours
    public void hours(long val) {
        timeVal = val * (60 * 60 * 1000 * 1000);
    }

    //return as float in seconds (should only be used for small relative times)
    public float toFloat() {
        return msecs/1000.0f;
    }
}


///new Time value from microseconds
public Time timeMusecs(int val) {
    return Time(cast(TType_Int)val);
}

public Time timeMusecs(float val) {
    return Time(cast(TType_Int)val);
}

public Time timeMusecs(long val) {
    return Time(val);
}

///new Time value from milliseconds
public Time timeMsecs(int val) {
    return timeMusecs(val*1000);
}

public Time timeMsecs(float val) {
    return timeMusecs(val*1000);
}

///new Time value from seconds
public Time timeSecs(int val) {
    return timeMsecs(val*1000);
}

public Time timeSecs(float val) {
    return timeMsecs(val*1000);
}

///new Time value from minutes
public Time timeMins(int val) {
    return timeSecs(val*60);
}

public Time timeMins(float val) {
    return timeSecs(val*60);
}

///new Time value from hours
public Time timeHours(int val) {
    return timeMins(val*60);
}

public Time timeHours(float val) {
    return timeMins(val*60);
}

///new Time value from hours+minutes+seconds
public Time timeHms(int h, int m, int s) {
    return timeHours(h) + timeMins(m) + timeSecs(s);
}

//seems to be a convenient hack, remove it if you don't like it
public Time timeNever() {
    Time r;
    r.timeVal = typeof(r.timeVal).max;
    return r;
}

public Time timeNull() {
    Time t;
    t.timeVal = 0;
    return t;
}

//use the perf counter as time source, lol
//the perf counter is fast, doesn't wrap in near time, and measures the absolute
//time (i.e. not the process time) - so why not?
//ok, might not be available under Win95
import std.perf;

private PerformanceCounter gCounter;
//not used anymore... just stores the ptr to timeCurrentTime() now
private Time delegate() timeGetCurrentTime;

import utils.misc;

static this() {
    gCounter = new PerformanceCounter();
    gCounter.start();

    timeGetCurrentTime = toDelegate(&timeCurrentTime);
}

///get current (framework) time
public Time timeCurrentTime() {
    //this relies on the inner working of std.perf:
    //  PerformanceCounter.stop() doesn't reset the start time or so, but always
    //  sets the measured time to the time between the last .start() and the
    //  current .stop() call
    gCounter.stop();
    return timeMusecs(gCounter.microseconds());
}

///returns the time delegate
///(leftover from old way of getting the time?)
public Time delegate() getCurrentTimeDelegate() {
    return timeGetCurrentTime;
}
