module utils.configfile;

import marray = utils.array;
import utils.stream;
import str = utils.string;
import tango.util.Convert : to, ConversionException;
import tango.text.convert.Float : toFloat;
import tango.core.Exception;
import base64 = tango.util.encode.Base64;
import utils.log;
import utils.misc;

//only for byte[]
import utils.gzip;

import utils.strparser : stringToType, fromStr, toStr,
                         fromStrSupports, toStrSupports;
import tango.core.Traits : isIntegerType, isRealType, isAssocArrayType;
import tango.text.Util : delimiters;

//replacement for the buggy functions in std.ctype
//(as of DMD 0.163, the is* functions silenty fail for unicode characters)
//these replacement functions are not really "correct", just hacked together

private bool my_isprint(dchar c) {
    return (c >= 32);
}
private bool my_isspace(dchar c) {
    //return (c == 9 || c == 10 || c == 13 || c == 32);
    //consistency with str.* functions used in doWrite
    return str.iswhite(c);
}
//maybe or maybe not equivalent to isalnum()
private bool my_isid(dchar c) {
    bool r = (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || c == '_' || c == '-' || c == '*' || c == '$' || c == ':'
        || c == '%' || c == '&' || c == '(' || c == ')' || c == '[' || c == ']';
    //Trace.formatln("{} -> {}", c, r);
    return r;
}

private bool is_config_id(string name) {
    //xxx: doesn't parse the utf-8, that's ok depending what my_isid() does
    for (int n = 0; n < name.length; n++) {
        if (!my_isid(name[n]))
            return false;
    }
    return true;
}

//all default values (== .init) represent unknown values
struct FilePosition {
    string filename = "unknown";
    int line = -1;
    int column = -1;

    //return true if there's at least a little bit of useful information
    bool useful() {
        return line >= 0;
    }

    string toString() {
        return myformat("'{}':{}:{}", filename, line >= 0 ? toStr(line) : "?",
            column >= 0 ? toStr(column) : "?");
    }
}

/// a subtree in a ConfigFile, can contain named and unnamed values and nodes
public class ConfigNode {
    private {
        string mName;
        ConfigNode mParent;
        ConfigNode[] mItems; //xxx replace by linked list
    }

    //value can contain anything (as long as it is valid UTF-8)
    public string value;

    //comment before theline, which defined this node
    public string comment;
    //comment after last item in the node (only useful if there are subnodes)
    public string endComment;

    //file position from parser - note that the node might have been added later
    //(like with getSubNode()), and filePosition might not contain any useful
    //information - then use originFilePosition() instead
    FilePosition filePosition;

    ConfigNode copy() {
        auto r = new ConfigNode();
        r.endComment = endComment;
        r.comment = comment;
        r.value = value;
        r.mName = mName;
        r.mParent = null;
        r.filePosition = filePosition;
        foreach (ConfigNode item; this) {
            ConfigNode n = item.copy();
            r.addNode(n);
        }
        return r;
    }

    //return file/ConfigNode position
    string locationString() {
        string getPath(ConfigNode s) {
            return (s.parent ? getPath(s.parent) : "") ~ "/" ~ s.name;
        }
        string path = getPath(this);
        FilePosition pos = originFilePosition();
        return (pos.useful() ? pos.toString() ~ " " : "") ~ "[" ~ path ~ "]";
    }

    FilePosition originFilePosition() {
        if (!filePosition.useful() && parent)
            return parent.originFilePosition();
        return filePosition;
    }

    public ConfigNode parent() {
        return mParent;
    }

    public string name() {
        return mName;
    }

    public bool hasSubNodes() {
        return !!mItems.length;
    }

    public void rename(string new_name) {
        mName = new_name;
    }

    ///if item already has a parent, it's removed first
    void addNode(ConfigNode item) {
        if (item.mParent)
            item.mParent.remove(item);
        item.mParent = this;
        mItems ~= item;
    }

    void addNode(string name, ConfigNode item) {
        addNode(item);
        item.rename(name);
    }

    void remove(ConfigNode item) {
        //(NOTE: clear() also can remove nodes)

        if (!item)
            return;

        assert(item.mParent is this);

        for (uint n = 0; n < mItems.length; n++) {
            if (mItems[n] is item) {
                mItems = mItems[0..n] ~ mItems[n+1..$];
                break;
            }
        }
    }

    bool remove(string name) {
        auto node = find(name);
        if (!node)
            return false;
        remove(node);
        return true;
    }

    /// unlink all contained config items
    public void clear() {
        foreach (i; mItems) {
            i.mParent = null;
        }
        mItems = null;
    }

    /// find an entry, return null if not found
    /// if there are several items with the same name, return the first one
    ConfigNode find(string name) {
        //unnamed items don't count?
        if (name.length == 0)
            return null;
        //linear search - shouldn't be a problem in the general case, most
        //nodes have not many items, and linear search is faster/simpler.
        //if something needs fast lookups, it should create its own index.
        foreach (ConfigNode sub; mItems) {
            if (sub.name == name)
                return sub;
        }
        return null;
    }

    bool exists(string name) {
        return !!find(name);
    }

    alias exists hasNode;
    alias exists hasValue;

    ConfigNode add(string name = "", string value = "") {
        auto node = new ConfigNode();
        node.value = value;
        addNode(name, node);
        return node;
    }

    /// Find a subnode by following a path.
    /// Path component separator is "."
    public ConfigNode getPath(string path, bool create = false) {
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
    public void parsePath(string path, out ConfigNode node, out string val) {
        auto val_start = str.rfind(path, '.');
        auto pathname = path[0..(val_start >= 0 ? val_start : 0)];
        val = path[val_start+1..$];
        node = getPath(pathname, true);
    }

    public void setStringValueByPath(string path, string value) {
        ConfigNode node;
        string valname;
        parsePath(path, node, valname);
        node.setStringValue(valname, value);
    }

    public string getStringValueByPath(string path) {
        ConfigNode node;
        string valname;
        parsePath(path, node, valname);
        return node.getStringValue(valname);
    }

    /// like find(), but return null if item has the wrong type
    /// for create==true, create a new / overwrite existing values/nodes
    /// instead of returning null
    public ConfigNode findNode(string name, bool create = false) {
        ConfigNode sub = find(name);
        if (sub !is null || !create)
            return sub;

        //create & add
        sub = new ConfigNode();
        addNode(name, sub);
        return sub;
    }

    //difference to findNode: different default value for 2nd parameter :-)
    public ConfigNode getSubNode(string name, bool createIfNotExist = true) {
        return findNode(name, createIfNotExist);
    }

    //number of nodes and values
    int count() {
        return mItems.length;
    }

    ///if count > 0, return first node, else return null
    ConfigNode first() {
        if (mItems.length > 0)
            return mItems[0];
        return null;
    }

    /// Access a value by name, return 'default' if it doesn't exist.
    public string getStringValue(string name, string def = "") {
        auto value = findNode(name);
        if (value is null) {
            return def;
        } else {
            return value.value;
        }
    }

    /// Create/overwrite a string value ('name = "value"')
    public void setStringValue(string name, string value) {
        auto val = findNode(name, true);
        val.value = value;
    }

    //alias to getStringValue/setStringValue
    public string opIndex(string name) {
        return getStringValue(name);
    }
    public void opIndexAssign(string value, string name) {
        setStringValue(name, value);
    }

    private void doWrite(void delegate(string) sink, uint level) {
        string newline = "\n";
        const int indent = 4;
        //xxx this could produce major garbage collection thrashing when writing
        //    big files
        string indent_str = str.repeat(" ", indent*level);

        void writeLine(string stuff) {
            sink(indent_str);
            sink(stuff);
            sink(newline);
        }

        void writeComment(string comment) {
            //this strip is used to cut off unneeded starting/trailing new lines
            string[] comments = str.splitlines(str.strip(comment));

            foreach(string lines; comments) {
                //don't write whitespace since we reformat the file
                auto line = str.strip(lines);
                if (line == "")
                    continue;
                writeLine(line);
            }
        }

        void writeValue(string v) {
            sink("\"");
            sink(ConfigFile.doEscape(v));
            sink("\"");
        }

        bool name_is_funny = !is_config_id(name);

        void writeName(bool ext) {
            if (ext || !name.length) {
                //new syntax, which allows spaces etc. in names
                sink("+ ");
                writeValue(name);
            } else {
                sink(name);
            }
        }

        //"level!=0": hack for rootnode
        if ((level != 0) && !mItems.length) {
            //a normal name=value entry
            //xxx will throw away endComment for sub-nodes which are empty
            if (name.length > 0) {
                writeName(name_is_funny);
                sink(" = ");
            }
            writeValue(value);
            return;
        }

        bool have_value = value.length != 0;

        /+
        //ah this sucks, but nothing can be done about it
        //note that the root node can't have a name either
        if (level == 0 && have_value) {
            throw new CustomException("can't save root ConfigNodes that have a value");
        }
        +/

        if (level != 0) {
            if (name.length > 0 || have_value) {
                writeName(name_is_funny || have_value);
                if (have_value) {
                    sink(" ");
                    writeValue(value);
                }
                sink(" ");
            }
            sink("{");
            sink(newline);
        }

        foreach (ConfigNode item; this) {
            writeComment(item.comment);
            sink(indent_str);
            item.doWrite(sink, level+1);
            sink(newline);
        }

        writeComment(endComment);

        if (level != 0) {
            //this is a hack
            sink(indent_str[0 .. $-indent]);
            sink("}");
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

    //foreach(string, string; ConfigNode) enumerate (name, value) pairs
    public int opApply(int delegate(inout string, inout string) del) {
        foreach (ConfigNode v; mItems) {
            string tmp = v.name;
            int res = del(tmp, v.value);
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

    //for use by getCurValue()
    //putting them outside of the template reduces the exe size
    private void invalid(Exception e = null, string txt = "") {
        string msg = "error at " ~ locationString();
        if (txt.length) {
            msg ~= " " ~ txt;
        }
        if (e) {
            msg ~= ": " ~ e.toString();
        }
        throw new CustomException(msg);
    }
    private void nosubnodes() {
        if (mItems.length)
            invalid(null, "value-only node has sub nodes");
    }
    private void novalue() {
        if (value != "")
            invalid(null, "non-empty string value for array/etc. node");
    }

    ///Get the value of the current node, parsed as type T
    ///If the value cannot be converted to T (parsing failed), throw ConfigError
    //currently supports:
    //  string
    //  byte[], ubyte[] (as base64)
    //  all types supported by toStr() / fromStr() in utils.strparser
    //  bool[], int[], float[] (as space-separated string)
    //  other arrays of above types (as list of unnamed subnode)
    //  AAs with a basic (-> Tango's to) key type and a supported value type
    //  other structs (as name-value pairs)
    public T getCurValue(T)() {
        static if (is(T : string)) {
            nosubnodes();
            return value;
        } else static if (is(T : byte[]) || is(T : ubyte[])) {
            nosubnodes();
            try {
                return cast(T)decodeByteArray(value);
            } catch (Exception e) {
                //base64.decode really throws the type Exception
                invalid(e);
            }
        } else static if (is(T T2 : T2[])) {
            novalue();
            //read all (unnamed) subnodes
            auto res = new T2[mItems.length];
            foreach (int idx, ConfigNode n; mItems) {
                res[idx] = n.getCurValue!(T2)();
            }
            return res;
        } else static if (isAssocArrayType!(T)) {
            novalue();
            T res;
            try {
                //again, one invalid value makes everything fail
                foreach (int idx, ConfigNode n; mItems) {
                    res[fromStr!(typeof(T.init.keys[0]))(n.name)] =
                        n.getCurValue!(typeof(T.init.values[0]))();
                }
            } catch (ConversionException e) {
                //from to()
                invalid(e);
            }
            //n.getCurValue() can also throw ConfigError (no need to catch)
            return res;
        } else static if (fromStrSupports!(T)) {
            nosubnodes();
            try {
                return fromStr!(T)(value);
            } catch (ConversionException e) {
                invalid(e);
            }
        } else static if (is(T == struct)) {
            novalue();
            T res;
            const names = structMemberNames!(T)();
            foreach (int idx, x; res.tupleof) {
                res.tupleof[idx] = getValue(names[idx], T.init.tupleof[idx]);
            }
            return res;
        } else {
            //static assert(false, "Implement me, for: " ~ T.stringof);
            //meh, for enums... so then, come here, runtime errors
            nosubnodes();
            T res;
            try {
                res = stringToType!(T)(value);
            } catch (ConversionException e) {
                invalid(e);
            }
            return res;
        }
    }

    ///Set the value of the current node to value
    ///Note: may create a more complex structure than simply setting the value;
    ///      only safe way to read it is using getCurValue!(T)()
    //for a list of types, see getCurValue
    public void setCurValue(T)(T value) {
        static if (is(T : string)) {
            clear();
            this.value = value;
        } else static if (is(T : byte[]) || is(T : ubyte[])) {
            clear();
            this.value = encodeByteArray(cast(ubyte[])value);
        } else static if (is(T T2 : T2[])) {
            //saving of array types
            this.value = "";
            clear();
            foreach (T2 v; value) {
                auto node = add();
                node.setCurValue(v);
            }
        } else static if (isAssocArrayType!(T)) {
            this.value = "";
            clear();
            foreach (akey, avalue; value) {
                setValue(toStr(akey), avalue);
            }
        } else static if (toStrSupports!(T)) {
            this.value = toStr!(T)(value);
        } else static if (is(T == struct)) {
            this.value = "";
            clear();
            const names = structMemberNames!(T)();
            foreach (int idx, x; value.tupleof) {
                //bug 3997
                static if (!isAssocArrayType!(typeof(x))) {
                    bool unequal = x != T.init.tupleof[idx];
                } else {
                    bool unequal = true;
                }
                if (unequal) {
                    setValue(names[idx], x);
                }
            }
        } else {
            static assert(false, "Implement me");
        }
    }

    ///Read the value of a named subnode of the current node
    ///return def if the value was not found; throw ConfigError on parse error
    public T getValue(T)(string name, T def = T.init) {
        auto v = findNode(name);
        if (!v)
            return def;
        return v.getCurValue!(T)();
    }

    ///Set the value of a named subnode of the current node to value
    ///see also setCurValue
    public void setValue(T)(string name, T value) {
        auto val = findNode(name, true);
        val.setCurValue!(T)(value);
    }

    ///Legacy accessor functions follow
    // -->
    public int getIntValue(string name, int def = 0) {
        return getValue(name, def);
    }
    public void setIntValue(string name, int value) {
        setValue(name, value);
    }
    public bool getBoolValue(string name, bool def = false) {
        return getValue(name, def);
    }
    public void setBoolValue(string name, bool value) {
        setValue(name, value);
    }
    public float getFloatValue(string name, float def = float.nan) {
        return getValue(name, def);
    }
    public void setFloatValue(string name, float value) {
        setValue(name, value);
    }
    //<-- end legacy accessor functions

    //just for scripting
    string[] getStringArray(string name) {
        return getValue!(string[])(name);
    }
    void setStringArray(string name, string[] value) {
        setValue(name, value);
    }

    static string encodeByteArray(ubyte[] data) {
        if (!data.length)
            return "[]";

        data = gzipData(data);

        scope(exit) delete data;
        return base64.encode(data);
    }

    static ubyte[] decodeByteArray(string input) {
        if (input == "[]")
            return null;
        ubyte[] buf;
        //throws Exception (really; stupid tango devs)
        buf = base64.decode(input);

        try {
            auto res = gunzipData(buf);
            delete buf;
            return res;
        } catch (ZlibException e) {
            //decompression failed, so assume the data wasn't compressed
            //xxx maybe write a header to catch this case
        }

        return buf;
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
            if (recursive && item && item2)
            {
                item2.mixinNode(item, overwrite, true);
                if (overwrite)
                    item2.value = item.value;
                continue;
            }
            if (overwrite && item2) {
                remove(item2);
                item2 = null;
            }
            if (!item2) {
                addNode(item.copy());
            }
        }
    }

    /// Does the following:
    /// for each subnode in "this", look for the key "key"
    /// if it finds "key", look for another subnode of "this" with that value
    /// then remove the "key" and mixin that other subnode
    /// do that recursively
    public void templatetifyNodes(string key) {
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

        foreach (ConfigNode node; this) {
            resolveTemplate(node);
        }
    }

    void write(void delegate(string) sink) {
        doWrite(sink, 0);
    }

    public void writeFile(PipeOut writer) {
        //just for the damn cast that does nothing
        void sink(string s) {
            writer.write(cast(ubyte[])s);
        }
        write(&sink);
    }

    public string writeAsString() {
        marray.AppenderVolatile!(char) outs;
        //is this kosher? anyway, I don't care
        write(&outs.opCatAssign);
        return outs[];
    }
}


private class ConfigFatalError : CustomException {
    int type;
    this(int type) {
        super("");
        this.type = type;
    }
}

/// Used to manage config files. See docs/*.grm for the used format.
public class ConfigFile {
    private string mFilename;
    private string mData;
    private Position mPos;          //current pos in data
    private Position mNextPos;      //position of following char
    private dchar mCurChar;         //char at mPos
    private ConfigNode mRootnode;
    private uint mErrorCount;

    public ConfigNode rootnode() {
        return mRootnode;
    }

    /// Read the config file from 'source' and output any errors to 'errors'
    /// 'filename' is used only for error messages
    public this(string source, string filename) {
        loadFrom(source, filename);
    }

    public this(Stream source, string filename) {
        loadFrom(source, filename);
    }

    static ConfigNode Parse(string source, string filename) {
        auto cf = new ConfigFile(source, filename);
        return cf.rootnode;
    }

    /// do the same like the constructor
    /// use hasErrors() to check if there were any errors
    public void loadFrom(string source, string filename) {
        mData = source;
        mFilename = filename;
        doParse();
    }

    /// do the same like the constructor
    public void loadFrom(Stream source, string filename) {
        source.position = 0;
        mData = cast(string)source.readAll();
        mFilename = filename;
        doParse();
    }

    private void init_parser() {
        mNextPos = Position.init;
        mErrorCount = 0;

        //if there's one, skip the unicode BOM
        //NOTE: tried to use tango.text.convert.UnicodeBom, but that thing sucks
        //also fuck Microsoft for introducing useless crap
        const string cUtf8Bom = [0xEF, 0xBB, 0xBF];
        str.eatStart(mData, cUtf8Bom);

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

    private FilePosition filePos(Position pos) {
        FilePosition res;
        res.filename = mFilename;
        res.line = pos.line;
        res.column = pos.column;
        return res;
    }

    //fatal==false: continue parsing allthough config file is invalid
    //fatal==true: parsing won't be continued (abort by throwing an exception)
    private void reportError(bool fatal, string fmt, ...) {
        mErrorCount++;

        auto log = registerLog("configparse");

        log.error("error in {}({},{}): ", mFilename, mPos.line, mPos.column);
        //scary D varargs!
        log.emitx(LogPriority.Error, fmt, _arguments, _argptr);

        //abuse exception handling to abort parsing
        if (fatal) {
            log.error("{}: fatal error, aborting", mFilename);
            throw new ConfigFatalError(2);
        } else if (mErrorCount > cMaxErrors) {
            log.error("{}: too many errors, aborting", mFilename);
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
            result = str.decode(mData, mNextPos.bytePos);
        } catch (str.UnicodeException utfe) {
            reportError(true, "invalid UTF-8 sequence");
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

    private string copyOut(Position p1, Position p2) {
        return mData[p1.bytePos .. p2.bytePos];
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
    private bool nextToken(out Token token, out string str, out string comm) {
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

        int is_value = 0;
        const final char cValueOpen = '"';
        const final char cValueClose = '"';
        const final char cValueOpen2 = '`';
        const final char cValueClose2 = '`';
        //lololo
        const final char cValueOpen3 = '<';
        const final char cValueClose3 = '>';
        const final char cValueMark3 = ':';

        dchar value3_endmark;

        if (curChar == cValueOpen) {
            //parse a VALUE; VALUEs must end with another '"'
            //if there's no closing '"', then the user is out of luck
            //(this needs a better error handling rule)
            next();
            is_value = 1;
        } else if (curChar == cValueOpen2) {
            next();
            is_value = 2;
        } else if (curChar == cValueOpen3) {
            next();
            if (curChar == EOF)
                reportError(true, "long string literal with '<': EOF");
            //NOTE: I'd like to be able to have an end mark longer than one char
            //  then you could write: <foo: blablabla foo>
            //but questionable feature, and not worth the effort right now
            value3_endmark = curChar;
            next();
            if (curChar == ':') {
                next();
            } else {
                reportError(false, "long string literal with '<': ':' after "
                    " '<' and end marker expected, e.g. '<#: ...stuff... #>'");
            }
            is_value = 3;
        }

        //if not a value: any chars that come now must form ID tokens
        //(the error handling relies on it)

        string curstr = "";
        Position strstart = curpos;

        void val_copy(Position until) {
            string stuff = copyOut(strstart, until);
            curstr ~= stuff;
            strstart = curpos;
        }

        for (;;) {
            if (curChar == '\r') {
                //remove windows CR
                next();
                val_copy(curpos);
                continue;
            }

            if (is_value == 1) {
                //special handling for VALUEs
                if (curChar == '\\') {
                    auto skip_from = curpos;
                    next();
                    char escape = parseEscape();
                    val_copy(skip_from);
                    curstr ~= escape;
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
            } else if (is_value == 2) {
                //`backtick` string, read as is, no escaping
                if (curChar == cValueClose2)
                    break;
            } else if (is_value == 3) {
                if (curChar == value3_endmark) {
                    //xxx: could look-ahead, and only end the literal if '>'
                    //  really follows (and otherwise continue the literal)
                    val_copy(curpos);
                    next();
                    if (curChar == cValueClose3) {
                        next();
                    } else {
                        reportError(false, "long string literal with '<': "
                            "'>' expected when closing the literal, e.g.:"
                            " '<#: foo #>'");
                    }
                    strstart = curpos;
                    break;
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

        val_copy(curpos);

        if (is_value) {
            if (is_value == 1 && curChar != cValueClose) {
                reportError(true, "no closing >\"< for a value"); //" yay
            } else if (is_value == 2 && curChar != cValueClose2) {
                reportError(true, "no closing >`< for a backticked value");
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
                        reportError(false, "expected {} hex digits max", digits);
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
    public static string doEscape(string s) {
        string output;

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
                string fmt = "x{:x2}";
                if (c > 0xff) {
                    fmt = "u{:x4}";
                } else if (c > 0xffff) {
                    fmt = "U{:x8}"; //???
                }

                output ~= myformat(fmt, c);
            } else {
                str.encode(output, c);
            }
        }
        return output;
    }

    private bool isVal(Token token) {
        return token == Token.VALUE || token == Token.ID;
    }

    private void parseNode(ConfigNode node, bool toplevel) {
        Token token;
        string str;
        string comm;
        string waste, waste2;
        string id;

        for (;;) {
            nextToken(token, str, comm);
            id = "";

            if (token == Token.VALUE) {
                //a VALUE without an ID
                auto newnode = node.add();
                newnode.filePosition = filePos(curpos());
                newnode.comment = comm;
                newnode.value = str;
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

                    auto newnode = node.add(id);
                    newnode.filePosition = filePos(curpos());
                    newnode.value = str;
                    newnode.comment = comm;

                    continue;
                }
            }

            if (token == Token.OPEN) {
                ConfigNode newnode = node.add(id);
                newnode.filePosition = filePos(curpos());
                newnode.comment = comm;
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

                ConfigNode newnode = node.add(id);
                newnode.filePosition = filePos(curpos());
                newnode.comment = comm;
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
                    " '=' or '{{'");
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
            string waste, morewaste;

            mRootnode.filePosition = filePos(curpos());

            Token token;
            parseNode(mRootnode, true);
            nextToken(token, waste, morewaste);
            if (token != Token.EOF) {
                //moan about unparsed stuff
                reportError(false, "aborting here (nothing more to parse, but "
                    "there is still text)");
            }
        } catch (ConfigFatalError e) {
            //Exception is only used to exit parser function hierachy
        }
    }

    public bool hasErrors() {
        return mErrorCount != 0;
    }
}

debug:

private bool test_error;

ConfigNode debugParseFile(string f) {
    auto p = new ConfigFile(f, "test");
    test_error = p.hasErrors();
    return p.rootnode();
}

string t1 =
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

string t2 =
`+ "foo hu" = "456"
`;

string t3 =
`+ "foo hu" "456" {
    goo = "5676"
}
`;

string t4 =
`+ "foo hu" {
    + "goo g" = "5676"
}
`;

string t5 =
`styles {
    + "*" {
        + "highlight-alpha" = "0"
    }
    + "/w-button" {
        + "highlight-alpha" = "0.5"
    }
}`;

//just check the <?: ... ?> string literal
string t6_1 =
`moo = "hello" //a
 foo = <Ä: brrr grrr
    hrrr drrr "a" 'b' <a: kdfg a> Ä>
 goo = "123"
`;
string t6_2 =
`moo = "hello"
//a
foo = " brrr grrr\n    hrrr drrr \"a\" \'b\' <a: kdfg a> "
goo = "123"
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

    debugParseFile(t5);

    auto n6 = debugParseFile(t6_1);
    auto s6 = n6.writeAsString();
    assert (s6 == t6_2, s6 ~ " -- " ~ t6_2);

    assert (!test_error);
}

/+
Lexer:
    it's all utf-8
    newlines count as whitespace
    comments: /* ... */ /+ ... +/ //...<eol>
        xxx: /+ +/ doesn't nest as in D
    escapes in strings
    string literals:
        "...." (one line, with escapes)
        `....` (multiline, without escapes)
        <?: ... ?> (multiline, without escapes, instead of '?', any char goes)

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

unittest {
    auto t = new ConfigNode();
    t.setCurValue!(int)(1234);
    assert(t.value == "1234");
}
