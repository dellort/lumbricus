module utils.configfile;

import std.stream;
import utf = std.utf;
import str = std.string;
import std.format;
import conv = std.conv;

//returns false: conversion failed, value is unmodified
public bool parseInt(char[] s, inout int value) {
    try {
        value = conv.toInt(s);
        return true;
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
    }
    return false;
}

//cf. parseInt
public bool parseFloat(char[] s, inout float value) {
    try {
        value = conv.toFloat(s);
        return true;
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
    }
    return false;
}

//cf. parseInt
public bool parseBool(char[] s, inout bool value) {
    //strings for truth values, alternating (sorry it was 4:28 AM)
    static char[][] bool_strings = ["true", "false", "yes", "no"]; //etc.
    bool ret_value = true;
    foreach(char[] test; bool_strings) {
        if (str.icmp(test, s) == 0) {
            value = ret_value;
            return true;
        }
        ret_value = !ret_value;
    }
    return false;
}

//replacement for the buggy functions in std.ctype
//(as of DMD 0.163, the is* functions silenty fail for unicode characters)
//these replacement functions are not really "correct", just hacked together

private bool my_isprint(dchar c) {
    return (c >= 32);
}
private bool my_isspace(dchar c) {
    //return (c == 9 || c == 10 || c == 13 || c == 32);
    //consistency with str.* functions used in doWrite
    //wtf int???1111!
    return str.iswhite(c) != 0;
}
//maybe or maybe not equivalent to isalnum()
private bool my_isid(dchar c) {
    bool r = (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || (c == '_');
    //std.stdio.writefln("%s -> %s", c, r);
    return r;
}

/// This exception is thrown when an invalid name is used.
public class ConfigInvalidName : Exception {
    public char[] invalidName;

    public this(char[] offender) {
        super("Invalid config entry name: >" ~ offender ~ "<");
    }
}

public abstract class ConfigItem {
    public char[] comment;
    private char[] mName;
    private ConfigNode mParent;

    public char[] name() {
        return mName;
    }

    protected abstract void doWrite(OutputStream stream, uint level);

    //throws ConfigInvalidName on error
    //keep in sync with parser
    public static void checkName(char[] name) {
        if (!doCheckName(name))
            throw new ConfigInvalidName(name);
    }

    //note: empty names are also legal
    private static bool doCheckName(char[] name) {
        foreach (dchar c; name) {
            if (!my_isid(c)) {
                return false;
            }
        }
        return true;
    }

    private void unlink(ConfigNode parent) {
        assert(mParent == parent);
        mParent = null;
        //not sure if the name should be cleared...
        mName = "";
    }
}

/// a ConfigFile value, this is always encoded as string
public class ConfigValue : ConfigItem {
    //value can contain anything (as long as it is valid UTF-8)
    public char[] value;

    protected override void doWrite(OutputStream stream, uint level) {
        if (name.length > 0) {
            stream.writeString(" = "c);
        }
        stream.writeString("\""c);
        stream.writeString(ConfigFile.doEscape(value));
        stream.writeString("\""c);
    }

    //TODO: add properties like asInt etc.
}

/// a subtree in a ConfigFile, can contain named and unnamed values and nodes
public class ConfigNode : ConfigItem {
    //TODO: should be replaced by a linked list
    //this list is used to preserve the order
    private ConfigItem[] mItems;

    //contains only "named" items
    private ConfigItem[char[]] mNamedItems;

    //comment after last item in the node
    private char[] mEndComment;

    private void doAdd(ConfigItem item) {
        assert(item.mParent is null);
        assert(doCheckName(item.mName));

        //add only to hashtable if "named" item
        if (item.mName.length > 0) {
            assert(!(item.mName in mNamedItems));
            mNamedItems[item.mName] = item;
        }

        //very inefficient
        mItems.length = mItems.length + 1;
        mItems[mItems.length-1] = item;

        item.mParent = this;
    }

    private void doRemove(ConfigItem item) {
        char[] name = item.mName;
        item.unlink(this);

        if (name.length > 0) {
            assert(name in mNamedItems);
            mNamedItems.remove(name);
        }

        for (uint n = 0; n < mItems.length; n++) {
            if (mItems[n] == item) {
                //this length is a doubtable D feature
                mItems = mItems[0..n] ~ mItems[n+1..length];
                break;
            }
        }
    }

    /// unlink all contained config items
    public void clear() {
        //this is stupid, but will change when a linked list is used for mItems
        for (int n = mItems.length - 1; n >= 0; n--) {
            doRemove(mItems[n]);
        }
    }

    /// find an entry, can be either a ConfigNode or a ConfigValue
    /// for uncomplicated access, use functions like i.e. getStringValue()
    public ConfigItem find(char[] name) {
        if (name in mNamedItems) {
            return mNamedItems[name];
        } else {
            return null;
        }
    }

    public bool exists(char[] name) {
        return find(name) !is null;
    }

    public bool remove(char[] name) {
        return remove(find(name));
    }
    public bool remove(ConfigItem item) {
        if (item is null)
            return false;
        assert(item.mParent == this);
        doRemove(item);
        return true;
    }

    //ugly
    //(D lacks support for class variables)
    template TdoFind(T) {
        //add something... also handles "unnamed" items
        //(always return new item on empty name)
        private T doFind(char[] name, bool create) {
            ConfigItem item = find(name);
            T sub = cast(T)item;
            if (sub !is null || !create)
                return sub;
            if (item) {
                //xxx: what to do with item? just to delete it seems unfriendly
                //other possibilities:
                // - convert 'item' to text and put it into the comment of the
                //   new node (=> keep user frustration low)
                // - put ConfigNode and ConfigValue both into ConfigItem
                //   (so a Node can have a value)
                // - separate namespace between nodes and values
                doRemove(item);
            }

            //create & add
            //xxx: should invalid names always be checked, or only when
            //     attempting to create nodes with invalid names?
            checkName(name);
            sub = new T();
            sub.mName = name;
            doAdd(sub);
            return sub;
        }
    }

    /// like find(), but return null if item has the wrong type
    /// for create==true, create a new / overwrite existing values/nodes
    /// instead of returning null
    public ConfigValue findValue(char[] name, bool create = false) {
        return TdoFind!(ConfigValue).doFind(name, create);
    }
    public ConfigNode findNode(char[] name, bool create = false) {
        return TdoFind!(ConfigNode).doFind(name, create);
    }

    //difference to findNode: different default value for 2nd parameter :-)
    public ConfigNode getSubNode(char[] name, bool createIfNotExist = true) {
        return findNode(name, createIfNotExist);
    }

    /// Access a value by name, return 'default' if it doesn't exist.
    public char[] getStringValue(char[] name, char[] def = "") {
        ConfigValue value = findValue(name);
        if (value is null) {
            return def;
        } else {
            return value.value;
        }
    }

    /// Create/overwrite a string value ('name = "value"')
    public void setStringValue(char[] name, char[] value) {
        ConfigValue val = findValue(name, true);
        val.value = value;
    }

    //internally used by ConfigFile
    package ConfigValue addValue(char[] name, char[] value, char[] comment) {
        ConfigValue val = findValue(name, true);
        val.value = value;
        val.comment = comment;
        return val;
    }
    package ConfigNode addNode(char[] name, char[] comment) {
        ConfigNode node = findNode(name, true);
        node.comment = comment;
        return node;
    }

    void doWrite(OutputStream stream, uint level) {
        //always use this... on some systems, \n might not be mapped to 0xa
        char[] newline = "\x0a";
        char[] indent_str = str.repeat(" ", 4*level);

        void writeLine(char[] stuff) {
            stream.writeString(indent_str);
            stream.writeString(stuff);
            stream.writeString(str.newline);
        }

        void writeComment(char[] comment) {
            //this strip is used to cut off unneeded starting/trailing new lines
            char[][] comments = str.splitlines(str.strip(comment));

            foreach(char[] lines; comments) {
                //don't write whitespace since we reformat the file
                writeLine(str.strip(lines));
            }
        }

        if (level != 0) {
            stream.writeString(" {"c);
            stream.writeString(newline);
        }

        foreach (ConfigItem item; this) {
            writeComment(item.comment);

            stream.writeString(indent_str);

            char[] name = item.name;
            if (name.length > 0) {
                stream.writeString(name);
            }

            item.doWrite(stream, level+1);

            stream.writeString(str.newline);
        }

        writeComment(mEndComment);

        if (level != 0) {
            //this is a hack
            stream.writeString(indent_str[0..length-4]);
            stream.writeString ("}"c);
        }
    }

    //foreach(ConfigItem; ConfigNode)
    public int opApply(int delegate(inout ConfigItem) del) {
        foreach (ConfigItem item; mItems) {
            int res = del(item);
            if (res)
                return res;
        }
        return 0;
    }

    //foreach(char[], ConfigNode; ConfigNode) enumerate subnodes
    public int opApply(int delegate(inout char[], inout ConfigNode) del) {
        foreach (ConfigItem item; mItems) {
            ConfigNode n = cast(ConfigNode)item;
            if (n !is null) {
                char[] tmp = n.name;
                int res = del(tmp, n);
                if (res)
                    return res;
            }
        }
        return 0;
    }
    
    //foreach(char[], char[]; ConfigNode) enumerate (name, value) pairs
    public int opApply(int delegate(inout char[], inout char[]) del) {
        foreach (ConfigItem item; mItems) {
            ConfigValue v = cast(ConfigValue)item;
            if (v !is null) {
                char[] tmp = v.name;
                int res = del(tmp, v.value);
                if (res)
                    return res;
            }
        }
        return 0;
    }

    //foreach(char[]; ConfigNode) enumerate names
    public int opApply(int delegate(inout char[]) del) {
        foreach (ConfigItem item; mItems) {
            char[] tmp = item.name;
            int res = del(tmp);
            if (res)
                return res;
        }
        return 0;
    }

    public int getIntValue(char[] name, int def = 0) {
        int res = def;
        parseInt(getStringValue(name), res);
        return res;
    }
    public void setIntValue(char[] name, int value) {
        setStringValue(name, str.toString(value));
    }

    public bool getBoolValue(char[] name, bool def = false) {
        bool res = def;
        parseBool(getStringValue(name), res);
        return res;
    }
    public void setBoolValue(char[] name, bool value) {
        setStringValue(name, value ? "true" : "false");
    }
    
    public float getFloatValue(char[] name, float def = float.nan) {
        float res = def;
        parseFloat(getStringValue(name), res);
        return res;
    }
    public void setFloatValue(char[] name, float value) {
        setStringValue(name, str.toString(value));
    }
}

private class ConfigFatalError : Exception {
    int type;
    this(int type) {
        super("");
        this.type = type;
    }
}

//stupid phobos dooesn't have this yet
char[] formatfx(TypeInfo[] arguments, void* argptr) {
    char[] res;

    void myputc(dchar c) {
        res.length = res.length + 1;
        res[res.length-1] = c;
    }

    doFormat(&myputc, arguments, argptr);

    return res;
}

/// Used to manage config files. See docs/*.grm for the used format.
public class ConfigFile {
    private char[] mFilename;
    private char[] mData;
    private Position mPos;          //current pos in data
    private Position mNextPos;      //position of following char
    private dchar mCurChar;         //char at mPos
    private ConfigNode mRootnode;
    private bool[uint] mUTFErrors;
    private uint mErrorCount;
    private void delegate(char[]) mErrorOut;
    private bool mHasEncodingErrors;

    public ConfigNode rootnode() {
        return mRootnode;
    }

    /// Read the config file from 'source' and output any errors to 'errors'
    /// 'filename' is used only for error messages
    public this(char[] source, char[] filename, void delegate(char[]) reportError) {
        loadFrom(source, filename, reportError);
    }

    public this(Stream source, char[] filename, void delegate(char[]) reportError) {
        loadFrom(source, filename, reportError);
    }

    /// do the same like the constructor
    /// use hasErrors() to check if there were any errors
    public void loadFrom(char[] source, char[] filename, void delegate(char[]) reportError) {
        mData = source;
        mErrorOut = reportError;
        mFilename = filename;
        doParse();
    }

    /// do the same like the constructor
    public void loadFrom(Stream source, char[] filename, void delegate(char[]) reportError) {
        source.seekSet(0);
        mData = source.readString(source.size());
        mErrorOut = reportError;
        mFilename = filename;
        doParse();
    }

    private struct BOMItem {
        char[] code; char[] name;
    }
    private static const char[] cUtf8Bom = [0xEF, 0xBB, 0xBF];
    private static const BOMItem[] cBOMs = [
        {cUtf8Bom, null}, //UTF-8, special handling
        //needed for sophisticated error handling messages, bloaha
        {[0xFF, 0xFE, 0x00, 0x00], "UTF-32 little endian"},
        {[0x00, 0x00, 0xFE, 0xFF], "UTF-32 big endian"},
        {[0xFF, 0xFE], "UTF-16 little endian"},
        {[0xFE, 0xFF], "UTF-16 big endian"},
    ];

    private void init_parser() {
        mNextPos = Position.init;
        mErrorCount = 0;
        mHasEncodingErrors = false;
        mUTFErrors = mUTFErrors.init;

        //if there's one, skip the unicode BOM
        foreach (BOMItem bom; cBOMs) {
            if (bom.code.length <= mData.length) {
                if (mData[0..bom.code.length] == bom.code) {
                    //if UTF-8, skip BOM and continue
                    if (bom.name == null) {
                        mNextPos.bytePos = bom.code.length;
                        break;
                    }

                    reportError(true, "file encoding is >%s<, unsupported",
                        bom.name);
                    return;
                }
            }
        }

        //read first char, inits mPos and mCurChar
        next();
    }

    //(just a test function)
    /*public void schnitzel() {
        Token token;
        char[] str;
        char[] comm;
        init_parser();
        while (nextToken(token, str, comm)) {
            mErrorOut.writefln("token %s with >%s<, comm=>%s<", cast(int)token, str, comm);
            if (token == Token.EOF)
                break;
        }
        mErrorOut.writefln("no more tokens");
    }*/

    private struct Position {
        uint bytePos = 0;
        uint charPos = 0;
        uint line = 1;
        uint column = 0;
    }

    private static final const dchar EOF = 0xFFFF;
    private static final uint cMaxErrors = 100;

    //fatal==false: continue parsing allthough config file is invalid
    //fatal==true: parsing won't be continued (abort by throwing an exception)
    private void reportError(bool fatal, ...) {
        mErrorCount++;

        //xxx: add possibility to translate error messages
        mErrorOut(str.format("ConfigFile, error in %s(%s,%s): ", mFilename,
            mPos.line, mPos.column));
        //scary D varargs!
        mErrorOut(formatfx(_arguments, _argptr));
        mErrorOut("\n");

        //abuse exception handling to abort parsing
        if (fatal) {
            mErrorOut(str.format("ConfigFile, %s: fatal error, aborting",
                mFilename));
            throw new ConfigFatalError(2);
        } else if (mErrorCount > cMaxErrors) {
            mErrorOut(str.format("ConfigFile, %s: too many errors, aborting",
                mFilename));
            throw new ConfigFatalError(1);
        }
    }

    //d'oh, completely unportable!
    //this isn't in std.ctype, but maybe there's a reason for that...
    private static bool my_isnewline(dchar c) {
         return (c == '\n');
    }

    //read the next char and advance curpos to the next one
    //returns EOF on file end
    //handles UTF8 encoding issues
    private void next() {
        //mNextPos becomes mPos, the current pos
        mPos = mNextPos;

        if (mNextPos.bytePos >= mData.length) {
            mCurChar = EOF;
            return;
        }

        dchar result;

        try {

            //xxx: officially, it's an "error" to rely on array bounds checking
            //this code will only work correctly in "debug" mode
            //(ie. if mData ends with a partial UTF8 sequence, decode will read
            // beyond the array and fsck up everything)
            result = utf.decode(mData, mNextPos.bytePos);

        } catch (utf.UtfException utfe) {

            //use a hashtable to record positions in the file, where encoding-
            //errors are. this is stupid but simple. next() now can be called
            //several times at the same positions without producing the same
            //errors again

            if (!(mNextPos.bytePos in mUTFErrors)) {
                mUTFErrors[mNextPos.bytePos] = true;
            }

            //skip until there's a valid UTF sequence again

            dchar offender = mData[mNextPos.bytePos];
            mNextPos.bytePos++;
            while (mNextPos.bytePos < mData.length) {
                uint adv = utf.stride(mData, mNextPos.bytePos);
                if (adv != 0xFF)
                    break;
                mNextPos.bytePos++;
            }

            result = '?';
            mHasEncodingErrors = true;

            reportError(false, "invalid UTF-8 sequence");
        }

        //update line/col position according to char type
        if (my_isnewline(result)) {
            mNextPos.column = 0;
            mNextPos.line++;
        }

        mNextPos.charPos++;
        mNextPos.column++;

        mCurChar = result;
    }

    alias mCurChar curChar;

    private Position curpos() {
        return mPos;
    }
    //step back to a specific position
    //for reset(curpos), mCurChar will stay the same
    private void reset(Position pos) {
        mNextPos = pos;
        next();
    }

    private char[] copyOut(Position p1, Position p2) {
        char[] slice = mData[p1.bytePos .. p2.bytePos];
        if (!mHasEncodingErrors) {
            return slice;
        } else {
            //check string and replace characters that produce encoding errors
            //due to the copying and the exception handling this is S.L.O.W.
            char[] args = slice.dup;
            for (uint i = 0; i < args.length; i++) {
                try {
                    //(decode modifies i)
                    utf.decode(args, i);
                    i--; //set back to first next char
                } catch (utf.UtfException e) {
                    args[i] = '?';
                }
            }
            utf.validate(args);
            return args;
        }
    }

    private enum Token {
        ERROR,  //?
        EOF,
        ID,     //known as "Id" in syntax definition
        VALUE,  //a value, "String" in "<Node>"
        ASSIGN, //'='
        OPEN,   //'{'
        CLOSE   //'}'
    }

    //str contains an identifier/value for Token.ID/Token.VALUE (else "")
    //comm contains the skipped whitespace between the previous and this token
    private bool nextToken(out Token token, out char[] str, out char[] comm) {
        Position start = curpos;
        Position nwstart; //position of first char after whitespace

        str = "";

        //skip whitespace
        for (;;) {
            if (my_isspace(curChar)) {
                next();
            } else if (curChar == '#') {
                //a comment; skip anything until the end of the line
                do {
                    next();
                } while (curChar != EOF && !my_isnewline(curChar));
            } else if (curChar == '/') {
                Position cur = curpos;
                next();
                if (curChar != '/') {
                    //go back, let the rest of the function parse the "/"
                    reset(cur);
                    break;
                } else {
                    //C99/C++/Java/C#/D style comment - skip it
                    do {
                        next();
                    } while (curChar != EOF && !my_isnewline(curChar));
                }
            } else {
                break;
            }
        }

        comm = copyOut(start, curpos);

        switch (curChar) {
            case EOF: token = Token.EOF; break;
            case '{': token = Token.OPEN; break;
            case '}': token = Token.CLOSE; break;
            case '=': token = Token.ASSIGN; break;
            default: token = Token.ERROR;
        }

        if (token != Token.ERROR) {
            next();
            return true;
        }

        bool is_value = false;
        const final char cValueOpen = '"';
        const final char cValueClose = '"';

        if (curChar == cValueOpen) {
            //parse a VALUE; VALUEs must end with another '"'
            //if there's no closing '"', then the user is out of luck
            //(this needs a better error handling rule)
            next();
            is_value = true;
        }

        //if not a value: any chars that come now must form ID tokens
        //(the error handling relies on it)

        char[] curstr = "";
        Position strstart = curpos;
        for (;;) {
            if (is_value) {
                //special handling for VALUEs
                if (curChar == '\\') {
                    char[] stuff = copyOut(strstart, curpos);
                    next();
                    char escape = parseEscape();
                    //looks inefficient
                    curstr = curstr ~ stuff ~ escape;
                    strstart = curpos;
                    continue;
                } else if (curChar == cValueClose) {
                    break;
                } else {
                    //any "real" control character should be encoded as escape
                    //I hope this check makes sense
                    if (!my_isprint(curChar) && !my_isspace(curChar)) {
                        reportError(false,
                            "unescaped control character in value");
                    }
                }
            } else {
                //special handling for IDs
                if (!my_isid(curChar)) {
                    break;
                }
            }

            if (curChar == EOF)
                break;

            next();
        }

        curstr = curstr ~ copyOut(strstart, curpos);

        if (is_value) {
            if (curChar != cValueClose) {
                reportError(true, "no closing >\"< for a value");
            } else {
                next();
            }
        }

        if (!is_value && curstr.length == 0) {
            reportError(false, "identifier expected");
            curstr = "<error>";
            //make "progress", better than showing the error again all the time
            next();
        }

        str = curstr;
        token = is_value ? Token.VALUE : Token.ID;

        return true;
    }

    //arrrg I want initializeable associative arrays
    private struct EscapeItem {char escape; char produce;}
    private static const EscapeItem cSimpleEscapes[] = [
        {'\\', '\\'}, {'\'', '\''}, {'\"', '\"'}, {'?', '?'},
        {'n', '\n'}, {'t', '\t'}, {'v', '\v'}, {'b', '\b'}, {'f', '\f'},
        {'a', '\a'},
        {'0', '\0'},
    ];

    //parse an escape sequence, curpos is behind the leading backslash
    private char parseEscape() {
        uint digits;

        foreach (EscapeItem item; cSimpleEscapes) {
            if (item.escape == curChar) {
                next();
                return item.produce;
            }
        }

        digits = 0;
        if (curChar == 'x') {
            digits = 2;
        } else if (curChar == 'u') {
            digits = 4;
        } else if (curChar == 'U') {
            digits = 8;
        }

        if (digits > 0) {
            next();
            //parse 'digits' hex numbers
            dchar value = 0;
            //bool printed_error = false;
            for (uint i = 0; i < digits; i++) {
                uint val = 0;
                if (curChar >= '0' && curChar <= '9') {
                    val = curChar - '0';
                } else if (curChar >= 'A' && curChar <= 'F') {
                    val = curChar - 'A' + 10;
                } else if (curChar >= 'a' && curChar <= 'f') {
                    val = curChar - 'a' + 10;
                } else {
                    //if (!printed_error) {
                        reportError(false, "expected %s hex digits", digits-i);
                        //printed_error = true;
                        break;
                    //}
                }
                next();
                value = (value << 8) | val;
            }
            return value;
        } else if (curChar == '&') {
            //and we maybe never will
            reportError(false,
                "sorry, I don't support named character entities");
        } else if (curChar >= '0' && curChar < '8') {
            reportError(false,
                "sorry, I don't support octal numbers (use \\x)");
        } else {
            reportError(false, "unknown escape sequence");
        }

        return '?';
    }

    //return an escaped string
    //xxx: definitely needs more work, it's S.L.O.W.
    public static char[] doEscape(char[] s) {
        char[] output;

        //preallocate data; in the best case (no characters to escape), no
        //further allocations are necessary
        //(at least should work with DMD)
        output.length = s.length;
        output.length = 0;

        charLoop: foreach(dchar c; s) {
            //try "simple escapes"
            foreach (EscapeItem item; cSimpleEscapes) {
                if (item.produce == c) {
                    output ~= '\\';
                    output ~= item.escape;
                    continue charLoop;
                }
            }

            //convert non-printable chars, and any non-space whitespace
            if (!my_isprint(c) || (my_isspace(c) && c != ' ')) {
                output ~= '\\';

                //encode it as hex; ugly but... ugly
                uint digits = 1;
                char marker = 'x';
                if (c > 0xff) {
                    digits = 2; marker = 'u';
                } else if (c > 0xffff) {
                    digits = 4; marker = 'U';
                }

                output ~= str.format("%s%*x", marker, cast(int)digits, c);
            } else {
                utf.encode(output, c);
            }
        }
        return output;
    }

    private void parseNode(ConfigNode node, bool toplevel) {
        Token token;
        char[] str;
        char[] comm;
        char[] waste;
        char[] id;

        for (;;) {
            nextToken(token, str, comm);
            id = "";

            if (token == Token.VALUE) {
                //a VALUE without an ID
                node.addValue("", str, comm);
                continue;
            }

            if (token == Token.EOF) {
                if (!toplevel) {
                    reportError(false, "missing '}'");
                }
                break;
            }

            if (token == Token.CLOSE) {
                if (toplevel) {
                    reportError(false, "too many '}'");
                }
                break;
            }

            if (token == Token.ID) {
                id = str;
                if (node.exists(id)) {
                    reportError(false, "item with this name exists already");
                }

                nextToken(token, str, waste);

                if (token == Token.ASSIGN) {
                    //ID = "VALUE"
                    Position p = curpos;
                    nextToken(token, str, waste);
                    if (token == Token.ID) {
                        reportError(false,
                            "value expected (did you forget the \"\"?)");
                        //if he really forgot the "", don't go back
                        //reset(p); //go back
                    } else if (token != Token.VALUE) {
                        reportError(false, "atfer '=': value expected");
                        reset(p);
                    }
                    node.addValue(id, str, comm);

                    continue;
                }
            }

            if (token == Token.OPEN) {
                ConfigNode newnode = node.addNode(id, comm);
                parseNode(newnode, false);

                continue;
            }

            //invalid tokens, report hopefully helpful error messages
            if (id.length != 0) {
                reportError(false, "identifier is expected to be followed by"
                    " '=' or '{'");
            } else if (token == Token.ASSIGN) {
                reportError(false, "unexpected '=', no identifier before it");
            } else {
                reportError(false, "unexpected token");
            }
        }

        //foo
        node.mEndComment = comm;
    }

    private void doParse() {
        clear();

        try {
            init_parser();
            char[] waste, morewaste;

            Token token;
            parseNode(mRootnode, true);
            nextToken(token, waste, morewaste);
            if (token != Token.EOF) {
                //moan about unparsed stuff
                reportError(false, "aborting here (nothing more to parse, but "
                    "there is still text)");
            }
        } catch (ConfigFatalError e) {
            //Exception is only used to exit parser function class hierachy
        }
    }

    public bool hasErrors() {
        return mErrorCount != 0;
    }

    public void clear() {
        if (mRootnode !is null) {
            mRootnode.unlink(null);
        }
        mRootnode = new ConfigNode();
    }

    public void writeFile(OutputStream stream) {
        if (rootnode !is null) {
            stream.writeString(cUtf8Bom);
            rootnode.doWrite(stream, 0);
        }
    }
}