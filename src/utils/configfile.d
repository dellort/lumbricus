module utils.configfile;

import std.stream;
import utf = std.utf;
import str = std.string;
import std.format;
import conv = std.conv;
import utils.output : Output, StringOutput;
import utils.misc : formatfx;

//only for byte[]
import zlib = std.zlib;
import base64 = std.base64;

//xxx: desperately moved to here (where else to put it?)
import utils.vector2;
bool parseVector(char[] s, inout Vector2i value) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        return false;
    }
    int a, b;
    if (!parseInt(items[0], a) || !parseInt(items[1], b))
        return false;
    value.x = a;
    value.y = b;
    return true;
}

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
        //as of DMD 0.163, std.conv.toFloat() parses an empty string as 0.0f
        if (s.length == 0)
            return false;
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

private bool is_config_id(char[] name) {
    //xxx: doesn't parse the utf-8, that's ok depending what my_isid() does
    for (int n = 0; n < name.length; n++) {
        if (!my_isid(name[n]))
            return false;
    }
    return true;
}

/// This exception is thrown when an invalid name is used.
public class ConfigInvalidName : Exception {
    public char[] invalidName;

    public this(char[] offender) {
        super("Invalid config entry name: >" ~ offender ~ "<");
    }
}

/// a subtree in a ConfigFile, can contain named and unnamed values and nodes
public class ConfigNode {
    private {
        char[] mName;
        ConfigNode mParent;
        ConfigNode[] mItems;
        //contains only "named" items
        ConfigNode[char[]] mNamedItems;
    }

    //value can contain anything (as long as it is valid UTF-8)
    public char[] value;

    //comment before theline, which defined this node
    public char[] comment;
    //comment after last item in the node (only useful if there are subnodes)
    public char[] endComment;

    public ConfigNode clone() {
        auto r = new ConfigNode();
        r.endComment = endComment;
        r.comment = comment;
        r.value = value;
        r.mName = mName;
        r.mParent = null;
        foreach (ConfigNode item; this) {
            ConfigNode n = item.clone();
            r.doAdd(n);
        }
        return r;
    }

    public ConfigNode parent() {
        return mParent;
    }

    public char[] name() {
        return mName;
    }

    public bool hasSubNodes() {
        return !!mItems.length;
    }

    public void rename(char[] new_name) {
        ConfigNode parent = mParent;
        if (!parent)
            throw new Exception("cannot rename: no parent");
        parent.doRemove(this);
        ConfigNode conflict = parent.find(new_name);
        if (conflict) {
            conflict.resolveConflict(new_name);
        }
        mName = new_name;
        parent.doAdd(this);
    }

    private void resolveConflict(char[] conflict_name) {
        rename(conflict_name ~ "_deleted");
        assert(mName != conflict_name);
    }

    private void doAdd(ConfigNode item) {
        assert(item.mParent is null);

        //add only to hashtable if "named" item
        if (item.mName.length > 0) {
            assert(!(item.mName in mNamedItems));
            mNamedItems[item.mName] = item;
        }

        //very inefficient
        mItems.length = mItems.length + 1;
        mItems[$-1] = item;

        item.mParent = this;
    }

    private void doRemove(ConfigNode item) {
        if (!item)
            return;

        char[] name = item.mName;

        assert(item.mParent is this);
        item.mParent = null;

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
        while (mItems.length) {
            doRemove(mItems[0]);
        }
    }

