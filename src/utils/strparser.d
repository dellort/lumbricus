//Contains string->type parsers for all value types available in this directory
//(including native types).
module utils.strparser;
import utils.mybox;
import conv = tango.util.Convert;
import tango.text.convert.Float : toFloat;
import tango.core.Exception;
import str = stdx.string;
import utils.misc : myformat;

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

debug import tango.io.Stdout;

unittest {
    assert(boxParseInt("123").unbox!(int) == 123);
    assert(boxParseInt("abc").type is null);
    assert(boxParseInt("1abc").type is null);
    assert(boxParseInt("").type is null);

    assert(boxParseFloat("123.25").unbox!(float) == 123.25f);
    assert(boxParseFloat("abc").type is null);
    assert(boxParseFloat("1.0abc").type is null);
    assert(boxParseFloat("").type is null);

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

    debug Stdout.formatln("strparser.d unittest: passed.");
}
