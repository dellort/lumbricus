module utils.randval;

import str = std.string;
import utils.misc;
import utils.random;

///stores a ranged random value, i.e. "int between 0 and 10"
///on first request, a value is sampled and stored
///following requests return the stored value, until a reset() call
public struct RandomValue(T) {
    //separator for strings
    private const randValSeparator = "-";

    T min;
    T max;
    Random rnd;
    private {
        T curValue;
        bool sampled = false;
    }

    public static RandomValue opCall(T min, T max, Random rnd = null) {
        RandomValue ret;
        if (min > max)
            swap(min, max);
        ret.min = min;
        ret.max = max;
        ret.rnd = rnd;
        return ret;
    }

    public static RandomValue opCall(T value, Random rnd = null) {
        return opCall(value, value, rnd);
    }

    ///initialize from string like "<min><randValSeparator><max>"
    public static RandomValue opCall(char[] s, Random rnd = null) {
        int i = str.find(s,randValSeparator);
        T min, max;
        if (i >= 0) {
            min = cast(T)str.atof(s[0..i]);
            max = cast(T)str.atof(s[i+1..$]);
        } else {
            min = max = cast(T)str.atof(s);
        }
        return opCall(min,max,rnd);
    }

    private double rndrealClose() {
        if (rnd)
            return rnd.nextDouble();
        else
            return genrand_real1();
    }

    private double rndrealOpen() {
        if (rnd)
            return rnd.nextDouble2();
        else
            return genrand_real2();
    }

    ///sample a random value between min and max
    ///the stored value is not modified
    public T sample() {
        if (min == max)
            return min;
        //this is different for integer and floating point values
        static if (T.stringof == "float" || T.stringof == "double" || T.stringof == "real")
            return min+(max-min)*rndrealClose();
        else
            return min+cast(T)((max-min+1)*rndrealOpen());
    }

    public T value() {
        if (!sampled)
            curValue = sample();
        sampled = true;
        return curValue;
    }

    public T nextValue() {
        reset();
        return value();
    }

    public void reset() {
        sampled = false;
    }

    public bool isNull() {
        return (min == 0) && (max == 0);
    }

    public char[] toString() {
        if (min == max)
            return str.toString(min);
        else
            return str.toString(min) ~ randValSeparator ~ str.toString(max);
    }
}

alias RandomValue!(float) RandomFloat;
alias RandomValue!(uint) RandomUint;
alias RandomValue!(int) RandomInt;
alias RandomValue!(long) RandomLong;
