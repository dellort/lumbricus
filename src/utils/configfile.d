module utils.configfile;

import utils.stream;
import str = utils.string;
import tango.util.Convert : to, ConversionException;
import tango.text.convert.Float : toFloat;
import tango.core.Exception;
import base64 = tango.io.encode.Base64;
import utils.output : Output, StringOutput, PipeOutput;
import utils.misc;

//only for byte[]
import tango.io.device.Array;
import tango.io.compress.ZlibStream;

import utils.strparser : stringToBox, hasBoxParser, fromStr, toStr,
                         fromStrSupports, toStrSupports;
import utils.mybox : MyBox;
import tango.core.Tuple : Tuple;
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

private bool is_config_id(char[] name) {
    //xxx: doesn't parse the utf-8, that's ok depending what my_isid() does
    for (int n = 0; n < name.length; n++) {
        if (!my_isid(name[n]))
            return false;
    }
    return true;
}

//all default values (== .init) represent unknown values
struct FilePosition {
    char[] filename = "unknown";
    int line = -1;
    int column = -1;

    //return true if there's at least a little bit of useful information
    bool useful() {
        return line >= 0;
    }

    char[] toString() {
        return myformat("'{}':{}:{}", filename, line >= 0 ? toStr(line) : "?",
            column >= 0 ? toStr(column) : "?");
    }
}

/// a subtree in a ConfigFile, can contain named and unnamed values and nodes
public class ConfigNode {
    private {
        char[] mName;
        ConfigNode mParent;
        ConfigNode[] mItems; //xxx replace by linked list
    }

    //value can contain anything (as long as it is valid UTF-8)
    public char[] value;

