module utils.misc;

import str = stdx.string;
import utf = stdx.utf;
import fmt = stdx.format; //wtf, can cause conflicts in other modules
import layout = tango.text.convert.Layout;

//if you're trying to compile this under Linux with Tango, Tangobos and dmd,
//then delete tango/import/std/stdarg.di; this file seems to be completely
//bogus (but they say gdc needs it); at least it doesn't always define va_list
//deleting that file will make dsss/rebuild/dmd to use
//tango/import/tangobos/std/stdarg.d
//import std.stdarg : va_list;
import stdx.base : va_list;

version (Tango) {
    //these functions are different from below, but do the same
    //needed because out fucntions conflict, if tango.math is implemented
    //Tango team = stupid
    public import tango.math.Math : min, max;

} else {

//min/max from tango - code is copyrighted, not sure if it can be here
//tango start ------------------------>

private {
    // Return the type which would be returned by a max or min operation
template minmaxtype(T...){
    static if(T.length == 1) alias typeof(T[0]) minmaxtype;
    else static if(T.length > 2)
        alias minmaxtype!(minmaxtype!(T[0..2]), T[2..$]) minmaxtype;
    else alias typeof (T[1] > T[0] ? T[1] : T[0]) minmaxtype;
}
}

/** Return the minimum of the supplied arguments.
 *
 * Note: If the arguments are floating-point numbers, and at least one is a NaN,
 * the result is undefined.
 */
minmaxtype!(T) min(T...)(T arg){
    static if(arg.length == 1) return arg[0];
    else static if(arg.length == 2) return arg[1] < arg[0] ? arg[1] : arg[0];
    static if(arg.length > 2) return min(arg[1] < arg[0] ? arg[1] : arg[0], arg[2..$]);
}

/** Return the maximum of the supplied arguments.
 *
 * Note: If the arguments are floating-point numbers, and at least one is a NaN,
 * the result is undefined.
 */
minmaxtype!(T) max(T...)(T arg){
    static if(arg.length == 1) return arg[0];
    else static if(arg.length == 2) return arg[1] > arg[0] ? arg[1] : arg[0];
    static if(arg.length > 2) return max(arg[1] > arg[0] ? arg[1] : arg[0], arg[2..$]);
}

//<------------------- tango end

}

void swap(T)(inout T a, inout T b) {
    T t = a;
    a = b;
    b = t;
}

bool startsWith(char[] str, char[] prefix) {
    if (str.length < prefix.length)
        return false;
    return str[0..prefix.length] == prefix;
}

bool endsWith(char[] str, char[] suffix) {
    if (str.length < suffix.length)
        return false;
    return str[$-suffix.length..$] == suffix;
}

//execute code count-times
void times(int count, void delegate() code) {
    while (count--)
        code();
}

//clamp to closed range, i.e. val is adjusted so that it fits into [low, high]
T clampRangeC(T)(T val, T low, T high) {
    if (val > high)
        val = high;
    return (val < low) ? low : val;
}

//clamp to open range, [low, high), makes sense for integers only
T clampRangeO(T)(T val, T low, T high) {
    if (val >= high)
        val = high - 1;
    return (val < low) ? low : val;
}

/* Quick utility function for texture creation */
int powerOfTwo(int input) {
    int value = 1;

    while ( value < input ) {
        value <<= 1;
    }
    return value;
}

/// Cast object in t to type T, and throw exception if not possible.
/// Only return null if t was already null.
T castStrict(T)(Object t) {
    //static assert (is(T == class) || is(T == interface));
    T res = cast(T)t;
    if (t && !res) {
        static if (is(T == class)) {
            throw new Exception("could not cast "~t.classinfo.name~" to "
                ~T.classinfo.name);
        } else {
            throw new Exception("figure it out yourself");
        }
    }
    return res;
}

/// convert a function-ptr to a delegate (thanks to downs, it's his code)
R delegate(T) toDelegate(R, T...)(R function(T) fn) {
    struct holder {
        typeof(fn) _fn;
        R call(T t) {
            static if (is(R==void))
                _fn(t);
            else
                return _fn(t);
        }
    }
    auto res = new holder;
    res._fn = fn;
    return &res.call;
}

char[] formatfx(char[] a_fmt, TypeInfo[] arguments, va_list argptr) {
    //(yeah, very funny names, Tango guys!)
    //return layout.Layout!(char).instance().vprint("", fmt, arguments, argptr);
    //Phobos for now
    char[] res;
    fmt.doFormat((dchar c) { utf.encode(res, c); }, a_fmt, arguments, argptr);
    return res;
}

//replacement for stdx.string.format()
//trivial, but Tango really is annoyingly noisy
char[] myformat(char[] fmt, ...) {
    return formatfx(fmt, _arguments, _argptr);
}

/// number of bytes to a string like "number XX", where XX is "B", "KB" etc.
char[] sizeToHuman(long bytes) {
    const char[][] cSizes = ["B", "KB", "MB", "GB"];
    int n;
    long x;
    x = 1;
    while (bytes >= x*1024 && n < cSizes.length-1) {
        x = x*1024;
        n++;
    }
    //xxx: ugly trailing zeros
    return str.format("%.3f %s", 1.0*bytes/x, cSizes[n]);
}

unittest {
    /+assert(sizeToHuman(0) == "0 B");
    assert(sizeToHuman(1023) == "1023 B");
    assert(sizeToHuman(1024) == "1 KB");+/
}

//some metaprogramming stuff

///unsigned!(T): return the unsigned type of a signed one
///invalid for non-integers (including char)
template unsigned(T : long) {
    alias ulong unsigned;
}
template unsigned(T : int) {
    alias uint unsigned;
}
template unsigned(T : short) {
    alias ushort unsigned;
}
template unsigned(T : byte) {
    alias ubyte unsigned;
}

///signed!(T): return the signed type of an unsigned one
///invalid for non-integers (including char)
template signed(T : ulong) {
    alias long signed;
}
template signed(T : uint) {
    alias int signed;
}
template signed(T : ushort) {
    alias short signed;
}
template signed(T : ubyte) {
    alias byte signed;
}

///test if a type is signed/unsigned
template isUnsigned(T) {
    const isUnsigned = is(signed!(T));
}
template isSigned(T) {
    const isSigned = is(unsigned!(T));
}

///true if it's an integer
///(isInteger!(char) is false)
template isInteger(T) {
    const isInteger = isSigned!(T) || isUnsigned!(T);
}

template forceUnsigned(T) {
    static assert(isInteger!(T));
    static if (isSigned!(T))
        alias unsigned!(T) forceUnsigned;
    else
        alias T forceUnsigned;
}
template forceSigned(T) {
    static assert(isInteger!(T));
    static if (isUnsigned!(T))
        alias signed!(T) forceSigned;
    else
        alias T forceSigned;
}

//unittest {
    static assert(is(signed!(ulong) == long));
    static assert(is(signed!(ubyte) == byte));
    static assert(is(unsigned!(long) == ulong));
    static assert(is(unsigned!(byte) == ubyte));
    static assert(isSigned!(long) && !isUnsigned!(long));
    static assert(isUnsigned!(uint) && !isSigned!(uint));
    static assert(isInteger!(int) && !isInteger!(char));
    static assert(!isInteger!(float));
    static assert(is(forceSigned!(ushort) == short));
    static assert(is(forceSigned!(short) == short));
    static assert(is(forceUnsigned!(short) == ushort));
    static assert(is(forceUnsigned!(ushort) == ushort));
//}
