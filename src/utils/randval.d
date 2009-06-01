module utils.randval;

import utils.misc;
import utils.random;

import str = tango.text.Util;
import tango.util.Convert : to;

///stores a ranged random value, i.e. "int between 0 and 10"
///a random value in the range can be sample()'d multiple times
struct RandomValue(T) {
    //separator for strings; 2nd is used if 1st not found
    private const cRandValSeparator = ':', cRandValSeparator2 = '-';

    T min;
    T max;

    static RandomValue opCall(T min, T max) {
        RandomValue ret;
        if (min > max)
            swap(min, max);
        ret.min = min;
        ret.max = max;
        return ret;
    }

    static RandomValue opCall(T value) {
        return opCall(value, value);
    }

    ///initialize from string like "<min><cRandValSeparator><max>"
    static RandomValue opCall(char[] s) {
        uint i = str.locate(s, cRandValSeparator);
        //not found -> fallback
        if (i == s.length)
            i = str.locate(s, cRandValSeparator2);
        T min, max;
        //we don't want to detect a '-' at the start as separator
        if (i > 0 && i < s.length) {
            min = to!(T)(str.trim(s[0..i]));
            max = to!(T)(str.trim(s[i+1..$]));
        } else {
            min = max = to!(T)(s);
        }
        return opCall(min,max);
    }

    ///sample a random value in [min, max]
    T sample(Random rnd) {
        assert(!!rnd);
        if (min == max)
            return min;
        return rnd.nextRange(min, max);
    }

    bool isNull() {
        return (min == 0) && (max == 0);
    }

    bool isConst() {
        return min == max;
    }

    char[] toString() {
        if (min == max)
            return to!(char[])(min);
        else
            return to!(char[])(min) ~ cRandValSeparator ~ to!(char[])(max);
    }
}

alias RandomValue!(float) RandomFloat;
alias RandomValue!(uint) RandomUint;
alias RandomValue!(int) RandomInt;
alias RandomValue!(long) RandomLong;