    //comment before theline, which defined this node
    public char[] comment;
    //comment after last item in the node (only useful if there are subnodes)
    public char[] endComment;

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
    char[] locationString() {
        char[] getPath(ConfigNode s) {
            return (s.parent ? getPath(s.parent) : "") ~ "/" ~ s.name;
        }
        char[] path = getPath(this);
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

    public char[] name() {
        return mName;
    }

    public bool hasSubNodes() {
        return !!mItems.length;
    }

    public void rename(char[] new_name) {
        mName = new_name;
    }

    ///if item already has a parent, it's removed first
    void addNode(ConfigNode item) {
        if (item.mParent)
            item.mParent.remove(item);
        item.mParent = this;
        mItems ~= item;
    }

    void addNode(char[] name, ConfigNode item) {
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

    bool remove(char[] name) {
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
    ConfigNode find(char[] name) {
        //linear search - shouldn't be a problem in the general case, most
        //nodes have not many items, and linear search is faster/simpler.
        //if something needs fast lookups, it should create its own index.
        foreach (ConfigNode sub; mItems) {
            if (sub.name == name)
                return sub;
        }
        return null;
    }

    bool exists(char[] name) {
        return !!find(name);
    }

    alias exists hasNode;
    alias exists hasValue;

    ConfigNode add(char[] name = "", char[] value = "") {
        auto node = new ConfigNode();
        node.value = value;
        addNode(name, node);
        return node;
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

    /// like find(), but return null if item has the wrong type
    /// for create==true, create a new / overwrite existing values/nodes
    /// instead of returning null
    public ConfigNode findNode(char[] name, bool create = false) {
        ConfigNode sub = find(name);
        if (sub !is null || !create)
            return sub;

        //create & add
        sub = new ConfigNode();
        addNode(name, sub);
        return sub;
    }

    alias findNode findValue;

    //difference to findNode: different default value for 2nd parameter :-)
    public ConfigNode getSubNode(char[] name, bool createIfNotExist = true) {
        return findNode(name, createIfNotExist);
    }

    /// find and return a ConfigNode with that name
    /// if it doesn't exist, do one of those things:
    ///   a) add and return a new ConfigNode with that name (like getSubNode())
    ///      and issue a warning to the user (in whatever way)
    ///   b) throw an exception
    /// it's also an error if the node is not unique (by name)
    ConfigNode requireNode(char[] name) {
        return getSubNode(name); //xD
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
                auto line = str.strip(lines);
                if (line == "")
                    continue;
                writeLine(line);
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

    private static char[] structProcName(char[] tupleString) {
        //struct.tupleof is always fully qualified (obj.x), so get the
        //string after the last .
        int p = str.rfind(tupleString, '.');
        assert(p > 0 && p < tupleString.length-1);
        //xxx maybe do more name processing here, like replacing capitals by
        //    underscores
        return tupleString[p+1..$];
    }

    ///Get the value of the current node, parsed as type T
    ///If the value cannot be converted to T (parsing failed), throw ConfigError
    //currently supports:
    //  char[]
    //  byte[], ubyte[] (as base64)
    //  all types supported by toStr() / fromStr() in utils.strparser
    //  bool[], int[], float[] (as space-separated string)
    //  other arrays of above types (as list of unnamed subnode)
    //  AAs with a basic (-> Tango's to) key type and a supported value type
    //  other structs (as name-value pairs)
    public T getCurValue(T)() {
        void invalid(Exception e = null, char[] txt = "") {
            //xxx why hidden inner class? how are users supposed to catch this??
            //    answer: not at all, I consider this a temporary hack
            //    a real solution must:
            //     - catch typos (warn about nodes that aren't read)
            //       (doesn't work at all with current design)
            //     - distinguish optional and required values
            //       (required values raise an error if node doesn't exist)
            //     - continue reading out the confignode even after an error,
            //       because reporting all errors is better than exit-on-first
            //     - avoid function-with-dozens-of-getValue-calls orgies
            static class ConfigError : Exception {
                this(char[] msg) {
                    super(msg);
                }
            }
            char[] msg = "error at " ~ locationString();
            if (txt.length) {
                msg ~= " " ~ txt;
            }
            if (e) {
                msg ~= " original exception: " ~ e.toString();
            }
            throw new ConfigError(msg);
        }
        void nosubnodes() {
            if (mItems.length)
                invalid(null, "value-only node has sub nodes");
        }
        void novalue() {
            if (value != "")
                invalid(null, "non-empty string value for array/etc. node");
        }

        static if (is(T : char[])) {
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
            foreach (int idx, x; res.tupleof) {
                res.tupleof[idx] = getValue(
                    structProcName(res.tupleof[idx].stringof),
                    T.init.tupleof[idx]);
            }
            return res;
        } else {
            static assert(false, "Implement me, for: " ~ T.stringof);
        }
    }

    ///Set the value of the current node to value
    ///Note: may create a more complex structure than simply setting the value;
    ///      only safe way to read it is using getCurValue!(T)()
    //for a list of types, see getCurValue
    public void setCurValue(T)(T value) {
        static if (is(T : char[])) {
            clear();
            this.value = value;
        } else static if (is(T : byte[]) || is(T : ubyte[])) {
            clear();
            this.value = encodeByteArray(cast(ubyte[])value, true);
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
            foreach (int idx, x; value.tupleof) {
                if (x != T.init.tupleof[idx]) {
                    setValue(structProcName(value.tupleof[idx].stringof), x);
                }
            }
        } else {
            static assert(false, "Implement me");
        }
    }

    ///Read the value of a named subnode of the current node
    ///return def if the value was not found; throw ConfigError on parse error
    public T getValue(T)(char[] name, T def = T.init) {
        auto v = findValue(name);
        if (!v)
            return def;
        return v.getCurValue!(T)();
    }

    ///Set the value of a named subnode of the current node to value
    ///see also setCurValue
    public void setValue(T)(char[] name, T value) {
        auto val = findValue(name, true);
        val.setCurValue!(T)(value);
    }

    ///Legacy accessor functions follow
    // -->
    public int getIntValue(char[] name, int def = 0) {
        return getValue(name, def);
    }
    public void setIntValue(char[] name, int value) {
        setValue(name, value);
    }
    public bool getBoolValue(char[] name, bool def = false) {
        return getValue(name, def);
    }
    public void setBoolValue(char[] name, bool value) {
        setValue(name, value);
    }
    public float getFloatValue(char[] name, float def = float.nan) {
        return getValue(name, def);
    }
    public void setFloatValue(char[] name, float value) {
        setValue(name, value);
    }
    //<-- end legacy accessor functions

    static char[] encodeByteArray(ubyte[] data, bool compress) {
        //
        if (!data.length)
            return "[]";

        void[] garbage1;
        if (compress) {
            scope buffer = new Array(2048, 2048);
            scope z = new ZlibOutput(buffer, ZlibOutput.Level.Best);
            z.write(data);
            z.close();
            garbage1 = buffer.slice();
            data = cast(ubyte[])garbage1;
        }

        char[] res = base64.encode(data);
        delete garbage1;
        return res;
    }

    static ubyte[] decodeByteArray(char[] input) {
        if (input == "[]")
            return null;
        ubyte[] buf;
        //throws Exception (really; stupid tango devs)
        buf = base64.decode(input);

        try {
            scope buffer = new Array(buf);
            scope z = new ZlibInput(buffer);
            return cast(ubyte[])z.load();
        } catch (ZlibException e) {
            //decompression failed, so assume the data wasn't compressed
            //xxx maybe write a header to catch this case
        }

        return buf;
    }

    //waste of time start ---------------------->

    /++
     + after there was getIntValue() etc. and getValue(), I define this to be
     + the recommended way of reading data from a ConfigNode
     + changes:
     + 1. more strict (if unparseable, no more switch to default without error)
     + 2. errors (warns) about double or missing entries
     + 3. get rid of some old hacks
     + [4. support for AAs and arrays] <- todo
     + [5. support for algebraic types aka typesafe unions] <- I wish
     + 6. if the type ConfigNode is encountered, it's assigned the node directly
     +    (no parsing or whatever involved)
     + 7. structs are read as in getValue(), but additionally, an error is
     +    thrown if there are too less or too many items in the config node.
     +    The struct can contain const char[] cAttributes with a comma separated
     +    list of names and additional item specific attributes, for now if e.g.
     +    cAttributes = "foo?,goo?" it means both foo and goo are optional and
     +    don't need to appear in the ConfigNode.
     +/
    void read(T)(T* p_val) {
        bool read_value; //if the value was read
        bool read_subs;  //if sub nodes were read

        //always check strparser first, at least because there's Vector2, and
        //such a vector is stored as a single string (=> not read as struct)
        if (hasBoxParser(typeid(T))) {
            //parse as box, be strict about failures
            read_value = true;
            MyBox b = stringToBox!(T)(value);
            //error handling: this can be reduced to a warning; *p_val simply
            //  isn't written in this case (=> value remains at default value)
            if (b.empty)
                throw new Exception("can't read value");
            *p_val = b.unbox!(T)();
        } else static if (is(T == struct)) {
            read_subs = true;
            do_read_struct!(T)(p_val);
        } else static if (is(T == ConfigNode)) {
            read_value = true;
            read_subs = true;
            *p_val = this;
        } else {
            assert(false, "can't handle type: " ~ T.stringof);
        }

        //this is useful to warn the user about ignored items (possibly typos)
        //actually, these should only be non-fatal warnings
        if (!read_value && value.length > 0)
            throw new Exception("value not read");
        if (!read_subs && first())
            throw new Exception("sub nodes not read");
    }

    /++
     + Use like this:
     +   readAll(&var1, "var1", &var2, "var2", ...)
     + The parameters with even parameter numbers are the config-item names for
     + the preceeding variables. This is like reading struct with:
     +      struct Foo {
     +          int var1;
     +          int var2;
     +          ....
     +      }
     +      Foo foo;
     +      read!(Foo)(&foo);
     + Especially, an error is raised if there are config-items in this node
     + that are not in the parameter list.
     +/
    void readAll(T...)(T p) {
        //do ridiculous complicated magic just to call the
        //generic do_read_values function

        //get names
        char[][T.length/2] names;
        foreach (int idx, item; p) {
            static if ((idx % 2) == 1) {
                names[idx/2] = item;
            }
        }

        alias GetPointerTypes!(Step2!(p)) TP;
        RTuple!(TP) t;

        //copy in
        foreach (int idx, _; t.items) {
            t.items[idx] = *p[idx*2];
        }
        do_read_values!(TP)(&t, names);
        //copy out
        foreach (int idx, _; t.items) {
            *p[idx*2] = t.items[idx];
        }
    }

    private struct RTuple(T...) {
        T items;
    }

    void test(T)(T* p) {
    }

    //this actually reads a group of values from the config node
    //this function serves as generic backend for read() and readAll()
    //(readAll() is the only reason why not to operate on a struct directly)
    private void do_read_values(T...)(RTuple!(T)* z, char[][] names) {
        char[][T.length] realname;
        bool[T.length] is_optional, was_read;

        foreach (int idx, char[] name; names) {
            parseName(name, realname[idx], is_optional[idx]);
        }

        outer: foreach (ConfigNode item; mItems) {
            foreach (int idx, _; z.items) {
                if (realname[idx] == item.name) {
                    //this can be turned into a warning etc.
                    if (was_read[idx])
                        throw new Exception("double entry for " ~ realname[idx]);
                    was_read[idx] = true;
                    item.read(&z.items[idx]);
                    continue outer;
                }
            }
            //config item was not found
            //this can be turned into a warning etc.
            throw new Exception("unknown item in config node: " ~ item.name);
        }

        foreach (int idx, char[] name; names) {
            if (!(is_optional[idx] || was_read[idx])) {
                //turn into warning etc.
                throw new Exception("item was not read: " ~ name);
            }
        }
    }

    //parse name-option pair
    private void parseName(char[] name, out char[] realname, out bool opt) {
        realname = name;
        if (str.endsWith(realname, "?")) {
            opt = true;
            realname = realname[0..$-1];
        }
    }

    private void do_read_struct(T)(T* p) {
        //ridiculously complicated magic just to call the generric backend
        //function do_read_values()
        //it gets the struct names and turns the struct members into a tuple
        static assert(is(T == struct));
        alias typeof(p.tupleof) TP;
        RTuple!(TP) x;
        char[] atts;
        char[][TP.length] names;
        foreach (int idx, _; p.tupleof) {
            names[idx] = structProcName(p.tupleof[idx].stringof);
        }
        //take care of the options
        //cAttributes is optional (and you can't catch typos)
        static if (is(typeof(p.cAttributes))) {
            atts = p.cAttributes;
        }
        outer: foreach (char[] item; delimiters(atts, ",")) {
            if (item == "")
                continue;
            char[] name;
            bool unused;
            //name = item minus attributes
            parseName(item, name, unused);
            foreach (int idx, n; names) {
                if (n == name) {
                    //replace the name by name+attributes
                    names[idx] = item;
                    continue outer;
                }
            }
            assert(false, "cAttributes contains incorrect/not-existing entry: "
                ~ item);
        }
version(LDC) {
    //utils/configfile.d(926): Error: Exp type TupleExp not implemented:
    //tuple(x._items_field_0 = (*p).a,x._items_field_1 = (*p).b)
    pragma(msg, "ConfigNode: do_read_struct unsupported on LDC.");
} else {
        //call the backend function to do the actual work
        x.items = p.tupleof; //copy in
        do_read_values!(typeof(p.tupleof))(&x, names);
        p.tupleof = x.items; //copy out
}
    }

    //<---------------------- waste of time end


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
                n2.mixinNode(n1, overwrite, true);
                if (overwrite)
                    n2.value = n1.value;
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

    public void writeFile(PipeOut writer) {
        //blurghdgfg
        writeFile(new PipeOutput(writer));
    }

    public char[] writeAsString() {
        auto sout = new StringOutput;
        writeFile(sout);
        return sout.text;
    }
}

//---- start more ridiculousnes

//take every second element of T (starting with element 0)
//if length is uneven, cut off correctly
private template Step2(T...) {
    static if (T.length <= 1) {
        alias T Step2;
    } else {
        alias Tuple!(T[0], Step2!(T[2..$])) Step2;
    }
}

//each element is expected to be a pointer variable
//return a tuple with the unpointered type of each item
//basically, map(T, (i) {unpointer(typeof(i))})
private template GetPointerTypes(T...) {
    static if (T.length == 0) {
        alias T GetPointerTypes;
    } else {
        static if (is(typeof(T[0]) T2 : T2*)) {
            alias Tuple!(T2, GetPointerTypes!(T[1..$]))
                GetPointerTypes;
        } else {
            static assert(false);
        }
    }
}

//---- end more ridiculousnes

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

    static ConfigNode Parse(char[] source, char[] filename,
        void delegate(char[]) reportError = null)
    {
        auto cf = new ConfigFile(source, filename, reportError);
        return cf.rootnode;
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
        source.position = 0;
        mData = cast(char[])source.readAll();
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

                    reportError(true, "file encoding is >{}<, unsupported",
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

    private FilePosition filePos(ref Position pos) {
        FilePosition res;
        res.filename = mFilename;
        res.line = pos.line;
        res.column = pos.column;
        return res;
    }

    //fatal==false: continue parsing allthough config file is invalid
    //fatal==true: parsing won't be continued (abort by throwing an exception)
    private void reportError(bool fatal, char[] fmt, ...) {
        mErrorCount++;

        if (!mErrorOut)
            throw new Exception("no configfile error handler set, no detailed"
                " error messages for you.");

        //xxx: add possibility to translate error messages
        mErrorOut(myformat("ConfigFile, error in {}({},{}): ", mFilename,
            mPos.line, mPos.column));
        //scary D varargs!
        mErrorOut(formatfx(fmt, _arguments, _argptr));
        mErrorOut("\n");

        //abuse exception handling to abort parsing
        if (fatal) {
            mErrorOut(myformat("ConfigFile, {}: fatal error, aborting",
                mFilename));
            throw new ConfigFatalError(2);
        } else if (mErrorCount > cMaxErrors) {
            mErrorOut(myformat("ConfigFile, {}: too many errors, aborting",
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

            result = str.decode(mData, mNextPos.bytePos);

        } catch (str.UnicodeException utfe) {

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
                uint adv = str.stride(mData, mNextPos.bytePos);
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
                    str.decode(args, i);
                    i--; //set back to first next char
                } catch (str.UnicodeException e) {
                    args[i] = '?';
                }
            }
            str.validate(args);
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

        int is_value = 0;
        const final char cValueOpen = '"';
        const final char cValueClose = '"';
        const final char cValueOpen2 = '`';
        const final char cValueClose2 = '`';

        if (curChar == cValueOpen) {
            //parse a VALUE; VALUEs must end with another '"'
            //if there's no closing '"', then the user is out of luck
            //(this needs a better error handling rule)
            next();
            is_value = 1;
        } else if (curChar == cValueOpen2) {
            next();
            is_value = 2;
        }

        //if not a value: any chars that come now must form ID tokens
        //(the error handling relies on it)

        char[] curstr = "";
        Position strstart = curpos;

        void val_copy(Position until) {
            char[] stuff = copyOut(strstart, until);
            curstr ~= stuff;
            strstart = curpos;
        }

        for (;;) {
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
                if (curChar == cValueClose2) {
                    break;
                } else {
                    if (curChar == '\r') {
                        //remove windows CR
                        next();
                        val_copy(curpos);
                        continue;
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
                char[] fmt = "x{:x2}";
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
        char[] str;
        char[] comm;
        char[] waste, waste2;
        char[] id;

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
            char[] waste, morewaste;

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

private bool test_error;

ConfigNode debugParseFile(char[] f) {
    void err(char[] msg) {
        Trace.formatln("configfile unittest: {}", msg);
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

char[] t5 =
`styles {
    + "*" {
        + "highlight-alpha" = "0"
    }
    + "/w-button" {
        + "highlight-alpha" = "0.5"
    }
}`;

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

    assert (!test_error);
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


//for waste-of-time stuff
unittest {
    struct Sub {
        int a;
        float b;
    }

    struct X {
        const cAttributes = "uh?,var";
        int var;
        short uh;
        bool var2;
        float varz;
        Sub sub;
    }

    int var;
    bool v2;
    float z;
    Sub s;
    X y;

    ConfigNode foo = new ConfigNode();
    foo["var"] = "123";
    foo["var2"] = "true";
    foo["varz"] = "0.5";
    auto sub = foo.add("sub");
    sub["a"] = "456";
    sub["b"] = "2.0";
    foo.readAll(&var, "var", &v2, "var2", &z, "varz", &s, "sub");
    foo.read!(X)(&y);

    assert(var == 123 && v2 == true && z == 0.5f);
    assert(y.var == 123 && y.var2 == true && y.varz == 0.5f);
    assert(s.a == 456 && s.b == 2.0f);
    assert(y.sub.a == 456 && y.sub.b == 2.0f);
}

unittest {
    auto t = new ConfigNode();
    t.setCurValue!(int)(1234);
    assert(t.value == "1234");
}
