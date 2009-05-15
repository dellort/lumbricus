module utils.misc;

import str = stdx.string;
import utf = stdx.utf;
import layout = tango.text.convert.Layout;

public import tango.stdc.stdarg : va_list;

//Tango team = stupid
public import tango.math.Math : min, max;

//because printf debugging is common and usefull
public import tango.util.log.Trace : Trace;

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

//return an array of length 2 (actual return type should be char[][2])
//result[1] contains everything in txt after (and including) find
//result[0] contains the rest (especially if nothing found)
//  split2("abcd", 'c') == ["ab", "cd"]
//  split2("abcd", 'x') == ["abcd", ""]
//(sadly allocates memory for return array)
char[][] split2(char[] txt, char find) {
    int idx = str.find(txt, find);
    char[] before = txt[0 .. idx >= 0 ? idx : $];
    char[] after = txt[before.length .. $];
    return [before, after];
}

unittest {
    assert(split2("abcd", 'c') == ["ab", "cd"]);
    assert(split2("abcd", 'x') == ["abcd", ""]);
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
    char[80] buffer2 = void;
    char[] s = myformat_s(buffer2, "{:f3}", 1.0*bytes/x);
    //strip ugly trailing zeros (replace with a better way if you know one)
    if (str.find(s, '.') >= 0) {
        while (s[$-1] == '0')
            s = s[0..$-1];
        if (endsWith(s, "."))
            s = s[0..$-1];
    }
    return myformat_s(buffer, "{} {}", s, cSizes[n]);
}

unittest {
    assert(sizeToHuman(0) == "0 B");
    assert(sizeToHuman(1023) == "1023 B");
    assert(sizeToHuman(1024) == "1 KB");
    assert(sizeToHuman((1024+512)*1024) == "1.5 MB");
}

char[][] ctfe_split(char[] s, char sep) {
    char[][] ps;
    bool cont = true;
    while (cont) {
        cont = false;
        for (int n = 0; n < s.length; n++) {
            if (s[n] == sep) {
                ps ~= s[0..n];
                s = s[n+1..$];
                cont = true;
                break;
            }
        }
    }
    ps ~= s;
    return ps;
}

char[] ctfe_itoa(int i) {
    char[] res;
    do {
        res = "0123456789"[i % 10] ~ res;
        i = i/10;
    } while (i > 0);
    return res;
}

