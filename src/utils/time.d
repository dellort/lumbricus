module utils.time;

import str = utils.string;
import strparser = utils.strparser;
import utils.misc;
import std.traits;

//if true, use nanosecond resolution instead of milliseconds
enum bool cNS = true;

//internal type for storing a time value
private alias long TType_Int;

public struct Time {
    //represents the time value in microseconds (or nanoseconds if cNS == true)
    private TType_Int timeVal;

    enum Time Null = {0};
    //seems to be a convenient hack, remove it if you don't like it
    //NOTE: exact value is subject to change (but is bound to be a very big)
    enum Time Never = {typeof(timeVal).max};
    //same, "Never" was a bad choice, "Always" would be another choice
    //of course, this doesn't behave like float.Infinity; if you do calculations
    //  with it, the special meaning of this value is ignored and destroyed
    enum Time Infinite = Never;

    //create a new Time structure from an internal value
    //not to be called from another class
    private static Time opCall(TType_Int tVal) {
        Time ret;
        ret.timeVal = tVal;
        return ret;
    }

    ///add two Time values
    public Time opAdd(Time t2) const {
        return Time(timeVal + t2.timeVal);
    }
    public void opAddAssign(Time t2) {
        timeVal += t2.timeVal;
    }

    ///get difference between Time values
    public Time opSub(Time t2) const {
        return Time(timeVal - t2.timeVal);
    }
    public void opSubAssign(Time t2) {
        timeVal -= t2.timeVal;
    }

    ///divide Time value by constant (int)
    public Time opMul(int i) const {
        return Time(cast(TType_Int)(timeVal * i));
    }
    public void opMulAssign(int i) {
        timeVal *= i;
    }

    //I hate D operator overloading
    Time opMul(long i) const {
        return Time(cast(TType_Int)(timeVal * i));
    }

    public Time opMul(float f) const {
        return this * cast(double)f;
    }

    public Time opMul(double f) const {
        return Time(cast(TType_Int)(timeVal * f));
    }

    public Time opDiv(int i) const {
        return Time(cast(TType_Int)(timeVal / i));
    }

    public Time opDiv(float f) const {
        return Time(cast(TType_Int)(timeVal / f));
    }

    public long opDiv(Time t) const {
        return timeVal / t.timeVal;
    }

    public bool opEquals(ref const(Time) t2) const {
        return timeVal == t2.timeVal;
    }

    public int opCmp(Time t2) const {
        //NOTE: "timeVal - t2.timeVal" is wrong, it wraps around too early!
        if (timeVal > t2.timeVal)
            return 1;
        else if (timeVal < t2.timeVal)
            return -1;
        else
            return 0;
    }

    public Time opNeg() const {
        return Time(-timeVal);
    }

    ///return string representation of value
    public string toString() {
        char[80] buffer = void;
        return toString_s(buffer).idup;
    }

    //I needed this hack I'm sorry I'm sorry I'm sorry
    public cstring toString_s(char[] buffer) const {
        if (this == Never)
            return "<unknown>";

        enum string[] cTimeName = ["ns", "us", "ms", "s",  "min", "h"];
        //divisior to get from one time unit to the next
        enum int[] cTimeDiv =     [1,    1000, 1000, 1000, 60,     60, 0];
        //precission which should be used to display the time
        enum int[] cPrec =        [0,    1,    3,    2,    2,      2];
        string sign;
        long time = nsecs;
        long timeDiv = 1;
        if (time < 0) {
            time = -time;
            sign = "-";
        }
        for (int i = 0; ; i++) {
            timeDiv *= cTimeDiv[i];
            if (time < timeDiv*cTimeDiv[i+1] || i == cTimeName.length-1) {
                return myformat_s(buffer, "%s%.*f %s", sign, cPrec[i],
                    cast(double)time / timeDiv, cTimeName[i]);
            }
        }
    }

    //both arrays must be kept synchronized
    //also, there's this nasty detail that for "ms" must be before "s"
    //  (ambiguous for fromString())
    //for fromStringRev, the list must be sorted by time value (ascending)
    enum string[] cTimeUnitNames = ["ns", "us", "ms", "s", "min", "h"];
    enum Time[] cTimeUnits = [timeNsecs(1), timeMusecs(1), timeMsecs(1),
        timeSecs(1), timeMins(1), timeHours(1)];

