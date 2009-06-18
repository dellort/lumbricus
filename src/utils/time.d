module utils.time;

import str = utils.string;
import strparser = utils.strparser;
import utils.misc;
import tango.util.Convert : to;

//if true, use nanosecond resolution instead of milliseconds
const bool cNS = true;

//internal type for storing a time value
private alias long TType_Int;

public struct Time {
    //represents the time value in microseconds (or nanoseconds if cNS == true)
    private TType_Int timeVal;

    public const Time Null = {0};
    //seems to be a convenient hack, remove it if you don't like it
    //NOTE: exact value is subject to change (but is bound to be a very big)
    public const Time Never = {typeof(timeVal).max};
    //same, "Never" was a bad choice, "Always" would be another choice
    //of course, this doesn't behave like float.Infinity; if you do calculations
    //  with it, the special meaning of this value is ignored and destroyed
    public const Time Infinite = Never;

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

    //I hate D operator overloading
    Time opMul(long i) {
        return Time(cast(TType_Int)(timeVal * i));
    }

    public Time opMul(float f) {
        return *this * cast(double)f;
    }

    public Time opMul(double f) {
        return Time(cast(TType_Int)(timeVal * f));
    }

    public Time opDiv(int i) {
        return Time(cast(TType_Int)(timeVal / i));
    }

    public Time opDiv(float f) {
        return Time(cast(TType_Int)(timeVal / f));
    }

