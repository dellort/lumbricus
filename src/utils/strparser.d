//Contains string->type parsers for all value types available in this directory
//(including native types).
module utils.strparser;
import utils.mybox;
import tango.util.Convert : to;
import tango.text.convert.Float : toFloat;
import tango.core.Exception;
import str = utils.string;
import utils.misc;

public import tango.util.Convert : ConversionException;

//xxx function, should be delegate
//convention: return empty box if not parseable
alias MyBox function(char[] s) BoxParseString;
//stupidity note: std.format() can do the same, but varargs suck so much in D,
// that this functionality can't be used without writing unportable code
alias char[] function(MyBox box) BoxUnParse;

BoxParseString[TypeInfo] gBoxParsers;
BoxUnParse[TypeInfo] gBoxUnParsers;


///sorry Tango
///T = the type being parsed (for the fromString() function)
///parsetext = the string being parsed (for now, the whole string)
///details = optional human readable error description
ConversionException newConversionException(T)(char[] parsetext,
    char[] details = "unknown")
{
    return new ConversionException(myformat("Can not parse {}: '{}',"
        ~ " reason: {}", typeid(T), parsetext, details));
}



bool hasBoxParser(TypeInfo info) {
    return !!(info in gBoxParsers);
}

MyBox stringToBoxTypeID(TypeInfo info, char[] s) {
    return gBoxParsers[info](s);
}

MyBox stringToBox(T)(char[] s) {
    return stringToBoxTypeID(typeid(T), s);
}

T stringToType(T)(char[] s) {
    MyBox res = stringToBoxTypeID(typeid(T), s);
    if (res.empty()) {
        newConversionException!(T)(s);
    }
    return res.unbox!(T)();
}
void stringToType(T)(ref T dest, char[] s) {
    dest = stringToType!(T)(s);
}
char[] typeToString(T)(T x) {
    return boxToString(MyBox.Box!(T)(x));
}

char[] boxToString(MyBox box) {
    return gBoxUnParsers[box.type()](box);
}

//like stringToType, but compile-time lookup
//supports all basic types (to() function) and structs that have a "fromString"
//  static member
//throws ConversionException if s could not be parsed, or an overflow occured
//xxx the tango to() function should do exactly that, but because the tango
//    runtime is not compiled with the project, template lookup fails
T fromStr(T)(char[] s) {
    static if (is(T == char[])) {
        return s;
    } else static if (is( typeof(T.fromString(s)) : T )) {
        //Type.fromString()
        return T.fromString(s);
    } else static if (is( typeof(to!(T)(s)) == T )) {
        //to() function
        //we don't support empty strings
        if (s.length == 0)
            throw new ConversionException("to!("~T.stringof~"): trying to parse"
                ~ " empty string");
        return to!(T)(s);
    } else {
        static assert(false, "Cannot parse: "~T.stringof);
    }
}
template fromStrSupports(T) {
    const bool fromStrSupports =
        is(typeof( { fromStr!(T)(cast(char[])null); } ));
}
//return false and leaves destVal unmodified if parsing failed
bool tryFromStr(T)(char[] s, ref T destVal) {
    try {
        destVal = fromStr!(T)(s);
        return true;
    } catch (ConversionException e) {
        return false;
    }
}

T tryFromStrDef(T)(char[] s, T def = T.init) {
    try {
        return fromStr!(T)(s);
    } catch (ConversionException e) {
        return def;
    }
}

//reverse of above
//structs require a fromStringRev() (sry for this name) member
char[] toStr(T)(T value) {
    static if (is(T == char[])) {
        return value;
    } else static if (is( typeof(value.fromStringRev()) == char[] )) {
        //Type.fromStringRev()
        //mostly, value.toString() if for a more "readable" representation
        return value.fromStringRev();
    } else static if (is( typeof(to!(char[])(value)) == char[] )) {
        //to() function
        return to!(char[])(value);
    } else {
        static assert(false, "Cannot stringify: "~T.stringof);
    }
}
template toStrSupports(T) {
    const bool toStrSupports = is(typeof( { toStr!(T)(T.init); } ));
}

static this() {
    gBoxParsers[typeid(char[])] = &boxParseStr;
    gBoxUnParsers[typeid(char[])] = &boxUnParseStr;

    addTrivialParsers!(byte, int, long, short, ubyte, uint, ulong, ushort,
        float, double, real)();
    addTrivialUnParser!(char)();

    //keeping this one special for yes/no strings
    gBoxParsers[typeid(bool)] = &boxParseBool;
    addTrivialUnParser!(bool)();
}

private void addTrivialParsers(T...)() {
    foreach (x; T) {
        addTrivialParser!(x)();
        addTrivialUnParser!(x)();
    }
}

void addTrivialParser(T)() {
    static assert(fromStrSupports!(T));
    gBoxParsers[typeid(T)] = function MyBox(char[] s) {
        try {
            return MyBox.Box!(T)(fromStr!(T)(s));
        } catch (ConversionException e) {
            return MyBox();
        }
    };
}
void addTrivialUnParser(T)() {
    static assert(toStrSupports!(T));
    gBoxUnParsers[typeid(T)] = function char[](MyBox box) {
        return toStr(box.unbox!(T));
    };
}

//connect our new .fromStr business with box parser
void addStrParser(T)() {
    addTrivialParser!(T)();
    addTrivialUnParser!(T)();
}