    //format: comma seperated items of "<time> <unit>"
    //the string can be prepended by a "-" to indicate negative values
    //<unit> is one of "h", "min", "s", "ms", "us", "ns"
    //<time> must be an integer... oh wait, float is allowed too
    //whitespace everywhere allowed
    //special values: "never" (=> Time.Never) and "0" (=> Time.Null)
    //example: "1s,30 ms"
    //if the resolution of Time is worse than ns, some are possibly ignored
    public static Time fromString(const(char)[] s) {
        s = str.strip(s);
        bool neg = false;
        if (str.startsWith(s, "-")) {
            neg = true;
            s = str.strip(s[1..$]);
        }

        //special strings
        if (s == "infinite" || s == "never")
            return neg ? -Time.Never : Time.Never;
        if (s == "0")
            return Time.Null;

        //normal parsing
        auto stuff = str.split(s, ",");
        if (stuff.length == 0)
            throw strparser.newConversionException!(Time)(s, "empty string");
        Time value;
        foreach (sub; stuff) {
            sub = str.strip(sub);
            int unit_idx = -1;
            foreach (int i, name; cTimeUnitNames) {
                if (str.endsWith(sub, name)) {
                    unit_idx = i;
                    break;
                }
            }
            if (unit_idx < 0)
                throw strparser.newConversionException!(Time)(s,
                    "unknown time unit");
            Time unit = cTimeUnits[unit_idx];
            string unit_name = cTimeUnitNames[unit_idx];
            sub = str.strip(sub[0..$-unit_name.length]);
            Time cur;
            //try int first, for unrounded results
            try {
                cur = unit*strparser.fromStr!(int)(sub);
            } catch (strparser.ConversionException e1) {
                try {
                    cur = unit*strparser.fromStr!(float)(sub);
                } catch (strparser.ConversionException e2) {
                    throw strparser.newConversionException!(Time)(s,
                        "parsing number");
                }
            }
            value += cur;
        }
        if (neg)
            value = -value;
        return value;
    }

    //NOTE: unlike toString(), the result of this function
    //  1. is an unrounded, exact representation of the time ("lossless")
    //  2. is actually parseable by fromString()
    public string fromStringRev() const {
        Time cur = this;
        string res;
        bool neg = false;
        if (cur.timeVal < 0) {
            cur.timeVal = -cur.timeVal;
            res = "- ";
        }

        //dumb special case
        if (cur == Time.Never)
            return res ~ "infinite";

        int count = 0; //number of non-0 components so far
        foreach_reverse(size_t i, Time t; cTimeUnits) {
            long c = cur / t;
            Time rest = cur - c*t;
            assert(rest.timeVal >= 0);
            cur = rest;
            if (c != 0) {
                if (count)
                    res ~= ", ";
                res ~= strparser.toStr(c);
                res ~= " ";
                res ~= cTimeUnitNames[i];
                count++;
            }
        }

        if (count == 0)
            res ~= "0";

        //if there's something left, the lowest time resolution wasn't included
        //in the cTimeUnits array
        assert(cur.timeVal == 0);
        return res;
    }

    unittest {
        Time p(string s) {
            return Time.fromString(s);
        }
        //yes dmd 2.054 was too retarded to grok this...
        bool cmp(Time a, Time b) { return a == b; }
        assert(cmp(p("1ns"), timeNsecs(1)));
        assert(cmp(p("1ns,3ms,67h"), timeNsecs(1)+timeMsecs(3)+timeHours(67)));
        assert(cmp(p("  - 1 ns,  3 ms , 67 h "),
            -(timeNsecs(1)+timeMsecs(3)+timeHours(67))));
        assert(cmp(p("  -  0  "), Time.Null));
        assert(cmp(p("   never  "), Time.Never));
        assert(cmp(p("   infinite  "), Time.Never));
        assert(cmp(p("  -  never  "), -Time.Never));
        assert(timeNsecs(1).fromStringRev() == "1 ns");
        assert(timeHms(55, 45, 5).fromStringRev() == "55 h, 45 min, 5 s");
        assert((-timeHms(55, 45, 5)).fromStringRev() == "- 55 h, 45 min, 5 s");
        assert(Time.Null.fromStringRev() == "0");
        assert(Time.Never.fromStringRev() == "infinite");
        //Trace.formatln("%s", (-Time.Never).fromStringRev());
        assert((-Time.Never).fromStringRev() == "- infinite");
    }

