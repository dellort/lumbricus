module utils.misc;

import layout = tango.text.convert.Layout;
import intr = tango.core.BitManip;

public import tango.stdc.stdarg : va_list;
public import tango.core.Tuple : Tuple;
import tango.core.Traits : ParameterTupleOf;

//Tango team = stupid
public import tango.math.Math : min, max;

//because printf debugging is common and usefull
//public import tango.util.log.Trace : Trace;
//tango.util.log.Trace now redirects to the Tango logging API, and the format()
//  method is missing too
//the Tango log API may or may not be OK; but I don't trust it (this is more
//  robust, and it is 2726 lines shorter)
class Trace {
    private static Object mutex;
    import cstdio = tango.stdc.stdio;
    static void format(char[] fmt, ...) {
        synchronized(mutex) {
            doprint(fmt, _arguments, _argptr);
        }
    }
    static void formatln(char[] fmt, ...) {
        synchronized(mutex) {
            doprint(fmt, _arguments, _argptr);
            cstdio.fprintf(cstdio.stderr, "\n");
        }
    }
    private static void doprint(char[] fmt, TypeInfo[] arguments, void* argptr)
    {
        uint sink(char[] s) {
            cstdio.fprintf(cstdio.stderr, "%.*s", s.length, s.ptr);
            return s.length;
        }
        layout.Layout!(char).instance().convert(&sink, arguments, argptr, fmt);
    }
    static void flush() {
        //unlike Tango, C is sane; stderr always flushs itself
    }
    static this() {
        mutex = new Object();
    }
}

//marker type for temporary string
//possibly use cases:
//- the Lua interface doesn't allocate+copy a new string if TempString instead
//  of char[] is demarshalled from Lua->D
//- other functions that copy the string anyway
//basically, this reinforces the normal D protocol of treating a string like a
//  garbage collected, immutable string by providing a separate string type for
//  manually managed or stack allocated strings
//NOTE: one can always pass a normal string (char[]) as TempString; it's just
//  that converting a TempString to char[] requires a .dup
//  => char[] should be implicitly conversible to TempString
struct TempString {
    char[] raw;
    //for the dumb
    char[] get() { return raw.dup; }
}

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

//if input is not a power of two, round up to next power of two (I think)
int powerOfTwoRoundUp(int input) {
    int value = 1;

    while ( value < input ) {
        value <<= 1;
    }
    return value;
}

uint log2(uint value)
out (res) {
    assert(value >= (1<<res));
    assert(value < (1<<(res+1)));
}
body {
    return intr.bsr(value);
}

/// Cast object in t to type T, and throw exception if not possible.
/// Only return null if t was already null.
T castStrict(T)(Object t) {
    //static assert (is(T == class) || is(T == interface));
    T res = cast(T)t;
    if (t && !res) {
        static if (is(T == class)) {
            throw new CustomException("could not cast "~t.classinfo.name~" to "
                ~T.classinfo.name);
        } else {
            throw new CustomException("figure it out yourself");
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
//should be in utils.string, but ugh the required changes
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

//functions cannot return static arrays, so this gets the equivalent
//dynamic array type
template RetType(T) {
    static if (is(T T2 : T2[])) {
        alias T2[] RetType;
    } else {
        alias T RetType;
    }
}

template Repeat(int count) { //thx h3
    static if (!count) {
        alias Tuple!() Repeat;
    } else {
        alias Tuple!(count-1, Repeat!(count-1)) Repeat;
    }
}

//returns number of required function arguments, optional arguments excluded
int requiredArgCount(alias Fn)() {
    alias ParameterTupleOf!(typeof(Fn)) Params;
    Params p;
    static if (is(typeof(Fn())))
        return 0;
    foreach (int idx, x; p) {
        static if (is(typeof(Fn(p[0..idx+1]))))
            return idx+1;
    }
}

//parse the result of stringof to get a struct member name; see unittest below
//also works with CTFE
char[] structProcName(char[] tupleString) {
    //struct.tupleof is always fully qualified (obj.x), so get the
    //string after the last .
    //search backwards for '.'
    int p = -1;
    for (int n = tupleString.length - 1; n >= 0; n--) {
        if (tupleString[n] == '.') {
            p = n;
            break;
        }
    }
    assert(p > 0 && p < tupleString.length-1);
    return tupleString[p+1..$];
}

unittest {
    struct Foo {
        int muh;
        bool fool;
    }
    char[][] names;
    Foo f;
    foreach (int idx, _; f.tupleof) {
        const n = structProcName(f.tupleof[idx].stringof);
        names ~= n;
    }
    assert(names == ["muh"[], "fool"]);
}

///all code should throw this instead of 'Exception'
///  (to discern from system errors)
///if you expect a system error, wrap it with this (or a derived class)
class CustomException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

//for parameter checks in "public" api (instead of Assertion)
//special class because it is fatal for D code, but non-fatal for scripts
class ParameterException : Exception {
    this(char[] msg) {
        super(msg);
    }
}
void argcheck(bool condition, char[] msg = "") {
    if (!condition) {
        char[] err = "Invalid parameter";
        if (msg.length) {
            err ~= " (" ~ msg ~ ")";
        }
        throw new ParameterException(err);
    }
}
//value must not be null
void argcheck(Object value) {
    argcheck(!!value, "object expected, got null");
}