//the nop
public MyBox boxParseStr(char[] s) {
    return MyBox.Box!(char[])(s);
}
public char[] boxUnParseStr(MyBox b) {
    return b.unbox!(char[]);
}

public MyBox boxParseBool(char[] s) {
    //strings for truth values, alternating (sorry it was 4:28 AM)
    static char[][] bool_strings = ["true", "false", "yes", "no"]; //etc.
    bool ret_value = true;
    foreach(char[] test; bool_strings) {
        if (str.tolower(s) == test) {
            return MyBox.Box!(bool)(ret_value);
        }
        ret_value = !ret_value;
    }
    return MyBox();
}

/+
Problem: get the names of enum items

register all enum items at runtime:
    void enumStrings(EnumType, char[] fields)();
works like this:
    enum E { x1, x2, x3 }
    enumStrings!(E, "x1,x2,x3");
the nice thing is that the strings are tested at compile time if they are valid
enum items, and the enum value is correctly obtained even if the order is
different etc.

can't deal with whitespace in the fields-string correctly
+/

private struct EnumItem {
    char[] name;
    int value;
}

private static EnumItem[] enum_get_vals(EnumType, char[] fields)() {
    EnumType X;
    static char[] gen_code() {
        char[][] pfields = str.ctfe_split(fields, ',');
        char[] code = "[";
        foreach (int idx, s; pfields) {
            if (idx != 0)
                code ~= ",";
            code ~= `EnumItem("` ~ s ~ `", typeof(X)` ~ "." ~ s ~ `)`;
        }
        code ~= "]";
        return code;
    }
    mixin(`return ` ~ gen_code() ~ `;`);
}

void enumStrings(EnumType, char[] fields)() {
    static assert(is(EnumType == enum));

    static const EnumItem[] items = enum_get_vals!(EnumType, fields)();

    static char[] box_unparse_enum(MyBox b) {
        EnumType val = b.unbox!(EnumType)();
        assert(val >= EnumType.min && val <= EnumType.max);
        foreach (ref EnumItem e; items) {
            if (e.value == val)
                return e.name;
        }
        //internal error
        assert(false, myformat("undefined enum value: ", val));
    }

    static MyBox box_parse_enum(char[] s) {
        foreach (ref EnumItem e; items) {
            if (e.name == s)
                return MyBox.Box!(EnumType)(cast(EnumType)e.value);
        }
        return MyBox();
    }

    //don't do all the work again (might not work as intended, of course)
    if (typeid(EnumType) in gBoxParsers)
        return;

    //sanity test: make sure all valid enum values are covered
    //not sure if this the right thing to do, because you can't really enumerate
    //all enum items, you only have .max and .min
    bool[] covered;
    covered.length = EnumType.max - EnumType.min + 1;
    foreach (EnumItem e; items) {
        covered[e.value - EnumType.min] = true;
    }
    foreach (int idx, bool b; covered) {
        assert(b, myformat("for type {}, enum item with numerical value {} is"
            " not covered by enumStrings() call, field args: '{}'",
            typeid(EnumType), idx + EnumType.min, fields));
    }

    gBoxUnParsers[typeid(EnumType)] = &box_unparse_enum;
    gBoxParsers[typeid(EnumType)] = &box_parse_enum;
}

unittest {
    assert(fromStr!(int)("123") == 123);
    assert(toStr(123) == "123");

    assert(stringToBox!(int)("123").unbox!(int) == 123);
    assert(stringToBox!(int)("abc").type is null);
    assert(stringToBox!(int)("1abc").type is null);
    assert(stringToBox!(int)("").type is null);
    //bug or feature?
    assert(stringToBox!(int)(" 123").unbox!(int) == 123);
    assert(stringToBox!(int)("123 ").type is null);

    assert(stringToBox!(float)("123.25").unbox!(float) == 123.25f);
    assert(stringToBox!(float)("abc").type is null);
    assert(stringToBox!(float)("1.0abc").type is null);
    assert(stringToBox!(float)("").type is null);
    //same behaviour as with int
    assert(stringToBox!(float)(" 123").unbox!(float) == 123f);
    assert(stringToBox!(float)("123 ").type is null);

    assert(stringToBox!(bool)("false").unbox!(bool) == false);
    assert(stringToBox!(bool)("yes").unbox!(bool) == true);
    assert(stringToBox!(bool)("").type is null);

    /+
    debug testParse("+123.0");
    debug testParse("1 2");
    debug testParse("1 2.0");
    +/

    //---- for the enum crap

    //(LOL DMD: directly defining the enum without struct X causes linker error)
    struct X {
        enum BlaTest {
            x1=5,
            fgf,
            x2,
        }
    }
    alias X.BlaTest BlaTest;

    //should fail at runtime with an assertion (missing value)
    //-- enumStrings!(BlaTest, "x1,x2");
    //should fail at compile time (can't find doesnotexist)
    //-- enumStrings!(BlaTest, "x1,doesnotexist");

    enumStrings!(BlaTest, "x1,fgf,x2");
    assert(stringToType!(BlaTest)("x1") == BlaTest.x1);
    assert(stringToType!(BlaTest)("x2") == BlaTest.x2);
    assert(boxToString(MyBox.Box(BlaTest.fgf)) == "fgf");

    static assert(!toStrSupports!(X));
    static assert(!fromStrSupports!(X));
}