    ///Get: Time value as nanoseconds
    public long nsecs() const {
        return cNS ? timeVal : timeVal*1000;
    }

    ///Set: Time value as nanoseconds
    public void nsecs(long val) {
        timeVal = cNS ? val : val/1000;
    }

    ///Get: Time value as microseconds
    public long musecs() const {
        return cNS ? timeVal/1000 : timeVal;
    }

    ///Set: Time value as microseconds
    public void musecs(long val) {
        timeVal = cNS ? val*1000 : val;
    }

    ///Get: Time value as milliseconds
    public long msecs() const {
        return musecs / 1000;
    }

    ///Set: Time value as milliseconds
    public void msecs(long val) {
        musecs = val * 1000;
    }

    ///Get: Time value as seconds
    public long secs() const {
        return musecs / (1000 * 1000);
    }

    //return as float in seconds (should only be used for small relative times)
    public float secsf() const {
        return secsd();
    }

    //seconds in double
    double secsd() const {
        return cast(double)musecs / (1000.0 * 1000.0);
    }

    ///Set: Time value as seconds
    public void secs(long val) {
        musecs = val * (1000 * 1000);
    }

    ///Get: Time value as minutes
    public long mins() const {
        return musecs / (60 * 1000 * 1000);
    }

    ///Set: Time value as minutes
    public void mins(long val) {
        musecs = val * (60 * 1000 * 1000);
    }

    ///Get: Time value as hours
    public long hours() const {
        return musecs / (60 * 60 * 1000 * 1000);
    }

    ///Set: Time value as hours
    public void hours(long val) {
        musecs = val * (60 * 60 * 1000 * 1000);
    }
}

//give the same kind of numeric type as T, but with maximal value range
private template maxttype(T) {
    static if (isIntegral!(T)) {
        alias long maxttype;
    } else static if (isFloatingPoint!(T)) {
        alias real maxttype;
    } else {
        static assert(false);
    }
}
//implicit conversion to maxttype!(T)
private maxttype!(T) maxconv(T)(T x) {
    return x;
}

///new Time value from nanoseconds
Time timeNsecs(T)(T val) {
    static if (!cNS) {
        val = val/1000;
    }
    //the maxconv is to ensure that val is a number (=> safer)
    return Time(cast(long)(maxconv(val)));
}

//xxx all the following functions might behave incorrectly for large values, lol

///new Time value from microseconds
Time timeMusecs(T)(T val) {
    //return Time(cast(long)(cNS ? val*1000 : val));
    return timeNsecs(maxconv(val*1000));
}

///new Time value from milliseconds
Time timeMsecs(T)(T val) {
    return timeMusecs(maxconv(val*1000));
}

///new Time value from seconds
Time timeSecs(T)(T val) {
    return timeMsecs(maxconv(val*1000));
}

///new Time value from minutes
Time timeMins(T)(T val) {
    return timeSecs(maxconv(val*60));
}

///new Time value from hours
Time timeHours(T)(T val) {
    return timeMins(maxconv(val*60));
}

///new Time value from hours+minutes+seconds
public Time timeHms(int h, int m, int s) {
    return timeHours(h) + timeMins(m) + timeSecs(s);
}

//use the perf counter as time source, lol
//the perf counter is fast, doesn't wrap in near time, and measures the absolute
//time (i.e. not the process time) - so why not?
//ok, might not be available under Win95

//import tango.time.StopWatch;
import core.time;

private ulong gBaseTime;

private ulong rawtime() {
    return TickDuration.currSystemTick.usecs;
}

public Time timeCurrentTime() {
    return timeMusecs(rawtime() - gBaseTime);
}

//xxx: using toDelegate(&timeCurrentTime) multiple times produces linker
//errors with dmd+Tango, so the resulting delegate is stored here (wtf...)
Time delegate() timeCurrentTimeDg;

static this() {
    gBaseTime = rawtime();
    timeCurrentTimeDg = toDelegate(&timeCurrentTime);
}


//--------------- idiotic idiocy
static this() {
    strparser.addStrParser!(Time)();
}
