//Contains string->type parsers for all value types available in this directory
//(including native types).
module utils.strparser;
import utils.mybox;
import conv = tango.util.Convert;
import tango.text.convert.Float : toFloat;
import tango.core.Exception;
import str = stdx.string;
import utils.misc;

import utils.vector2 : Vector2, Vector2i, Vector2f;

//xxx function, should be delegate
//convention: return empty box if not parseable
alias MyBox function(char[] s) BoxParseString;
//stupidity note: std.format() can do the same, but varargs suck so much in D,
// that this functionality can't be used without writing unportable code
alias char[] function(MyBox box) BoxUnParse;

BoxParseString[TypeInfo] gBoxParsers;
BoxUnParse[TypeInfo] gBoxUnParsers;

MyBox stringToBoxTypeID(TypeInfo info, char[] s) {
    return gBoxParsers[info](s);
}

MyBox stringToBox(T)(char[] s) {
    return stringToBoxTypeID(typeid(T), s);
}

T stringToType(T)(char[] s) {
    MyBox res = stringToBoxTypeID(typeid(T), s);
    if (res.empty()) {
        throw new Exception(myformat("can't parse '{}' to type {}", s,
            typeid(T)));
    }
    return res.unbox!(T)();
}

char[] boxToString(MyBox box) {
    return gBoxUnParsers[box.type()](box);
}

static this() {
    gBoxParsers[typeid(char[])] = &boxParseStr;
    gBoxParsers[typeid(int)] = &boxParseInt;
    gBoxParsers[typeid(float)] = &boxParseFloat;
    gBoxParsers[typeid(bool)] = &boxParseBool;
    gBoxParsers[typeid(Vector2i)] = &boxParseVector2i;
    gBoxParsers[typeid(Vector2f)] = &boxParseVector2f;
    addTrivialUnParsers!(byte, int, long, short, ubyte, uint, ulong, ushort,
        char, float, double, bool)();
    gBoxUnParsers[typeid(Vector2i)] = &boxUnParseVector2i;
    gBoxUnParsers[typeid(Vector2f)] = &boxUnParseVector2f;
    gBoxUnParsers[typeid(char[])] = &boxUnParseStr;
}

private void addTrivialUnParsers(T...)() {
    foreach (x; T) {
        gBoxUnParsers[typeid(x)] = function char[](MyBox box) {
            return str.toString(box.unbox!(x));
        };
    }
}

//the nop
public MyBox boxParseStr(char[] s) {
    return MyBox.Box!(char[])(s);
}
public char[] boxUnParseStr(MyBox b) {
    return b.unbox!(char[]);
}

//stolen from configfile.d
public MyBox boxParseInt(char[] s) {
    try {
        //tango.text.convert.Integer.toInt() parses an empty string as 0
        if (s.length > 0)
            return MyBox.Box!(int)(conv.to!(int)(s));
    } catch (conv.ConversionException e) {
    }
    return MyBox();
}
public MyBox boxParseFloat(char[] s) {
    try {
        //tango.text.convert.Float.toFloat() parses an empty string as 0.0f
        //also, tango.util.Convert.to!(float) seems to be major crap
        if (s.length > 0)
            return MyBox.Box!(float)(toFloat(s));
    } catch (IllegalArgumentException e) {
    }
    return MyBox();
}
public MyBox boxParseBool(char[] s) {
    //strings for truth values, alternating (sorry it was 4:28 AM)
    static char[][] bool_strings = ["true", "false", "yes", "no"]; //etc.
    bool ret_value = true;
    foreach(char[] test; bool_strings) {
        if (str.icmp(test, s) == 0) {
            return MyBox.Box!(bool)(ret_value);
        }
        ret_value = !ret_value;
    }
    return MyBox();
}

//3rd place of code duplication
private MyBox boxParseVector(T)(char[] s) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        return MyBox();
    }
    try {
        Vector2!(T) pt;
        pt.x = conv.to!(T)(items[0]);
        pt.y = conv.to!(T)(items[1]);
        return MyBox.Box!(Vector2!(T))(pt);
    } catch (conv.ConversionException e) {
    }
    return MyBox();
}
public MyBox boxParseVector2i(char[] s) {
    return boxParseVector!(int)(s);
}
public MyBox boxParseVector2f(char[] s) {
    return boxParseVector!(float)(s);
}

public char[] boxUnParseVector2f(MyBox b) {
    auto v = b.unbox!(Vector2f)();
    return myformat("{} {}", v.x, v.y);
}

public char[] boxUnParseVector2i(MyBox b) {
    auto v = b.unbox!(Vector2i)();
    return myformat("{} {}", v.x, v.y);
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
        char[][] pfields = ctfe_split(fields, ',');
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
        foreach (EnumItem e; items) {
            if (e.value == val)
                return e.name;
        }
        //internal error
        assert(false, myformat("undefined enum value: ", val));
    }

    static MyBox box_parse_enum(char[] s) {
        foreach (EnumItem e; items) {
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
    assert(boxParseInt("123").unbox!(int) == 123);
    assert(boxParseInt("abc").type is null);
    assert(boxParseInt("1abc").type is null);
    assert(boxParseInt("").type is null);
    //bug or feature?
    assert(boxParseInt(" 123").unbox!(int) == 123);
    assert(boxParseInt("123 ").type is null);

    assert(boxParseFloat("123.25").unbox!(float) == 123.25f);
    assert(boxParseFloat("abc").type is null);
    assert(boxParseFloat("1.0abc").type is null);
    assert(boxParseFloat("").type is null);
    //same behaviour as with int
    assert(boxParseFloat(" 123").unbox!(float) == 123f);
    assert(boxParseFloat("123 ").type is null);

    assert(boxParseBool("false").unbox!(bool) == false);
    assert(boxParseBool("yes").unbox!(bool) == true);
    assert(boxParseBool("").type is null);

    assert(boxParseVector2i("1 2").unbox!(Vector2i) == Vector2i(1, 2));
    assert(boxParseVector2i("1 foo").type is null);

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

    //----

    debug Trace.formatln("strparser.d unittest: passed.");
}
