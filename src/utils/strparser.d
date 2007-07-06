//Contains string->type parsers for all value types available in this directory
//(including native types).
module utils.strparser;
import utils.mybox;
import conv = std.conv;
import str = std.string;
import std.format : doFormat;

import utils.vector2 : Vector2, Vector2i, Vector2f;

//xxx function, should be delegate
//convention: return empty box if not parseable
alias MyBox function(char[] s) BoxParseString;

BoxParseString[TypeInfo] gBoxParsers;

MyBox stringToBoxTypeID(TypeInfo info, char[] s) {
    return gBoxParsers[info](s);
}

MyBox stringToBox(T)(char[] s) {
    return stringToBoxTypeID(typeid(T), s);
}

static this() {
    gBoxParsers[typeid(char[])] = &boxParseStr;
    gBoxParsers[typeid(int)] = &boxParseInt;
    gBoxParsers[typeid(float)] = &boxParseFloat;
    gBoxParsers[typeid(bool)] = &boxParseBool;
    gBoxParsers[typeid(Vector2i)] = &boxParseVector2i;
    gBoxParsers[typeid(Vector2f)] = &boxParseVector2f;
}

//the nop
public MyBox boxParseStr(char[] s) {
    return MyBox.Box!(char[])(s);
}

//stolen from configfile.d
public MyBox boxParseInt(char[] s) {
    try {
        return MyBox.Box!(int)(conv.toInt(s));
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
    }
    return MyBox();
}
public MyBox boxParseFloat(char[] s) {
    try {
        //as of DMD 0.163, std.conv.toFloat() parses an empty string as 0.0f
        if (s.length == 0)
            return MyBox();
        return MyBox.Box!(float)(conv.toFloat(s));
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
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
private MyBox boxParseVector(T)(char[] s, T function(char[]) convert) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        return MyBox();
    }
    try {
        Vector2!(T) pt;
        pt.x = convert(items[0]);
        pt.y = convert(items[1]);
        return MyBox.Box!(Vector2!(T))(pt);
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
    }
    return MyBox();
}
public MyBox boxParseVector2i(char[] s) {
    return boxParseVector!(int)(s, &conv.toInt);
}
public MyBox boxParseVector2f(char[] s) {
    return boxParseVector!(float)(s, &conv.toFloat);
}

debug import std.stdio;
debug import std.format;

//some horrible testcode, to be killed *g*
debug void testParse(char[] input) {
    writefln("parsing: '%s':", input);
    foreach (TypeInfo t, BoxParseString parser; gBoxParsers) {
        MyBox box = parser(input);
        if (box.type) {
            assert(t is box.type);
            writefln("  %s: '%s'", box.type.toString(), boxToString(box));
        }
    }
    std.stdio.writefln("fin.");
}

char[] boxToString(MyBox box) {
    char[] res;
    //EVIL, PURE EVIL
    //the doFormat() function expects data.ptr to be aligned like on
    //the stack
    doFormat((dchar c) {res ~= c;}, [box.type], box.data.ptr);
    return res;
}

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

    debug testParse("+123.0");
    debug testParse("1 2");
    debug testParse("1 2.0");

    debug writefln("strparser.d unittest: passed.");
}
