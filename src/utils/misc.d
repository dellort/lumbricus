module utils.misc;

import layout = tango.text.convert.Layout;
import intr = tango.core.BitManip;
import runtime = tango.core.Runtime;

public import tango.stdc.stdarg : va_list;
public import tango.core.Tuple : Tuple;
//import tango.core.Traits : ParameterTupleOf;

//Tango team = stupid (defining your own min/max functions will conflict)
public import tango.math.Math : min, max;
import tango.math.Math : abs;

//because printf debugging is common and usefull
//public import tango.util.log.Trace : Trace;
//tango.util.log.Trace now redirects to the Tango logging API, and the format()
//  method is missing too
//the Tango log API may or may not be OK; but I don't trust it (this is more
//  robust, and it is 2726 lines shorter)
class Trace {

    static void write(char[] s) {
        runtime.Runtime.console.stderr(s);
    }
    static void flush() {
        //Runtime.console should write directly to stderr; no buffering anywhere
    }

    static void format(char[] fmt, ...) {
        synchronized(Trace.classinfo) {
            doprint(fmt, _arguments, _argptr);
        }
    }
    static void formatln(char[] fmt, ...) {
        synchronized(Trace.classinfo) {
            doprint(fmt, _arguments, _argptr);
            write("\n");
        }
    }

    private static void doprint(char[] fmt, TypeInfo[] arguments, void* argptr)
    {
        uint sink(char[] s) {
            write(s);
            return s.length;
        }
        layout.Layout!(char).instance().convert(&sink, arguments, argptr, fmt);
    }
}

//marker type for temporary string
//possible use cases:
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

//whether an index into the array is valid
bool indexValid(T)(T[] array, uint index) {
    //uint takes care of the >= 0
    return index < array.length;
}

//whether array[a..b] would be valid (and not cause an exception)
bool sliceValid(T)(T[] array, uint a, uint b) {
    //uint takes care of the >= 0
    return a <= array.length && b <= array.length && a <= b;
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

//[0 .. 0.5 .. 1] -> [valLow .. valMid .. valHigh]
//T needs opMul(float)
T map3(T)(float ratio, T valLow, T valMid, T valHigh) {
    float r_v1 = clampRangeC(1.0f - ratio * 2.0f, 0f, 1f);
    float r_v2 = clampRangeC!(float)(1.0f - abs((ratio - 0.5f) * 2.0f),
        0f, 1f);
    float r_v3 = clampRangeC(ratio * 2.0f - 1.0f, 0f, 1f);

    return valLow * r_v1 + valMid * r_v2 + valHigh * r_v3;
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

char[] myformat_fx(char[] a_fmt, TypeInfo[] arguments, va_list argptr) {
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
    return myformat_fx(fmt, _arguments, _argptr);
}

//if the buffer is too small, allocate a new one
char[] myformat_s_fx(char[] buffer, char[] fmt, TypeInfo[] arguments,
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
    return myformat_s_fx(buffer, fmt, _arguments, _argptr);
}

void myformat_cb_fx(void delegate(char[] s) sink, char[] fmt,
    TypeInfo[] arguments, va_list argptr)
{
    uint xsink(char[] s) { sink(s); return s.length; }
    return layout.Layout!(char).instance().convert(&xsink, arguments, argptr,
        fmt);
}
void myformat_cb(void delegate(char[] s) sink, char[] fmt, ...) {
    myformat_cb_fx(sink, fmt, _arguments, _argptr);
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

/+

This function is dangerous because of dmd bug 4028.
Basically, if you pass a delegate type, the return value may be more or less
random. Function types are also affected.

It still works if you pass a function symbol directly (alias parameters pass
symbols, and there aren't any delegate/function types, which would be affected
by bug 4028).

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
    assert(false);
}

unittest {
    void foo1(int x) {
    }
    void foo2(int x = 123) {
    }
    void foo3(int x, int y = 123, int z = 456) {
    }
    void foo4(int x, int y, int z) {
    }
    static assert(requiredArgCount!(foo1)() == 1);
    static assert(requiredArgCount!(foo2)() == 0);
    static assert(requiredArgCount!(foo3)() == 1);
    auto x1 = &foo3;
    auto x2 = &foo4;
    static assert(requiredArgCount!(x1)() == 1);
    static assert(requiredArgCount!(x2)() == 3);
}

+/

//can remove this as soon as dmd bug 2881 gets fixed
version = bug2881;

version (bug2881) {
} else {
    //test for http://d.puremagic.com/issues/show_bug.cgi?id=2881
    //(other static asserts will throw; this is just to output a good error message)
    private enum _Compiler_Test {
        x,
    }
    private _Compiler_Test _test_enum;
    static assert(_test_enum.stringof == "_test_enum", "Get a dmd version "
        "where #2881 is fixed (or patch dmd yourself)");
}

//once for each type
//a simpler approach can be used once dmd bug 2881 is fixed
private template StructMemberNames(T) {
    version (bug2881) {
        private char[][] get() {
            char[][] res;
            const char[] st = T.tupleof.stringof;
            //currently, dmd produces something like "tuple((Type).a,(Type).b)"
            //the really bad thing is that it really inline expands the Type,
            //  and "Type" can contain further brackets and quoted strings (!!!)
            //which means it's way too hard to support the general case; so if T
            //  is a template with strings as parameter, stuff might break
            static assert(st[0..6] == "tuple(");
            static assert(st[$-1] == ')');
            const s = st[6..$-1];
            //(Type).a,(Type).b
            //p = current position in s (slicing is costly in CTFE mode)
            int p = 0;
            while (p < s.length) {
                //skip brackets and nested brackets
                assert(s[p] == '(');
                int b = 1;
                p++;
                while (b != 0) {
                    if (s[p] == '(')
                        b++;
                    else if (s[p] == ')')
                        b--;
                    p++;
                }
                //skip dot that "qualifies" the member name (actually, wtf?)
                assert(s[p] == '.');
                p++;
                //start must point to the struct member name
                int start = p;
                //find next ',' or end-of-string
                while (s[p] != ',') {
                    p++;
                    if (p == s.length)
                        break;
                }
                res ~= s[start..p];
                p++;
            }
            return res;
        }
    } else { //version(bug2881)
        //warning: dmd bug 2881 ruins this
        private char[] structProcName(char[] tupleString) {
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
        private char[][] get() {
            char[][] res;
            T x;
            foreach (int idx, _; x.tupleof) {
                const n = structProcName(x.tupleof[idx].stringof);
                res ~= n;
            }
            return res;
        }
    }

    const StructMemberNames = get();
}

//similar to structProcName; return an array of all members
//unlike structProcName, this successfully works around dmd bug 2881
//this should actually be implemented using __traits (only available in D2)
char[][] structMemberNames(T)() {
    //the template is to cache the result (no idea if that works as intended)
    return StructMemberNames!(T).StructMemberNames;
}

debug {
    enum E { x }

    struct N(T, char[] S) {
        T abc;
        E defg;
    }

    //brackets in the template parameter string would break it
    alias N!(int, "foo\"hu") X;

    unittest {
        const names = structMemberNames!(X)();
        static assert(names == ["abc", "defg"]);
    }
}

unittest {
    struct Foo {
        int muh;
        bool fool;
    }
    char[][] names = structMemberNames!(Foo)();
    assert(names == ["muh"[], "fool"]);
}

///all code should throw this instead of 'Exception'
///  (to discern from system errors)
///if you expect a system error, wrap it with this (or a derived class)
class CustomException : Exception {
    this(char[] msg, Exception n = null) {
        super(msg, n);
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
