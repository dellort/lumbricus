module utils.misc;

import tango.text.convert.Format;
import intr = tango.core.BitManip;
import runtime = tango.core.Runtime;

public import tango.stdc.stdarg : va_list;
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

    static void write(string s) {
        runtime.Runtime.console.stderr(s);
    }
    static void flush() {
        //Runtime.console should write directly to stderr; no buffering anywhere
    }

    static void format(string fmt, ...) {
        synchronized(Trace.classinfo) {
            doprint(fmt, _arguments, _argptr);
        }
    }
    static void formatln(string fmt, ...) {
        synchronized(Trace.classinfo) {
            doprint(fmt, _arguments, _argptr);
            write("\n");
        }
    }

    private static void doprint(string fmt, TypeInfo[] arguments, void* argptr)
    {
        uint sink(string s) {
            write(s);
            return s.length;
        }
        Format.convert(&sink, arguments, argptr, fmt);
    }
}

//marker type for temporary string
//possible use cases:
//- the Lua interface doesn't allocate+copy a new string if TempString instead
//  of string is demarshalled from Lua->D
//- other functions that copy the string anyway
//basically, this reinforces the normal D protocol of treating a string like a
//  garbage collected, immutable string by providing a separate string type for
//  manually managed or stack allocated strings
//NOTE: one can always pass a normal string (string) as TempString; it's just
//  that converting a TempString to string requires a .dup
//  => string should be implicitly conversible to TempString
struct TempString {
    string raw;
    //for the dumb
    string get() { return raw.dup; }
}

//behave mathematically correctly for negative values
//e.g. -1 % 3 == -1, but realmod(-1, 3) == 2
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

