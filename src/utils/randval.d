module utils.randval;

import utils.misc;
import utils.random;
import strparser = utils.strparser;

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

    ///sample a random value in [min, max]
    T sample(Random rnd) {
        assert(!!rnd);
        if (min == max)
            return min;
        return rnd.nextRange(min, max);
    }

    bool isNull() {
        return (min == T.init) && (max == T.init);
    }

    bool isConst() {
        //(wow == doesn't always return bool?)
        return !!(min == max);
    }

    void opAssign(T val) {
        min = max = val;
    }

    string toString() {
        if (min == max)
            return to!(string)(min);
        else
            return to!(string)(min) ~ cRandValSeparator ~ to!(string)(max);
    }

    ///initialize from string like "<min><cRandValSeparator><max>"
    //may throw ConversionException
    static RandomValue fromString(string s) {
        uint i = str.locate(s, cRandValSeparator);
        //not found -> fallback
        if (i == s.length)
            i = str.locate(s, cRandValSeparator2);
        T min, max;
        //we don't want to detect a '-' at the start as separator
        if (i > 0 && i < s.length) {
            min = strparser.fromStr!(T)(str.trim(s[0..i]));
            max = strparser.fromStr!(T)(str.trim(s[i+1..$]));
        } else {
            min = max = strparser.fromStr!(T)(s);
        }
        return opCall(min,max);
    }

    string fromStringRev() {
        return toString();
    }
}

alias RandomValue!(float) RandomFloat;
alias RandomValue!(uint) RandomUint;
alias RandomValue!(int) RandomInt;
alias RandomValue!(long) RandomLong;

static this() {
    strparser.addStrParser!(RandomInt);
    strparser.addStrParser!(RandomFloat);
}
