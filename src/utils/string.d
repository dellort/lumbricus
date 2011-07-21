///Sorry about this. It wraps Tango string functions.
///Reasons:
/// - Tango API (and implementation) sucks donkeyballs
/// - if we're switching to D2, we can use the Phobos functions; and there will
///   be changes to Phobos anyway (probably)
/// - I don't feel like porting all ~150 modules using the Phobos functions
module utils.string;

import pstr = std.string;
import parray = std.array;
import palgo = std.algorithm;
import putf = std.utf;
import prange = std.range;
import pascii = std.ascii;

import std.uni;

//--- public aliases for exporting functions, which are just fine as they are
//(but often does name changes)

//yeah, "ASCII", but there seem no unicode equivalents

alias palgo.cmp cmp;   //compare case insensitive, return <0, 0 or >0
alias parray.icmp icmp; //same as cmp, case sensitive

alias pstr.toLower tolower; //return lower case version of string
alias pstr.toUpper toupper; //return upper case version of string

//NOTE: there also is unicode.isSpace and unicode.isWhitespace
//      but textu.* probably only works with text.isSpace
alias pascii.isWhite iswhite; //return true if whitespace char/dchar/wchar

//cut whitespace
alias pstr.strip strip;
alias pstr.stripLeft stripl;
alias pstr.stripRight stripr;

alias pstr.splitLines splitlines;

//T[] replace(T)(T[] source, T[] match, T[] replacement)
alias parray.replace replace;

//T[] repeat(T, U = uint)(T[] src, U count, T[] dst = null)
//in practise: string repeat(string src, int count)
alias parray.replicate repeat;

unittest {
    assert(repeat("ab", 3) == "ababab");
}

