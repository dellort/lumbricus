///Sorry about this. It wraps Tango string functions.
///Reasons:
/// - Tango API (and implementation) sucks donkeyballs
/// - if we're switching to D2, we can use the Phobos functions; and there will
///   be changes to Phobos anyway (probably)
/// - I don't feel like porting all ~150 modules using the Phobos functions
module utils.string;

import textu = tango.text.Util;
import unicode = tango.text.Unicode;
import ascii = tango.text.Ascii;
import utf = tango.text.convert.Utf;


//--- public aliases for exporting functions, which are just fine as they are
//(but often does name changes)

//yeah, "ASCII", but there seem no unicode equivalents

alias ascii.compare cmp;   //compare case insensitive, return <0, 0 or >0
alias ascii.icompare icmp; //same as cmp, case sensitive

alias unicode.toLower tolower; //return lower case version of string
alias unicode.toUpper toupper; //return upper case version of string

//NOTE: there also is unicode.isSpace and unicode.isWhitespace
//      but textu.* probably only works with text.isSpace
alias textu.isSpace iswhite; //return true if whitespace char/dchar/wchar

//cut whitespace
alias textu.trim strip;
alias textu.triml stripl;
alias textu.trimr stripr;

alias textu.splitLines splitlines;

//T[] replace(T)(T[] source, T[] match, T[] replacement)
alias textu.substitute replace;

//T[] repeat(T, U = uint)(T[] src, U count, T[] dst = null)
//in practise: char[] repeat(char[] src, int count)
alias textu.repeat repeat;

