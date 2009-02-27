module utils.misc;

import str = stdx.string;
import utf = stdx.utf;
import layout = tango.text.convert.Layout;

public import tango.stdc.stdarg : va_list;

//Tango team = stupid
public import tango.math.Math : min, max;

//because printf debugging is common and usefull
public import tango.io.Stdout : Stdout;

T realmod(T)(T a, T m) {
    T res = a % m;
    if (res < 0)
        res += m;
    return res;
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
    return layout.Layout!(char).instance().convert(arguments, argptr, a_fmt);
    //Phobos for now
    //char[] res;
    //fmt.doFormat((dchar c) { utf.encode(res, c); }, a_fmt, arguments, argptr);
    //return res;
}

//replacement for stdx.string.format()
//trivial, but Tango really is annoyingly noisy
char[] myformat(char[] fmt, ...) {
    return formatfx(fmt, _arguments, _argptr);
}

//if the buffer is too small, allocate a new one
char[] formatfx_s(char[] buffer, char[] fmt, TypeInfo[] arguments,
    va_list argptr)
{
    //NOTE: there's Layout.vprint(), but it simply cuts the output if the buffer
    //      is too small (and you don't know if this happened)
    char[] output = buffer;
    size_t outpos = 0;
    uint sink(char[] append) {
        auto end = outpos + append.length;
        if (end > buffer.length) {
            //(force reallocation, never resize buffer's memory block)
            if (output.ptr == buffer.ptr)
                output = buffer.dup;
            output = output[0..outpos];
            output ~= append;
        } else {
            output[outpos..end] = append;
        }
        outpos = end;
        return append.length; //whatever... what the fuck is this for?
    }
    layout.Layout!(char).instance().convert(&sink, arguments, argptr, fmt);
    return output[0..outpos];
}

//like myformat(), but use the buffer
//if the buffer is too small, allocate a new one
char[] myformat_s(char[] buffer, char[] fmt, ...) {
    return formatfx_s(buffer, fmt, _arguments, _argptr);
}

/// number of bytes to a string like "number XX", where XX is "B", "KB" etc.
/// buffer = if long enough, use this instead of allocating memory
char[] sizeToHuman(long bytes, char[] buffer = null) {
    const char[][] cSizes = ["B", "KB", "MB", "GB"];
    int n;
    long x;
    x = 1;
    while (bytes >= x*1024 && n < cSizes.length-1) {
        x = x*1024;
        n++;
    }
    //xxx: ugly trailing zeros
    return myformat_s(buffer, "{:f3} {}", 1.0*bytes/x, cSizes[n]);
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