//return: -1 if not found, or the first n with text[n] == tofind
int find(cstring text, char tofind) {
    return pstr.indexOf(text, tofind);
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
int find(cstring text, cstring tofind) {
    return pstr.indexOf(text, tofind);
}

//return: -1 if not found, or the last n with text[n] == tofind
int rfind(cstring text, char tofind) {
    return pstr.lastIndexOf(text, tofind);
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
int rfind(cstring text, cstring tofind) {
    return pstr.lastIndexOf(text, tofind);
}

//on every spliton in text, create a new array item, and return that array
string[] split(string text, const(char)[] spliton) {
    //XXXTANGO: check whether it's correct
    auto res = parray.split(text, spliton);
    //behaviour different Phobos <-> Tango:
    //split("", ",") returns
    // in Tango: [""]
    // in Phobos: []
    //I think Phobos behaviour is more useful (less special cases in user code)
    if (res.length == 1 && res[0] == "")
        return null;
    return res;
}
//XXXTANGO
const(char)[][] split(const(char)[] text, const(char)[] spliton) {
    //XXXTANGO: check whether it's correct
    auto res = parray.split(text, spliton);
    //behaviour different Phobos <-> Tango:
    //split("", ",") returns
    // in Tango: [""]
    // in Phobos: []
    //I think Phobos behaviour is more useful (less special cases in user code)
    if (res.length == 1 && res[0] == "")
        return null;
    return res;
}


unittest {
    assert(split("a,b", ",") == ["a"[], "b"]);
    assert(split("a,", ",") == ["a"[], ""]);
    assert(split("a", ",") == ["a"[]]);
    assert(split("", ",") == null);
}

string join(cstring[] text, cstring joiner) {
    return parray.join(cast(string[])text, cast(string)joiner);
}

//--- std.utf

alias putf.isValidDchar isValidDchar;

alias putf.UtfException UnicodeException;

//append c to txt (encoded as utf-8)
void encode(ref string txt, dchar c) {
    //apparently, the string passed as first arg is only used as a buffer
    //Tango does _not_ append to it (oh Tango, you suck so much!)
    char[4] buffer;
    auto len = putf.encode(buffer, c);
    txt ~= buffer[0..len];
}

//decode one character of the utf-8 string txt, starting at txt[idx]
//return decoded character, and write index of following character to idx
//if decoding fails, throw UnicodeException and don't change idx
dchar decode(cstring txt, ref size_t idx) {
    return putf.decode(txt, idx);
}

//throw UnicodeException, if txt is not valid unicode
void validate(cstring txt) {
    size_t idx;
    while (idx < txt.length) {
        decode(txt, idx);
    }
    assert(idx == txt.length); //can only fail if decode() is buggy
}

//exception-less version of validate
bool isValid(cstring txt) {
    try {
        validate(txt);
    } catch (UnicodeException e) {
        return false;
    }
    return true;
}

//return a string that has been fixed to valid utf-8 (as in validate() succeeds)
//the input string can anything
string sanitize(string txt) {
    if (isValid(txt))
        return txt;
    string nstr;
    size_t idx = 0;
    while (idx < txt.length) {
        dchar cur = '?';
        try {
            cur = decode(txt, idx);
        } catch (UnicodeException e) {
            //could do anything here; but at least has to make some progress
            idx += 1;
        }
        encode(nstr, cur);
    }
    return nstr;
}

unittest {
    string foo;
    foo ~= "huhu";
    foo ~= 0xa4;
    foo ~= 0xc3;
    assert(!isValid(foo));
    string v = sanitize(foo);
    assert(isValid(v));
    assert(startsWith(v, "huh")); //the last 'u' gets eaten, who knows why
}

//return length of the unicode character at txt[idx] (in bytes)
size_t stride(cstring txt, size_t idx) {
    size_t idx2 = idx;
    decode(txt, idx2);
    return idx2 - idx;
}

//decode one char; if txt.length==0, return dchar.init
dchar decode_first(cstring txt) {
    if (txt.length == 0)
        return dchar.init;
    size_t idx = 0;
    return decode(txt, idx);
}
//probably badly named; make it better
cstring utf8_get_first(cstring txt) {
    return txt.length ? txt[0..stride(txt, 0)] : "";
}

unittest {
    size_t x = 2;
    dchar x2 = decode("äöü", x);
    assert(x == 4 && x2 == 'ö');
    string x3;
    encode(x3, 'ä');
    encode(x3, 'ö');
    assert(x3 == "äö");
    assert(stride("ä", 0) == 2);
    char[2] x4;
    x4[0] = 195;
    x4[1] = 39;
    bool exc = false;
    try {
        validate(x4);
    } catch (UnicodeException e) {
        exc = true;
    }
    assert(exc);
}

//--- my own functions

//split on iswhite() (see unittest)
string[] split(string text) {
    //split(text, " ") doesn't work with multiple spaces as seperator, and it
    // obviously doesn't use iswhite()
    //note that, unlike in split(), continuous ranges of whitespaces are ignored
    string[] ps;
    string cur;
    void commit() {
        if (!cur.length)
            return;
        ps ~= cur;
        cur = "";
    }
    foreach (dchar c; text) {
        if (iswhite(c)) {
            commit();
        } else {
            cur ~= c;
        }
    }
    commit();
    return ps;
}

//XXXTANGO
const(char[])[] split(cstring text) {
    return cast(const(char[])[])split(cast(string)text);
}

unittest {
    assert(split(" 1b  2ghj     y3") == ["1b", "2ghj", "y3"]);
    assert(split("1 ") == ["1"]);
    assert(split(" 1") == ["1"]);
    assert(split(" 1 ") == ["1"]);
    assert(split("") == null);
    assert(split("    ") == null);
}

bool startsWith(cstring str, cstring prefix) {
    if (str.length < prefix.length)
        return false;
    return str[0..prefix.length] == prefix;
}

bool endsWith(cstring str, cstring suffix) {
    if (str.length < suffix.length)
        return false;
    return str[$-suffix.length..$] == suffix;
}

bool eatStart(ref const(char)[] str, cstring prefix) {
    if (!startsWith(str, prefix))
        return false;
    str = str[prefix.length .. $];
    return true;
}

bool eatEnd(ref const(char)[] str, cstring suffix) {
    if (!endsWith(str, suffix))
        return false;
    str = str[0 .. $ - suffix.length];
    return true;
}

//XXXTANGO dunno
bool eatStart(ref string str, cstring prefix) {
    if (!startsWith(str, prefix))
        return false;
    str = str[prefix.length .. $];
    return true;
}
bool eatEnd(ref string str, cstring suffix) {
    if (!endsWith(str, suffix))
        return false;
    str = str[0 .. $ - suffix.length];
    return true;
}

//return an array of length 2 (actual return type should be string[2])
//result[1] contains everything in txt after (and including) find
//result[0] contains the rest (especially if nothing found)
//  split2("abcd", 'c') == ["ab", "cd"]
//  split2("abcd", 'x') == ["abcd", ""]
const(char)[][2] split2(const(char)[] txt, char tofind) {
    int idx = find(txt, tofind);
    auto before = txt[0 .. idx >= 0 ? idx : $];
    auto after = txt[before.length .. $];
    return [before, after];
}
//hm I guess I'm a little bit tired
//like split2(), but excludes tofind
const(char)[][2] split2_b(const(char)[] txt, char tofind) {
    auto res = split2(txt, tofind);
    if (res[1].length) {
        assert(res[1][0] == tofind);
        res[1] = res[1][1..$];
    }
    return res;
}

unittest {
    assert(split2("abcd", 'c') == ["ab", "cd"]);
    assert(split2_b("abcd", 'c') == ["ab", "d"]);
    assert(split2("abcd", 'x') == ["abcd", ""]);
    assert(split2_b("abcd", 'x') == ["abcd", ""]);
}

import utils.misc;

/// number of bytes to a string like "number XX", where XX is "B", "KB" etc.
string sizeToHuman(long bytes) {
    char[40] buffer;
    return cast(string)sizeToHuman(bytes, buffer).idup;
}

/// buffer = if long enough, use this instead of allocating memory
cstring sizeToHuman(long bytes, char[] buffer) {
    enum string[] cSizes = ["B", "KB", "MB", "GB"];
    int n;
    long x;
    x = 1;
    while (bytes >= x*1024 && n < cSizes.length-1) {
        x = x*1024;
        n++;
    }
    char[80] buffer2 = void;
    char[] s = myformat_s(buffer2, "%.3f", 1.0*bytes/x);
    //strip ugly trailing zeros (replace with a better way if you know one)
    if (find(s, '.') >= 0) {
        while (s[$-1] == '0')
            s = s[0..$-1];
        if (endsWith(s, "."))
            s = s[0..$-1];
    }
    return myformat_s(buffer, "%s %s", s, cSizes[n]);
}

unittest {
    assert(sizeToHuman(0) == "0 B");
    assert(sizeToHuman(1023) == "1023 B");
    assert(sizeToHuman(1024) == "1 KB");
    assert(sizeToHuman((1024+512)*1024) == "1.5 MB");
}

//must be possible to run at compile time
string[] ctfe_split(string s, char sep) {
    string[] ps;
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
    //same as standard split
    if (ps.length == 1 && ps[0] == "")
        return [];
    return ps;
}

string ctfe_itoa(int i) {
    string res;
    bool neg = i < 0;
    i = neg ? -i : i;
    do {
        res = "0123456789"[i % 10] ~ res;
        i = i/10;
    } while (i > 0);
    return (neg ? "-" : "") ~ res;
}

string ctfe_firstupper(string s) {
    if (s.length == 0)
        return null;
    if (s[0] >= 'a' && s[0] <= 'z')
        return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[s[0] - 'a'] ~ s[1..$];
    else
        return s;
}


/// Return the index of the character following the character at "index"
int charNext(cstring s, int index) {
    assert(index >= 0 && index <= s.length);
    if (index == s.length)
        return s.length;
    return index + stride(s, index);
}
/// Return the index of the character prepending the character at "index"
int charPrev(cstring s, int index) {
    assert(index >= 0 && index <= s.length);
    debug if (index < s.length) {
        //assert valid UTF-8 character (stride will throw an exception)
        stride(s, index);
    }
    //you just had to find the first char starting with 0b0... or 0b11...
    //but this was most simple
    foreach_reverse(int byteindex, dchar c; s[0..index]) {
        return byteindex;
    }
    return 0;
}

//split after delimiters and keep the delimiters as prefixes
//never adds empty strings to the result
//rest of documentation see unittest lol
string[] splitPrefixDelimiters(string s, string[] delimiters) {
    string[] res;
    int last_delim = 0;
    for (;;) {
        int next = -1;
        int delim_len;
        foreach (del; delimiters) {
            auto v = find(s[last_delim..$], del);
            if (v >= 0 && (next < 0 || v <= next)) {
                next = v;
                delim_len = del.length;
            }
        }
        if (next < 0)
            break;
        next += last_delim;
        last_delim = delim_len;
        auto pre = s[0..next];
        if (pre.length)
            res ~= pre;
        s = s[next..$];
    }
    if (s.length)
        res ~= s;
    return res;
}

unittest {
    assert(splitPrefixDelimiters("abc#de#fghi", ["#"])
        == ["abc", "#de", "#fghi"]);
    assert(splitPrefixDelimiters("##abc##", ["#"]) == ["#", "#abc", "#", "#"]);
    assert(splitPrefixDelimiters("abc#de,fg,#", ["#", ","])
        == ["abc", "#de", ",fg", ",", "#"]);
    static assert(ctfe_firstupper("testing") == "Testing");
}

//check if name is a valid identifier
//  (defined as "[A-Za-z_][A-Za-z0-9_]*")
//this is stricter than D's identifier rules, but should work with all languages
bool isIdentifier(string name) {
    bool isid(char c, bool first = false) {
        return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
            || (!first && c >= '0' && c <= '9') || (c == '_');
    }
    if (name.length == 0 || !isid(name[0], true)) {
        return false;
    }
    foreach (ref char c; name[1..$]) {
        if (!isid(c)) {
            return false;
        }
    }
    return true;
}

//simple escaping (the one in configfile.d sucks)
//care is taken not to allocate memory if nothing is [un]escaped
//characters in exclude are escaped (they all must be ASCII)
//NOTE: Tango has unescape() somewhere, but no escape()
string simpleEscape(string s, string exclude = "\\") {
    string res;
    //thanks to utf-8, we can treat this as ASCII if we work on ASCII only
    outer: foreach (size_t index, char d; s) {
        foreach (char e; exclude) {
            assert(e < 128, "only ASCII allowed in exclude");
            if (d is e) {
                if (res.length == 0)
                    res = s[0..index].idup;
                //escape this
                res ~= myformat("\\x%x%x", d >> 4, d & 15);
                continue outer;
            }
        }
        //not escaped
        if (res.length)
            res ~= d;
    }
    return res.length ? res : s;
}

string simpleUnescape(string s) {
    if (find(s, "\\") < 0)
        return s;

    void check(bool c) {
        if (!c)
            throwError("unescaping error");
    }

    ubyte getN(char c) {
        if (c >= '0' && c <= '9')
            return cast(ubyte)(c - '0');
        if (c >= 'A' && c <= 'F')
            return cast(ubyte)(c - 'A' + 10);
        if (c >= 'a' && c <= 'f')
            return cast(ubyte)(c - 'a' + 10);
        check(false);
        return 0; //make dmd happy
    }

    string res;
    for (size_t n = 0; n < s.length; n++) {
        if (s[n] == '\\') {
            //unescape, expects \xNN, N=0-9/A-F
            auto old_n = n;
            n++;
            check(s[n] == 'x' || s[n] == 'X');
            n++;
            check(n + 2 <= s.length);
            char c = cast(char)((getN(s[n]) << 4) | getN(s[n+1]));
            n += 2;
            res ~= c;
            n -= 1;  //compensate for n++
        } else {
            res ~= s[n];
        }
    }
    return res;
}

unittest {
    assert(simpleEscape("aöiäu:z", "iu:") == r"aö\x69ä\x75\x3az");
    assert(simpleUnescape(r"aö\x69ä\x75\x3az") == "aöiäu:z");
    string bla = "bla";
    assert(simpleEscape(bla).ptr is bla.ptr);
    assert(simpleUnescape(bla).ptr is bla.ptr);
}

//Tango has tango.text.Text, but didn't immediately provide what I wanted
//(it heap-allocates when replacing)

//these functions assume short strings, and they don't do any heap allocation,
//  if the (implied) free buffer space in buf is large enough

//replace "search" string in buf by myformat(fmt, ...)
void buffer_replace_fmt(T...)(ref StrBuffer buf, cstring search, cstring fmt, T args) {
    if (find(buf.get, search) < 0)
        return;
    char[40] buffer2 = void;
    char[] repl = myformat_s(buffer2, fmt, args);
    buffer_replace(buf, search, repl);
}

//replace "search" by "replace" in buf
void buffer_replace(ref StrBuffer buf, cstring search, cstring replace) {
    if (find(buf.get, search) < 0)
        return;
    char[40] buffer2 = void;
    auto dest = StrBuffer(buffer2);
    auto rest = buf.get();
    while (rest.length) {
        auto pos = pstr.indexOf(rest, search);
        if (pos < 0) {
            dest.sink(rest);
            break;
        }
        dest.sink(rest[0 .. pos]); //string before search term
        rest = rest[pos + search.length .. $]; //string after search term
        dest.sink(replace); //replace search term
    }
    buf.reset();
    buf.sink(dest.get);
}

unittest {
    char[6] buffer;
    StrBuffer x = StrBuffer(buffer);
    x.sink("hurr durr murrr");
    buffer_replace(x, "ur", "dumb");
    assert(x.get() == "hdumbr ddumbr mdumbrr");
    x.reset();
    x.sink("hum");
    buffer_replace(x, "um", "bla");
    assert(x.get() == "hbla");
}