//return: -1 if not found, or the first n with text[n] == tofind
sizediff_t find(char[] text, char tofind) {
    size_t res = textu.locate(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
sizediff_t find(char[] text, char[] tofind) {
    size_t res = textu.locatePattern(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or the last n with text[n] == tofind
sizediff_t rfind(char[] text, char tofind) {
    size_t res = textu.locatePrior(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
sizediff_t rfind(char[] text, char[] tofind) {
    size_t res = textu.locatePatternPrior(text, tofind);
    return res == text.length ? -1 : res;
}

//on every spliton in text, create a new array item, and return that array
char[][] split(char[] text, char[] spliton) {
    char[][] res = textu.split(text, spliton);
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

char[] join(char[][] text, char[] joiner) {
    return textu.join(text, joiner);
}

//--- std.utf

alias utf.isValid isValidDchar;

public import tango.core.Exception : UnicodeException;

//append c to txt (encoded as utf-8)
void encode(ref char[] txt, dchar c) {
    //apparently, the string passed as first arg is only used as a buffer
    //Tango does _not_ append to it (oh Tango, you suck so much!)
    char[8] buffer; //something long enough for a dchar
    char[] data = utf.encode(buffer, c);
    txt ~= data;
}

//decode one character of the utf-8 string txt, starting at txt[idx]
//return decoded character, and write index of following character to idx
//if decoding fails, throw UnicodeException and don't change idx
dchar decode(char[] txt, ref size_t idx) {
    /+ maybe this code would be faster; but it's also a bit buggy
       as of Tango r5245, this didn't throw errors on some invalid utf-8
       the Tango dev who wrote Utf.d must be an idiot
    //apparently, Tango's decode() always starts from index 0
    uint idx2; //uint instead of size_t: Tango and Phobos are doing it wrong
    dchar res = utf.decode(txt[idx..$], idx2);
    idx += idx2;
    +/
    //instead, enjoy this horrible hack
    //it works because the runtime uses different code for utf-8 parsing (lol.)
    assert(idx < txt.length);
    dchar res;
    bool done;
    foreach (size_t i, dchar dec; txt[idx..$]) {
        if (done) {
            idx = idx + i;
            return res;
        }
        res = dec;
        done = true;
    }
    //no next character; so idx couldn't be set
    idx = txt.length;
    return res;
}

//throw UnicodeException, if txt is not valid unicode
void validate(char[] txt) {
    size_t idx;
    while (idx < txt.length) {
        decode(txt, idx);
    }
    assert(idx == txt.length); //can only fail if decode() is buggy
}

//exception-less version of validate
bool isValid(char[] txt) {
    try {
        validate(txt);
    } catch (UnicodeException e) {
        return false;
    }
    return true;
}

//return a string that has been fixed to valid utf-8 (as in validate() succeeds)
//the input string can anything
char[] sanitize(char[] txt) {
    if (isValid(txt))
        return txt;
    char[] nstr;
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
    char[] foo;
    foo ~= "huhu";
    foo ~= 0xa4;
    foo ~= 0xc3;
    assert(!isValid(foo));
    char[] v = sanitize(foo);
    assert(isValid(v));
    assert(startsWith(v, "huh")); //the last 'u' gets eaten, who knows why
}

//return length of the unicode character at txt[idx] (in bytes)
size_t stride(char[] txt, size_t idx) {
    size_t idx2 = idx;
    decode(txt, idx2);
    return idx2 - idx;
}

//decode one char; if txt.length==0, return dchar.init
dchar decode_first(char[] txt) {
    if (txt.length == 0)
        return dchar.init;
    size_t idx = 0;
    return decode(txt, idx);
}
//probably badly named; make it better
char[] utf8_get_first(char[] txt) {
    return txt.length ? txt[0..stride(txt, 0)] : "";
}

unittest {
    size_t x = 2;
    dchar x2 = decode("äöü", x);
    assert(x == 4 && x2 == 'ö');
    char[] x3;
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
char[][] split(char[] text) {
    //split(text, " ") doesn't work with multiple spaces as seperator, and it
    // obviously doesn't use iswhite()
    //note that, unlike in split(), continuous ranges of whitespaces are ignored
    char[][] ps;
    char[] cur;
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

unittest {
    assert(split(" 1b  2ghj     y3") == ["1b", "2ghj", "y3"]);
    assert(split("1 ") == ["1"]);
    assert(split(" 1") == ["1"]);
    assert(split(" 1 ") == ["1"]);
    assert(split("") == null);
    assert(split("    ") == null);
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

bool eatStart(ref char[] str, char[] prefix) {
    if (!startsWith(str, prefix))
        return false;
    str = str[prefix.length .. $];
    return true;
}

bool eatEnd(ref char[] str, char[] suffix) {
    if (!endsWith(str, suffix))
        return false;
    str = str[0 .. $ - suffix.length];
    return true;
}

//return an array of length 2 (actual return type should be char[][2])
//result[1] contains everything in txt after (and including) find
//result[0] contains the rest (especially if nothing found)
//  split2("abcd", 'c') == ["ab", "cd"]
//  split2("abcd", 'x') == ["abcd", ""]
struct Split2Result {
    char[][2] res;
    char[] opIndex(uint i) {
        return res[i];
    }
}
Split2Result split2(char[] txt, char tofind) {
    auto idx = find(txt, tofind);
    char[] before = txt[0 .. idx >= 0 ? idx : $];
    char[] after = txt[before.length .. $];
    Split2Result r;
    r.res[0] = before;
    r.res[1] = after;
    return r;
}
//hm I guess I'm a little bit tired
//like split2(), but excludes tofind
Split2Result split2_b(char[] txt, char tofind) {
    auto res = split2(txt, tofind);
    if (res[1].length) {
        assert(res[1][0] == tofind);
        res.res[1] = res.res[1][1..$];
    }
    return res;
}

unittest {
    assert(split2("abcd", 'c').res == ["ab", "cd"]);
    assert(split2_b("abcd", 'c').res == ["ab", "d"]);
    assert(split2("abcd", 'x').res == ["abcd", ""]);
    assert(split2_b("abcd", 'x').res == ["abcd", ""]);
}

import utils.misc;

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
    if (find(s, '.') >= 0) {
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

//must be possible to run at compile time
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
    //same as standard split
    if (ps.length == 1 && ps[0] == "")
        return [];
    return ps;
}

char[] ctfe_itoa(int i) {
    char[] res;
    bool neg = i < 0;
    i = neg ? -i : i;
    do {
        res = "0123456789"[i % 10] ~ res;
        i = i/10;
    } while (i > 0);
    return (neg ? "-" : "") ~ res;
}

char[] ctfe_firstupper(char[] s) {
    if (s.length == 0)
        return null;
    if (s[0] >= 'a' && s[0] <= 'z')
        return "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[s[0] - 'a'] ~ s[1..$];
    else
        return s;
}


/// Return the index of the character following the character at "index"
size_t charNext(char[] s, size_t index) {
    assert(index <= s.length);
    if (index == s.length)
        return s.length;
    return index + stride(s, index);
}
/// Return the index of the character prepending the character at "index"
size_t charPrev(char[] s, size_t index) {
    assert(index <= s.length);
    debug if (index < s.length) {
        //assert valid UTF-8 character (stride will throw an exception)
        stride(s, index);
    }
    //you just had to find the first char starting with 0b0... or 0b11...
    //but this was most simple
    foreach_reverse(size_t byteindex, dchar c; s[0..index]) {
        return byteindex;
    }
    return 0;
}

//split after delimiters and keep the delimiters as prefixes
//never adds empty strings to the result
//rest of documentation see unittest lol
char[][] splitPrefixDelimiters(char[] s, char[][] delimiters) {
    char[][] res;
    size_t last_delim = 0;
    for (;;) {
        sizediff_t next = -1;
        size_t delim_len;
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
bool isIdentifier(char[] name) {
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
char[] simpleEscape(char[] s, char[] exclude = "\\") {
    char[] res;
    //thanks to utf-8, we can treat this as ASCII if we work on ASCII only
    outer: foreach (size_t index, char d; s) {
        foreach (char e; exclude) {
            assert(e < 128, "only ASCII allowed in exclude");
            if (d is e) {
                if (res.length == 0)
                    res = s[0..index].dup;
                //escape this
                res ~= myformat("\\x{:x}{:x}", d >> 4, d & 15);
                continue outer;
            }
        }
        //not escaped
        if (res.length)
            res ~= d;
    }
    return res.length ? res : s;
}

char[] simpleUnescape(char[] s) {
    if (find(s, "\\") < 0)
        return s;

    void check(bool c) {
        if (!c)
            throwError("unescaping error");
    }

    ubyte getN(char c) {
        if (c >= '0' && c <= '9')
            return c - '0';
        if (c >= 'A' && c <= 'F')
            return c - 'A' + 10;
        if (c >= 'a' && c <= 'f')
            return c - 'a' + 10;
        check(false);
    }

    char[] res;
    for (size_t n = 0; n < s.length; n++) {
        if (s[n] == '\\') {
            //unescape, expects \xNN, N=0-9/A-F
            auto old_n = n;
            n++;
            check(s[n] == 'x' || s[n] == 'X');
            n++;
            check(n + 2 <= s.length);
            char c = (getN(s[n]) << 4) | getN(s[n+1]);
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
    char[] bla = "bla";
    assert(simpleEscape(bla).ptr is bla.ptr);
    assert(simpleUnescape(bla).ptr is bla.ptr);
}

//Tango has tango.text.Text, but didn't immediately provide what I wanted
//(it heap-allocates when replacing)

//these functions assume short strings, and they don't do any heap allocation,
//  if the (implied) free buffer space in buf is large enough

//replace "search" string in buf by myformat(fmt, ...)
void buffer_replace_fmt(ref StrBuffer buf, char[] search, char[] fmt, ...) {
    if (find(buf.get, search) < 0)
        return;
    char[40] buffer2 = void;
    char[] repl = myformat_s_fx(buffer2, fmt, _arguments, _argptr);
    buffer_replace(buf, search, repl);
}

import tsearch = tango.text.Search;

//replace "search" by "replace" in buf
void buffer_replace(ref StrBuffer buf, char[] search, char[] replace) {
    if (find(buf.get, search) < 0)
        return;
    char[40] buffer2 = void;
    auto buf2 = StrBuffer(buffer2);
    auto match = tsearch.find(search);
    foreach (token; match.tokens(buf.get, replace))
        buf2.sink(token);
    buf.reset();
    buf.sink(buf2.get);
}