    /// find an entry
    /// for uncomplicated access, use functions like i.e. getStringValue()
    public ConfigNode find(char[] name) {
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
    public bool remove(ConfigNode item) {
        if (item is null)
            return false;
        doRemove(item);
        return true;
    }

    /// Find a subnode by following a path.
    /// Path component separator is "."
    public ConfigNode getPath(char[] path, bool create = false) {
        //needed for recursion temrination :)
        if (path.length == 0) {
            return this;
        }

        int pos = str.find(path, ".");
        if (pos < 0)
            pos = path.length;

        ConfigNode sub = findNode(path[0 .. pos], create);
        if (!sub)
            return null;

        if (pos < path.length)
            pos++;
        return sub.getPath(path[pos .. $], create);
    }

    ///parse path into the config node location (create on demand) and the name
    ///of the value
    public void parsePath(char[] path, out ConfigNode node, out char[] val) {
        auto val_start = str.rfind(path, '.');
        auto pathname = path[0..(val_start >= 0 ? val_start : 0)];
        val = path[val_start+1..$];
        node = getPath(pathname, true);
    }

    public void setStringValueByPath(char[] path, char[] value) {
        ConfigNode node;
        char[] valname;
        parsePath(path, node, valname);
        node.setStringValue(valname, value);
    }

    public char[] getStringValueByPath(char[] path) {
        ConfigNode node;
        char[] valname;
        parsePath(path, node, valname);
        return node.getStringValue(valname);
    }

    //add something... also handles "unnamed" items
    //(always return new item on empty name)
    private ConfigNode doFind(char[] name, bool create) {
        ConfigNode sub = find(name);
        if (sub !is null || !create)
            return sub;

        //create & add
        sub = new ConfigNode();
        sub.mName = name;
        doAdd(sub);
        return sub;
    }

    /// like find(), but return null if item has the wrong type
    /// for create==true, create a new / overwrite existing values/nodes
    /// instead of returning null
    public ConfigNode findValue(char[] name, bool create = false) {
        return doFind(name, create);
    }
    public ConfigNode findNode(char[] name, bool create = false) {
        return doFind(name, create);
    }

    public bool hasValue(char[] name) {
        return findValue(name) !is null;
    }
    public bool hasNode(char[] name) {
        return findNode(name) !is null;
    }

    //difference to findNode: different default value for 2nd parameter :-)
    public ConfigNode getSubNode(char[] name, bool createIfNotExist = true) {
        return findNode(name, createIfNotExist);
    }

    public ConfigNode addUnnamedNode() {
        return findNode("", true);
    }

    //number of nodes and values
    int count() {
        return mItems.length;
    }

    /// Access a value by name, return 'default' if it doesn't exist.
    public char[] getStringValue(char[] name, char[] def = "") {
        auto value = findValue(name);
        if (value is null) {
            return def;
        } else {
            return value.value;
        }
    }

    /// Create/overwrite a string value ('name = "value"')
    public void setStringValue(char[] name, char[] value) {
        auto val = findValue(name, true);
        val.value = value;
    }

    //alias to getStringValue/setStringValue
    public char[] opIndex(char[] name) {
        return getStringValue(name);
    }
    public void opIndexAssign(char[] value, char[] name) {
        setStringValue(name, value);
    }

    //internally used by ConfigFile
    package ConfigNode addValue(char[] name, char[] value, char[] comment) {
        auto val = findValue(name, true);
        val.value = value;
        val.comment = comment;
        return val;
    }
    package ConfigNode addNode(char[] name, char[] comment) {
        auto node = findNode(name, true);
        node.comment = comment;
        return node;
    }

    private void doWrite(Output stream, uint level) {
        //always use this... on some systems, \n might not be mapped to 0xa
        char[] newline = "\x0a";
        const int indent = 4;
        //xxx this could produce major garbage collection thrashing when writing
        //    big files
        char[] indent_str = str.repeat(" ", indent*level);

        void writeLine(char[] stuff) {
            stream.writeString(indent_str);
            stream.writeString(stuff);
            stream.writeString(newline);
        }

        void writeComment(char[] comment) {
            //this strip is used to cut off unneeded starting/trailing new lines
            char[][] comments = str.splitlines(str.strip(comment));

            foreach(char[] lines; comments) {
                //don't write whitespace since we reformat the file
                writeLine(str.strip(lines));
            }
        }

        void writeValue(char[] v) {
            stream.writeString("\"");
            stream.writeString(ConfigFile.doEscape(v));
            stream.writeString("\"");
        }

        bool name_is_funny = !is_config_id(name);

        void writeName(bool ext) {
            if (ext || !name.length) {
                //new syntax, which allows spaces etc. in names
                stream.writeString("+ ");
                writeValue(name);
            } else {
                stream.writeString(name);
            }
        }

        //"level!=0": hack for rootnode
        if ((level != 0) && !mItems.length) {
            //a normal name=value entry
            //xxx will throw away endComment for sub-nodes which are empty
            if (name.length > 0) {
                writeName(name_is_funny);
                stream.writeString(" = ");
            }
            writeValue(value);
            return;
        }

        bool have_value = value.length != 0;

        /+
        //ah this sucks, but nothing can be done about it
        //note that the root node can't have a name either
        if (level == 0 && have_value) {
            throw new Exception("can't save root ConfigNodes that have a value");
        }
        +/

        if (level != 0) {
            if (name.length > 0 || have_value) {
                writeName(name_is_funny || have_value);
                if (have_value) {
                    stream.writeString(" ");
                    writeValue(value);
                }
                stream.writeString(" ");
            }
            stream.writeString("{");
            stream.writeString(newline);
        }

        foreach (ConfigNode item; this) {
            writeComment(item.comment);
            stream.writeString(indent_str);
            item.doWrite(stream, level+1);
            stream.writeString(newline);
        }

        writeComment(endComment);

        if (level != 0) {
            //this is a hack
            stream.writeString(indent_str[0 .. $-indent]);
            stream.writeString ("}");
        }
    }

    //foreach(ConfigNode; ConfigNode) enumerate subnodes
    public int opApply(int delegate(inout ConfigNode) del) {
        foreach (ConfigNode n; mItems) {
            int res = del(n);
            if (res)
                return res;
        }
        return 0;
    }

    //foreach(char[], ConfigNode; ConfigNode) enumerate subnodes with name
    public int opApply(int delegate(inout char[], inout ConfigNode) del) {
        foreach (ConfigNode n; mItems) {
            char[] tmp = n.name;
            int res = del(tmp, n);
            if (res)
                return res;
        }
        return 0;
    }

    //foreach(char[], char[]; ConfigNode) enumerate (name, value) pairs
    public int opApply(int delegate(inout char[], inout char[]) del) {
        foreach (ConfigNode v; mItems) {
            char[] tmp = v.name;
            int res = del(tmp, v.value);
            if (res)
                return res;
        }
        return 0;
    }

    //foreach(char[]; ConfigNode) enumerate names
    public int opApply(int delegate(inout char[]) del) {
        foreach (ConfigNode item; mItems) {
            char[] tmp = item.name;
            int res = del(tmp);
            if (res)
                return res;
        }
        return 0;
    }

    ///visit all existing (transitive) subitems, including "this"
    public void visitAllNodes(void delegate(ConfigNode item) visitor) {
        visitor(this);
        foreach (ConfigNode item; mItems) {
            visitor(item);
            item.visitAllNodes(visitor);
        }
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

    /// Parse the value as array of values.
    /// Separator is always whitespace.
    //(xxx: should be really generic, but the other accessor functions aren't
    // templated yet)
    public T[] getValueArray(T)(char[] name, T[] def = null) {
        auto v = findValue(name);
        if (!v)
            return def;
        //xxx: Phobos API decides how string is parsed
        auto array = str.split(v.value);
        auto res = new T[array.length];
        foreach (int i, char[] s; array) {
            T n;
            static if (is(T : char[])) {
                n = s;
            } else static if (is(T : int)) {
                //(one invalid value makes everything fail)
                if (!parseInt(s, n))
                    return def;
            } else static if (is(T: float)) {
                if (!parseFloat(s, n))
                    return def;
            } else {
                assert(false);
            }
            res[i] = n;
        }
        return res;
    }
    //sigh, it's all a hack etc.
    public void setValueArray(T)(char[] name, T[] v) {
        char[][] s;
        static if (is(T == char[])) {
            s = v;
        } else {
            foreach (T t; v) {
                s ~= str.toString(t);
            }
        }
        setStringValue(name, str.join(s, " "));
    }

    public void setByteArrayValue(char[] name, byte[] data,
        bool allow_compress = false)
    {
        setStringValue(name, encodeByteArray(data, allow_compress));
    }

    public byte[] getByteArrayValue(char[] name, byte[] def = null) {
        return decodeByteArray(getStringValue(name), def);
    }

    static char[] encodeByteArray(byte[] data, bool compress) {
        //
        if (!data.length)
            return "[]";
        void[] garbage1;
        if (compress) {
            auto ndata = zlib.compress(data, 9);
            assert (ndata.ptr !is data.ptr);
            garbage1 = ndata;
            data = cast(byte[])ndata;
        }
        char[] res = base64.encode(cast(char[])data);
        delete garbage1;
        return res;
    }

    static byte[] decodeByteArray(char[] input, byte[] def) {
        if (input == "[]")
            return null;
        char[] buf;
        try {
            buf = base64.decode(input);
        } catch (base64.Base64Exception e) {
            return def;
        }
        try {
            return cast(byte[])zlib.uncompress(buf);
        } catch (zlib.ZlibException e) {
            return def;
        }
    }

    //compare values in a non-strict way (i.e. not byte-exact)
    //xxx: maybe at least case insensitive, also maybe strip whitespace
    private bool doCompareValueFuzzy(char[] s1, char[] s2) {
        return s1 == s2;
    }

    /// return true if the field name contains the value isValue
    /// does fuzzy value comparision
    bool valueIs(char[] name, char[] isValue) {
        return doCompareValueFuzzy(getStringValue(name), isValue);
    }

    /// Return what to index into values to which that value equals to.
    /// does fuzzy value comparision
    //TODO: distinguish between not-set values and "wrong" values?
    public int selectValueFrom(char[] name, char[][] values, int def = -1) {
        auto vo = findValue(name);
        if (!vo)
            return def;
        char[] v = vo.value;
        foreach (int i, char[] cur; values) {
            if (doCompareValueFuzzy(cur, v))
                return i;
        }
        //not found
        return def;
    }

    //return all values from this node in an string array
    //xxx: maybe give up and implement ConfigNodes that are lists
    public char[][] getValueList() {
        char[][] res;
        foreach (char[] name, char[] value; this) {
            res ~= value;
        }
        return res;
    }

    /// Copy all items from "node" into "this", as long as no node exists with
    /// that name.
    /// node = node to be mixed in
    /// overwrite = if names exist in both this and node, use the one from node
    /// recursive = if there are two ConfigNodes in both this and node, merge
    ///    them by calling mixinNode(..., overwrite, true) on them
    public void mixinNode(ConfigNode node, bool overwrite = false,
        bool recursive = true)
    {
        if (!node)
            return;
        assert(node !is this);
        foreach (ConfigNode item; node) {
            auto item2 = find(item.name);
            auto n1 = item;
            auto n2 = item2;
            if (recursive && item2 && n1 && n2)
            {
                n1.mixinNode(n2, overwrite, true);
                continue;
            }
            if (overwrite && item2) {
                remove(item2);
                item2 = null;
            }
            if (!item2) {
                auto n = item.clone();
                doAdd(n);
            }
        }
    }

    /// Does the following:
    /// for each subnode in "this", look for the key "key"
    /// if it finds "key", look for another subnode of "this" with that value
    /// then remove the "key" and mixin that other subnode
    /// do that recursively
    public void templatetifyNodes(char[] key) {
        void resolveTemplate(ConfigNode node) {
            if (node.hasValue(key)) {
                auto mixinnode = findNode(node.getStringValue(key));
                node.remove(key);
                if (!mixinnode) {
                    //xxx: what to do?
                } else {
                    //hint: deleting the template-key hopefully prevents
                    //  recursion... at least in non-evil cases
                    resolveTemplate(mixinnode);
                    node.mixinNode(mixinnode);
                }
            }
        }

        foreach (char[] tmp, ConfigNode node; this) {
            resolveTemplate(node);
        }
    }

    public void writeFile(Output stream) {
        //xxx: add method to stream to determine if it's a file... or so
        //stream.writeString(ConfigFile.cUtf8Bom);
        doWrite(stream, 0);
    }

    public char[] writeAsString() {
        auto sout = new StringOutput;
        writeFile(sout);
        return sout.text;
    }

    //does a deep copy if the node and its subnodes
    //result is unparented
    public ConfigNode copy() {
        auto n = new ConfigNode();
        n.mixinNode(this, true);
        return n;
    }
}

private class ConfigFatalError : Exception {
    int type;
    this(int type) {
        super("");
        this.type = type;
    }
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

    private struct Position {
        size_t bytePos = 0;
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

        if (!mErrorOut)
            throw new Exception("no configfile error handler set, no detailed"
                " error messages for you.");

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
            for (size_t i = 0; i < args.length; i++) {
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
        CLOSE,  //'}'
        PLUS,   //'+'
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
                if (curChar == '/') {
                    //C99/C++/Java/C#/D style comment - skip it
                    do {
                        next();
                    } while (curChar != EOF && !my_isnewline(curChar));
                } else if (curChar == '*' || curChar == '+') {
                    //stream comment, search next "*/" or "+/"
                    //xxx maybe implement full D style /++/ comments
                    char term = curChar;
                    bool s = false;
                    do {
                        next();
                        if (curChar == '/' && s) {
                            next();
                            break;
                        }
                        s = false;
                        if (curChar == term) {
                            s = true;
                        }
                    } while (curChar != EOF);
                } else {
                    //go back, let the rest of the function parse the "/"
                    reset(cur);
                    break;
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
            case '+': token = Token.PLUS; break;
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
                reportError(true, "no closing >\"< for a value"); //" yay
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
                    if (i == 0)
                        reportError(false, "expected %s hex digits max", digits);
                    break;
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

    private bool isVal(Token token) {
        return token == Token.VALUE || token == Token.ID;
    }

    private void parseNode(ConfigNode node, bool toplevel) {
        Token token;
        char[] str;
        char[] comm;
        char[] waste, waste2;
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
                            "value expected (did you forget the \"\"?)"); //"
                        //if he really forgot the "", don't go back
                        //reset(p); //go back
                    } else if (token != Token.VALUE) {
                        reportError(false, "after '=': value expected");
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

            if (token == Token.PLUS) {
                //the ID of the new node is expected to follow
                nextToken(token, str, waste);
                if (!isVal(token)) {
                    reportError(true, "after '+': id or value expected");
                    continue;
                }
                id = str;

                ConfigNode newnode = node.addNode(id, comm);
                //now, either an id/value, a '=', or a '{'
                nextToken(token, str, waste);

                if (token == Token.ASSIGN) {
                    //id/value to assign to the node as value
                    nextToken(token, str, waste);
                    if (!isVal(token)) {
                        reportError(true, "after '=': id or value expected");
                        continue;
                    }
                    newnode.value = str;
                    continue;
                }

                //optional value
                if (isVal(token)) {
                    newnode.value = str;
                    nextToken(token, str, waste);
                }

                if (token != Token.OPEN) {
                    reportError(true, "what.");
                    continue;
                }

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
        node.endComment = comm;
    }

    private void doParse() {
        mRootnode = new ConfigNode();

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

    public void writeFile(Output stream) {
        if (rootnode !is null) {
            rootnode.writeFile(stream);
        }
    }
}

debug:

import std.stdio;

private bool test_error;

ConfigNode debugParseFile(char[] f) {
    void err(char[] msg) {
        writefln("configfile unittest: %s", msg);
        test_error = true;
    }
    auto p = new ConfigFile(f, "test", &err);
    return p.rootnode();
}

char[] t1 =
`//hr
foo = "123"
//hu
moo {
    //ha
    goo = "456"
    //na
}
//fa
`;

char[] t2 =
`+ "foo hu" = "456"
`;

char[] t3 =
`+ "foo hu" "456" {
    goo = "5676"
}
`;

char[] t4 =
`+ "foo hu" {
    + "goo g" = "5676"
}
`;

unittest {
    auto n1 = debugParseFile(t1);
    auto s1 = n1.writeAsString();
    assert (s1 == t1);

    auto n2 = debugParseFile(t2);
    auto s2 = n2.writeAsString();
    assert (n2["foo hu"] == "456");
    assert (s2 == t2);

    auto n3 = debugParseFile(t3);
    auto s3 = n3.writeAsString();
    assert (n3["foo hu"] == "456");
    assert (n3.getSubNode("foo hu")["goo"] == "5676");
    assert (s3 == t3);

    auto n4 = debugParseFile(t4);
    auto s4 = n4.writeAsString();
    assert (s4 == t4);

    assert (!test_error);
    writefln("configfile.d: unittest success");
}

/+
Lexer:
    it's all utf-8
    newlines count as whitespace
    comments
    escapes in strings

Syntax:
    //normal syntax

    <file> = <nodelist>
    <nodelist> = <node>*
    <id> = A-Z a-z 0-9 _
    <value> = '"' any utf-8 + escape sequences '"'
    //normal name/value pairs
    <node> = <id> '=' <value>
    //normal unnamed values (for lists)
    <node> = <value>
    //normal named/unnamed sub-node
    <node> = [<id>] '{' <nodelist> '}'

    //extensions

    <val> = <id>|<value>
    //name/value pair, where the name can contain any chars
    <node> = '+' <val> '=' <val>
    //named subnodes with names same as above
    //first val is the name, second the value (empty string if ommitted)
    <node> = '+' <val> [<val>] '{' <nodelist> '}'

e.g. >+node "123" { }< is equal to >"node" = 123<
Attention: >"some node id" { }< will not work as expected; it does the same as
    the old code and create two nodes
+/
