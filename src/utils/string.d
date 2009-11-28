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
int find(char[] text, char tofind) {
    size_t res = textu.locate(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
int find(char[] text, char[] tofind) {
    size_t res = textu.locatePattern(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or the last n with text[n] == tofind
int rfind(char[] text, char tofind) {
    size_t res = textu.locatePrior(text, tofind);
    return res == text.length ? -1 : res;
}

//return: -1 if not found, or first n with text[n..n+tofind.length] == tofind
int rfind(char[] text, char[] tofind) {
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
dchar decode(char[] txt, ref size_t idx) {
    //apparently, Tango's decode() always starts from index 0
    uint idx2; //uint instead of size_t: Tango and Phobos are doing it wrong
    dchar res = utf.decode(txt[idx..$], idx2);
    idx += idx2;
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

//return length of the unicode character at txt[idx] (in bytes)
size_t stride(char[] txt, size_t idx) {
    size_t idx2 = idx;
    decode(txt, idx2);
    return idx2 - idx;
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
    int idx = find(txt, tofind);
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
int charNext(char[] s, int index) {
    assert(index >= 0 && index <= s.length);
    if (index == s.length)
        return s.length;
    return index + stride(s, index);
}
/// Return the index of the character prepending the character at "index"
int charPrev(char[] s, int index) {
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
char[][] splitPrefixDelimiters(char[] s, char[][] delimiters) {
    char[][] res;
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

