module utils.randval;

import utils.misc;
import utils.random;
import strparser = utils.strparser;

import str = utils.string;
import std.conv;

///stores a ranged random value, i.e. "int between 0 and 10"
///a random value in the range can be sample()'d multiple times
struct RandomValue(T) {
    //separator for strings; 2nd is used if 1st not found
    private enum cRandValSeparator = ':', cRandValSeparator2 = '-';

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

    //was opAssign, caused trouble in D2
    void set(T val) {
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
        int i = str.find(s, cRandValSeparator);
        //not found -> fallback
        if (i < 0)
            i = str.find(s, cRandValSeparator2);
        T min, max;
        //we don't want to detect a '-' at the start as separator
        if (i > 0 && i < s.length) {
            min = strparser.fromStr!(T)(str.strip(s[0..i]));
            max = strparser.fromStr!(T)(str.strip(s[i+1..$]));
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