//set array.length = length, but in such a way that future appends will reuse
//  the already present array capacity - no-op in D1, but not in D2 (in D2,
//  int[] x; x ~= 1; x.length = 0; x ~= 2; will allocate two arrays!)
void resetLength(T)(T[] array, size_t length = 0) {
    array.length = length;
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

string myformat_fx(string a_fmt, TypeInfo[] arguments, va_list argptr) {
    return Format.convert(arguments, argptr, a_fmt);
}

//replacement for stdx.string.format()
//trivial, but Tango really is annoyingly noisy
//should be in utils.string, but ugh the required changes
string myformat(string fmt, ...) {
    return myformat_fx(fmt, _arguments, _argptr);
}

//make it simpler to append to a string without memory allocation
//StrBuffer.sink() will append a string using the provided memory buffer
//if the memory buffer is too short, it falls back to heap allocation
struct StrBuffer {
    string buffer;  //static buffer passed by user
    string output;  //append buffer (may be larger than actual string)
    size_t outpos;  //output[0..outpos] is actual (valid) string

    static StrBuffer opCall(string buffer) {
        StrBuffer s;
        s.buffer = buffer;
        s.output = s.buffer;
        return s;
    }

    void sink(string append) {
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
    }

    //like sink, but compatible with Tango
    uint tsink(string s) {
        sink(s);
        return s.length; //????
    }

    //retrieve actual string
    string get() {
        return output[0..outpos];
    }

    //reuse the buffer by setting outpos to 0
    //the previous result of get() will get invalid
    void reset() {
        outpos = 0;
    }
}

//if the buffer is too small, allocate a new one
string myformat_s_fx(string buffer, string fmt, TypeInfo[] arguments,
    va_list argptr)
{
    //NOTE: there's Layout.vprint(), but it simply cuts the output if the buffer
    //      is too small (and you don't know if this happened)
    auto buf = StrBuffer(buffer);
    Format.convert(&buf.tsink, arguments, argptr, fmt);
    return buf.get;
}

//like myformat(), but use the buffer
//if the buffer is too small, allocate a new one
string myformat_s(string buffer, string fmt, ...) {
    return myformat_s_fx(buffer, fmt, _arguments, _argptr);
}

void myformat_cb_fx(void delegate(string s) sink, string fmt,
    TypeInfo[] arguments, va_list argptr)
{
    uint xsink(string s) { sink(s); return s.length; }
    return Format.convert(&xsink, arguments, argptr, fmt);
}
void myformat_cb(void delegate(string s) sink, string fmt, ...) {
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

//as defined in D2 std.typetuple
//Tango has the same thing a type Tuple in tango.core.Tuple
template TypeTuple(TList...) {
    alias TList TypeTuple;
}

template Repeat(int count) { //thx h3
    static if (!count) {
        alias TypeTuple!() Repeat;
    } else {
        alias TypeTuple!(count-1, Repeat!(count-1)) Repeat;
    }
}

//D is crap, thus D can't return real tuples from functions
//have to use a wrapper struct to do this
//this is similar to the definition in D2 (minus bloated clusterfuck)
struct Tuple(T...) {
    T fields;
    //use this if you rely on tuple expansion
    alias fields expand;
}

//construct a Tuple (D2 also has this function)
Tuple!(T) tuple(T...)(T args) {
    return Tuple!(T)(args);
}

unittest {
    auto x = tuple(1, 2.3);
    assert(x.fields[0] == 1 && x.fields[1] == 2.3);
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
        private string[] get() {
            string[] res;
            const string st = T.tupleof.stringof;
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
        private string structProcName(string tupleString) {
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
        private string[] get() {
            string[] res;
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
string[] structMemberNames(T)() {
    //the template is to cache the result (no idea if that works as intended)
    return StructMemberNames!(T).StructMemberNames;
}

debug {
    enum E { x }

    struct N(T, string S) {
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
    string[] names = structMemberNames!(Foo)();
    assert(names == ["muh"[], "fool"]);
}

///all code should throw this instead of 'Exception'
///  (to discern from system errors)
///if you expect a system error, wrap it with this (or a derived class)
///also see require()
class CustomException : Exception {
    this(string msg, Exception n = null) {
        super(msg, n);
    }
}

//I got tired of retyping throw new CustomException...
void throwError(string fmt, ...) {
    throw new CustomException(myformat_fx(fmt, _arguments, _argptr));
}

//like assert(), but throw a recoverable CustomException on failure
//similar to D2's enforce() or Scala's require()
//  use require() when: there's something wrong, but it's not fatal; operation
//      can be resumed after catching the exception thrown by this function, and
//      the operation can possibly be retried by the caller.
//  use assert() when: there's something wrong, but you can't restore your state
//      to how it was before, and/or there's no way to safely proceed. catching
//      the exception won't remove the inconsistent/bugged state.
//  argcheck(): same as require(), but hint to the user that something is wrong
//      with the parameters passed to the function.
//  throwError()/CustomException: really the same as require().
void require(bool cond, string msg = "Something went wrong.", ...) {
    if (cond)
        return;
    throw new CustomException(myformat_fx(msg, _arguments, _argptr));
}

//exception thrown by argcheck
class ParameterException : CustomException {
    this(string msg) {
        super(msg);
    }
}
void argcheck(bool condition, string msg = "") {
    if (!condition) {
        string err = "Invalid parameter";
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

//retarded version of std.bind
//it takes a context value and a function with a context param as first
//  parameter
//it returns a delegate, which will call the function with that context value
//  (i.e. the delegate won't have the context value)
//basically, you can write:
//  static int foo(Object x, int a, int b) { ... }
//  int delegate(int a, int b) foo = bindfn(x, &foo);
//you can use this to work around D1's missing real closures (D2 has them) -
//  making the fn parameter a function (instead of a delegate) is intended to
//  ensure you're not accidentally using any stack parameters
//NOTE: it's forced to one bindable parameter, because that's simpler; surely
//  you could use tuples to extend it further
//toDelegate() would be a version of this function with no bound parameters
template bindfn(Tret, BoundParam1, ParamRest...) {
    Tret delegate(ParamRest)
        bindfn(BoundParam1 p1, Tret function(BoundParam1, ParamRest) fn)
    {
        struct Closure {
            BoundParam1 m_p1;
            typeof(fn) m_fn;
            Tret call(ParamRest p) {
                return m_fn(m_p1, p);
            }
        }
        Closure* c = new Closure;
        c.m_p1 = p1;
        c.m_fn = fn;
        return &c.call;
    }
}

unittest {
    void delegate() d1 = bindfn(123, function void(int x) {
        assert(x == 123);
    });
    d1(); d1();
    int delegate(int) d2 = bindfn(123, function int(int x, int y) {
        assert(x == 123);
        return x + y;
    });
    assert(d2(333) == 456);
}