    public long opDiv(Time t) {
        return timeVal / t.timeVal;
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

    public Time opNeg() {
        return Time(-timeVal);
    }

    ///return string representation of value
    public char[] toString() {
        char[80] buffer = void;
        return toString_s(buffer).dup;
    }

    //I needed this hack I'm sorry I'm sorry I'm sorry
    public char[] toString_s(char[] buffer) {
        if (*this == Never)
            return "<unknown>";

        const char[][] cTimeName = ["ns", "us", "ms", "s", "min", "h"];
        //divisior to get from one time unit to the next
        const int[] cTimeDiv =       [1, 1000, 1000, 1000, 60,    60, 0];
        //precission which should be used to display the time
        const int[] cPrec =         [0,   1,    3,     2,   2,     2];
        long time = nsecs;
        //xxx negative time?
        for (int i = 0; ; i++) {
            if (time < cTimeDiv[i]*cTimeDiv[i+1] || i == cTimeName.length-1) {
                //auto s = myformat("%.*f {}", cPrec[i],
                //    cast(double)time / cTimeDiv[i], cTimeName[i]);
                //xxx: how to do the precission?
                auto s = myformat_s(buffer, "{} {}",
                    cast(double)time / cTimeDiv[i], cTimeName[i]);
                return s;
            }
            time = time / cTimeDiv[i];
        }
    }

    //both arrays must be kept synchronized
    //also, there's this nasty detail that for "ms" must be before "s"
    //  (ambiguous for fromString())
    //for fromStringRev, the list must be sorted by time value (ascending)
    const char[][] cTimeUnitNames = ["ns", "us", "ms", "s", "min", "h"];
    const Time[] cTimeUnits = [timeNsecs(1), timeMusecs(1), timeMsecs(1),
        timeSecs(1), timeMins(1), timeHours(1)];

    //format: comma seperated items of "<time> <unit>"
    //the string can be prepended by a "-" to indicate negative values
    //<unit> is one of "h", "min", "s", "ms", "us", "ns"
    //<time> must be an integer... oh wait, float is allowed too
    //whitespace everywhere allowed
    //special values: "never" (=> Time.Never) and "0" (=> Time.Null)
    //example: "1s,30 ms"
    //if the resolution of Time is worse than ns, some are possibly ignored
    public static Time fromString(char[] s) {
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
        char[][] stuff = str.split(s, ",");
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
            char[] unit_name = cTimeUnitNames[unit_idx];
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
    public char[] fromStringRev() {
        Time cur = *this;
        char[] res;
        bool neg = false;
        if (cur.timeVal < 0) {
            cur.timeVal = -cur.timeVal;
            res = "- ";
        }

        //dumb special case
        if (cur == Time.Never)
            return res ~ "infinite";

        int count = 0; //number of non-0 components so far
        foreach_reverse(int i, Time t; cTimeUnits) {
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
        Time p(char[] s) {
            return Time.fromString(s);
        }
        assert(p("1ns") == timeNsecs(1));
        assert(p("1ns,3ms,67h") == timeNsecs(1)+timeMsecs(3)+timeHours(67));
        assert(p("  - 1 ns,  3 ms , 67 h ") ==
            -(timeNsecs(1)+timeMsecs(3)+timeHours(67)));
        assert(p("  -  0  ") == Time.Null);
        assert(p("   never  ") == Time.Never);
        assert(p("   infinite  ") == Time.Never);
        assert(p("  -  never  ") == -Time.Never);
        assert(timeNsecs(1).fromStringRev() == "1 ns");
        assert(timeHms(55, 45, 5).fromStringRev() == "55 h, 45 min, 5 s");
        assert((-timeHms(55, 45, 5)).fromStringRev() == "- 55 h, 45 min, 5 s");
        assert(Time.Null.fromStringRev() == "0");
        assert(Time.Never.fromStringRev() == "infinite");
        //Trace.formatln("{}", (-Time.Never).fromStringRev());
        assert((-Time.Never).fromStringRev() == "- infinite");
    }

    ///Get: Time value as nanoseconds
    public long nsecs() {
        return cNS ? timeVal : timeVal*1000;
    }

    ///Set: Time value as nanoseconds
    public void nsecs(long val) {
        timeVal = cNS ? val : val/1000;
    }

    ///Get: Time value as microseconds
    public long musecs() {
        return cNS ? timeVal/1000 : timeVal;
    }

    ///Set: Time value as microseconds
    public void musecs(long val) {
        timeVal = cNS ? val*1000 : val;
    }

    ///Get: Time value as milliseconds
    public long msecs() {
        return musecs / 1000;
    }

    ///Set: Time value as milliseconds
    public void msecs(long val) {
        musecs = val * 1000;
    }

    ///Get: Time value as seconds
    public long secs() {
        return musecs / (1000 * 1000);
    }

    //return as float in seconds (should only be used for small relative times)
    public float secsf() {
        return cast(float)musecs / (1000.0f * 1000.0f);
    }

    ///Set: Time value as seconds
    public void secs(long val) {
        musecs = val * (1000 * 1000);
    }

    ///Get: Time value as minutes
    public long mins() {
        return musecs / (60 * 1000 * 1000);
    }

    ///Set: Time value as minutes
    public void mins(long val) {
        musecs = val * (60 * 1000 * 1000);
    }

    ///Get: Time value as hours
    public long hours() {
        return musecs / (60 * 60 * 1000 * 1000);
    }

    ///Set: Time value as hours
    public void hours(long val) {
        musecs = val * (60 * 60 * 1000 * 1000);
    }
}

///new Time value from nanoseconds
Time timeNsecs(long val) {
    return Time(cNS ? val : val/1000);
}

//xxx all the following functions might behave incorrectly for large values, lol

///new Time value from microseconds
Time timeMusecs(T)(T val) {
    //return Time(cast(long)(cNS ? val*1000 : val));
    return timeNsecs(cast(TType_Int)(val*1000));
}

///new Time value from milliseconds
Time timeMsecs(T)(T val) {
    return timeMusecs(cast(TType_Int)(val*1000));
}

///new Time value from seconds
Time timeSecs(T)(T val) {
    return timeMsecs(cast(TType_Int)(val*1000));
}

///new Time value from minutes
Time timeMins(T)(T val) {
    return timeSecs(cast(TType_Int)(val*60));
}

///new Time value from hours
Time timeHours(T)(T val) {
    return timeMins(cast(TType_Int)(val*60));
}

///new Time value from hours+minutes+seconds
public Time timeHms(int h, int m, int s) {
    return timeHours(h) + timeMins(m) + timeSecs(s);
}

//use the perf counter as time source, lol
//the perf counter is fast, doesn't wrap in near time, and measures the absolute
//time (i.e. not the process time) - so why not?
//ok, might not be available under Win95

import tango.time.StopWatch;
private StopWatch gTimer;

static this()  {
    gTimer.start();
}

public Time timeCurrentTime() {
    return timeMusecs(cast(long)gTimer.microsec());
}

//xxx: using toDelegate(&timeCurrentTime) multiple times produces linker
//errors with dmd+Tango, so the resulting delegate is stored here (wtf...)
Time delegate() timeCurrentTimeDg;

static this() {
    timeCurrentTimeDg = toDelegate(&timeCurrentTime);
}


//--------------- idiotic idiocy
static this() {
    strparser.addStrParser!(Time)();
}
