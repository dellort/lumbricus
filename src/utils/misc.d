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


/+
Problem: D is too stupid to give me char[] of the names of enum items
Solution: do something ridiculously complicated in CTFE and using string mixins,
    which happen to be the most advanced features of D, just to implement
    a very simple feature, that would be trivially implementable inside the
    compiler.

emulate the bultin enum type by using a struct
works like this:
    struct Enum(T) { ... }
    Enum!("x1,x2,x3") E;

Fields must be a list of identifiers, separated by ","
xxx whitespace isn't handled yet, so don't insert it
invalid identifiers will probably cause chaotic CTFE errors

underlying type is always int
default value is the first enum item
+/
struct Enum(char[] Fields) {
    //other code may need this to check for the template type, see isMyEnum()
    static const FieldsString = Fields;

    //actual integer value for the enum
    private int m_value = 0;

    //integer value
    int value() {
        return m_value;
    }

    static Enum fromInteger(int v) {
        assert(v >= min.value && v <= max.value);
        Enum res;
        res.m_value = v;
        return res;
    }

    //return the string representation of the stored value
    char[] toString() {
        return FieldNames[m_value];
    }

    //throw Exception on error
    static Enum fromString(char[] s) {
        foreach (int index, char[] item; FieldNames) {
            if (item == s)
                return fromInteger(index);
        }
        throw new Exception("invalid enum string: " ~ s);
    }

    //CTFE garbage follows

    private static char[] generate(char[] fields) {
        char[][] pfields = ctfe_split(fields, ',');
        assert(pfields.length > 0, "Enum with 0 elements");
        //actually generate fields
        char[] code1, code2;
        code1 = `static const char[][] FieldNames = [`;
        foreach (int index, char[] f; pfields) {
            code1 ~= `"` ~ f ~ `", `;
            code2 ~= `static const Enum ` ~ f ~ ` = dmd_is_buggy(`
                ~ ctfe_itoa(index) ~ `);` \n;
        }
        code1 ~= `];` \n;
        code2 ~= `alias ` ~ pfields[0] ~ ` min;` \n;
        code2 ~= `alias ` ~ pfields[$-1] ~ ` max;` \n;
        return code1 ~ code2;
    }

    mixin(generate(Fields));
    //pragma(msg, generate(Fields));

    //direct initializers ( static const Enum foo = {m_value:0}; ) don't work,
    //they silently fail at runtime and m_value has a wrong value
    //also, this function must come after the mixin, else you will get strange
    //incomprehensible (hey, I'm not even joking) error messages
    private static Enum dmd_is_buggy(int v) {
        Enum e;
        e.m_value = v;
        return e;
    }
}

template isMyEnum(T) {
    const bool isMyEnum = is(Enum!(T.FieldsString) == T);
}

unittest {
    alias Enum!("a,bee,c") E;
    static assert (isMyEnum!(E));
    static assert (!isMyEnum!(int));
    assert(E.min == E.a);
    assert(E.max == E.c);
    E x;
    assert(x == E.a);
    x = E.c;
    assert(x == E.c);
    assert(x.toString == "c");
    E x2 = E.fromString("bee");
    assert(x2 == E.bee);
    assert(x2.toString == "bee");
    /+ doesn't work
    switch (x2) {
        case E.a:
        case E.bee, E.c:
    }
    +/
}
