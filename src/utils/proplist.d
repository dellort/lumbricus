//simple settings list (emphasis on simplicity... almost)
//actually, it's a tree (PropertyList + PropertyValue)
//no boxes/variants, no TypeInfos, no templates (except some accessor functions)
//(NOTE: I failed: the implementation [but not the interface] uses templates)
module utils.proplist;

import utils.misc;
import str = utils.string;
import tango.core.Traits : isIntegerType, isRealType, ParameterTupleOf;
import tango.util.Convert : to, ConversionException;

class PropertyException : Exception {
    this(PropertyNode from, char[] msg) {
        super(myformat("{} (at '{}')", msg, from.path()));
    }
}
class InvalidValue : PropertyException {
    this(PropertyNode n, char[] m) { super(n, m); }
}
class PropertyNotFound : PropertyException {
    this(PropertyNode n, char[] path, bool nolist = false, bool noval = false) {
        char[] more;
        if (nolist) more = "; not a list";
        if (noval) more = "; not a value";
        super(n, myformat("path: '{}'{}", path, more));
    }
}

const char cPropertyPathSep = '.';


class PropertyNode {
    protected {
        //position in property tree
        PropertyList mParent;
        char[] mName = "unnamed";

        char[][char[]] mHints;

        //notification handling (doing this well is the point of this module)
        int mSilent;        //if >0, don't call listeners
        bool mChangeFlag;   //only useful when mSilent > 0
        PropertyNode[] mChangedChildren; //set of changed children
        bool mNotifying;    //true while calling listeners (for debugging)
        alias void delegate(PropertyNode) Listener;
        Listener[] mListeners;
    }

    final PropertyList parent() { return mParent; }
    final char[] name() { return mName; }

    final void name(char[] a_name) {
        if (mParent) {
            if (mParent.find(a_name))
                throw new PropertyException(this, "rename would lead to "
                    "double entry '" ~ a_name ~ "'");
        }
        mName = a_name;
        changed();
    }

    //fully qualified path
    //if rel is specified, the path stops at rel, and rel.name and everything
    //  before it will not be included in the path (only if rel is a parent;
    //  otherwise it's as if rel is null)
    final char[] path(PropertyNode rel = null) {
        char[] path;
        if (parent && parent !is rel)
            path = parent.path(rel) ~ cPropertyPathSep;
        path ~= name;
        return path;
    }

    //a node is either a PropertyValue or a PropertyList
    //only PropertyList have sub properties
    //only PropertyValue has a real string representation
    final bool isValue() {
        return !!cast(PropertyValue)this;
    }

    //return this casted to PropertyValue, or raise an error
    final PropertyValue asValue() {
        auto r = cast(PropertyValue)this;
        if (!r)
            throw new PropertyNotFound(this, "-", false, true);
        return r;
    }
    //return this casted to PropertyList, or raise an error
    final PropertyList asList() {
        auto r = cast(PropertyList)this;
        if (!r)
            throw new PropertyNotFound(this, "-", true, false);
        return r;
    }

    //hints are additional attributes that can be associated with a node, aren't
    //  interpreted by the property code, and are for free use
    //e.g. the hint "help" for human readable per value help texts
    final char[] getHint(char[] name, char[] def = "") {
        if (auto p = name in mHints) {
            return *p;
        }
        return def;
    }

    final void setHint(char[] name, char[] value) {
        mHints[name] = value;
    }

    final char[] help() { return getHint("help"); }
    final void help(char[] h) { setHint("help", h); }

    //inhibit change notifiers temporarily (use with care)
    //if released, all listeners, which were inhibited, are called
    //change events never "disappear" (although they may be coalesced)
    void changesStart() {
        mSilent++;
        if (auto list = cast(PropertyList)this) {
            foreach (sub; list) {
                sub.changesStart();
            }
        }
    }
    void changesEnd() {
        if (mSilent == 0)
            throw new Exception("changesEnd(): underflow; nesting error?");
        mSilent--;
        if (mSilent == 0) {
            if (auto list = cast(PropertyList)this) {
                foreach (sub; list) {
                    sub.changesEnd();
                }
            }
            if (mChangeFlag) {
                while (mChangedChildren.length) {
                    //(try to iterate the array in a safe way; whatever)
                    auto c = mChangedChildren[$-1];
                    mChangedChildren.length = mChangedChildren.length - 1;
                    callListeners(c);
                }
                callListeners(this);
            }
        }
    }

    private void callListeners(PropertyNode c) {
        assert(!mNotifying);
        mNotifying = true;
        scope (exit) mNotifying = false;
        mChangeFlag = false;
        foreach (l; mListeners) {
            l(c);
        }
    }

    //raise change notification (unless it's inhibited)
    private void changed() {
        changedSub(this);
    }

    //node must be some transitive child (or this)
    private void changedSub(PropertyNode node) {
        if (mSilent > 0) {
            mChangeFlag = true;
            if (node !is this) {
                foreach (s; mChangedChildren) {
                    //bail out if this was already notified
                    if (s is node)
                        return;
                }
                mChangedChildren ~= node;
            }
        } else {
            callListeners(node);
        }
        if (mParent)
            mParent.changedSub(node);
    }

    //change notification; all listeners are called if something changes
    //a PropertyValue calls its listener after the actual value changes
    //a PropertyList calls the notifiers after any (transitive) sub-value is
    //  changed, or after a property is added or removed
    //"inner" listeners are called first; e.g. children before parent, value
    //  before owning list, first registered listeners before later registered
    //  ones
    //parameters for the callbacks:
    //  1 = always "this" (possibly casted)
    //  2 = the changed child node (may be "this", depending from the situation)
    //it never happens that a callback isn't called because of the delegate's
    //  parameter types; sometimes null may be passed (when the cast fails)
    void addListener(void delegate() cb) { listener(cb); }
    void addListener(void delegate(PropertyNode) cb) { listener(cb); }
    void addListener(void delegate(PropertyNode, PropertyNode) cb)
        { listener(cb); }
    void addListener(void delegate(PropertyNode, PropertyValue) cb)
        { listener(cb); }
    void addListener(void delegate(PropertyValue) cb) { listener(cb); }

    private void listener(T)(T a_cb) {
        struct Burb {
            PropertyNode _this;
            T cb;
            void call(PropertyNode child) {
                ParameterTupleOf!(T) p;
                foreach (int idx, i; p) {
                    PropertyNode x = (idx == 0) ? _this : child;
                    typeof(i) r;
                    static if (is(typeof(i) == PropertyValue)) {
                        r = cast(PropertyValue)x;
                        //never call when cast failed
                        if (x && !r)
                            return;
                    } else {
                        r = x;
                    }
                    p[idx] = r;
                }
                cb(p);
            }
        }
        auto c = new Burb;
        c._this = this;
        c.cb = a_cb;
        mListeners ~= &c.call;
    }

    //validation failed
    protected void invalidValue() {
        throw new InvalidValue(this, "invalid value");
    }

    //static set/get convenience interface
    //it's not meant to be extensible to every static type that could exist
    //if there are type incompatibilities, an InvalidValue exception is raised
    void setval(T)(T v) {
        void error() {
            throw new InvalidValue(this, "setval(T) failed; T="~T.stringof);
        }

        //yyy decide struct path on whether it's a list, or something

        alias PropertyValueT!(ReduceType!(T)) Handler;
        if (auto h = cast(Handler)this) {
            h.set(v);
            return;
        }

        static if (is(T == struct)) {
            auto l = asList();
            //xxx on failure, it writes some values and some not
            changesStart();
            scope(exit) changesEnd();
            foreach (int idx, i; v.tupleof) {
                const item = structProcName(v.tupleof[idx].stringof);
                auto sub = l.find(item);
                if (!sub)
                    error();
                sub.setval(i);
            }
            return;
        }

        static if (is(T : char[])) {
            //will throw various exceptions on failure
            asValue.setAsString(v);
            return;
        }

        error();
    }
    //if incompatible type, don't touch v and return false
    //else, write value to v and return true
    //using a struct will succeed if all struct members are present
    bool getval_maybe(T)(ref T v) {
        alias PropertyValueT!(ReduceType!(T)) Handler;
        if (auto h = cast(Handler)this) {
            v = h.get();
            return true;
        }

        static if (is(T == struct)) {
            if (auto l = cast(PropertyList)this) {
                T res;
                foreach (int idx, _; res.tupleof) {
                    const item = structProcName(res.tupleof[idx].stringof);
                    auto sub = l.find(item);
                    if (!sub)
                        return false;
                    if (!sub.getval_maybe(res.tupleof[idx]))
                        return false;
                }
                v = res;
                return true;
            }
        }

        //finally try as string, if it is one
        static if (is(T : char[])) {
            if (auto val = cast(PropertyValue)this) {
                v = val.asString();
                return true;
            }
        }

        return false;
    }
    //as getval_maybe; but raise an exception on failure
    T getval(T)() {
        T res;
        if (!getval_maybe(res))
            throw new InvalidValue(this, "getval(T) failed; T="~T.stringof);
        return res;
    }
    //as getval_maybe; but return a default value on failure
    T getval_def(T)(T def = T.init) {
        getval_maybe(def);
        return def;
    }

    //versions of setval, getval_maybe, getval, getval_def with path parameter
    //I didn't know how to name them; feel free to improve (esp. getT)
    void set(T)(char[] path, T v) {
        asList.sub(path).setval(v);
    }
    bool get_maybe(T)(char[] path, ref T v) {
        PropertyList list = cast(PropertyList)this;
        if (!list)
            return false;
        PropertyNode s = list.find(path);
        if (!s)
            return false;
        return s.getval_maybe(v);
    }
    T getT(T)(char[] path) {
        return asList.sub(path).getval!(T)();
    }
    T get_def(T)(char[] path, T def = T.init) {
        getval_maybe(path, def);
        return def;
    }


    //listeners and the parent of the root are not copied
    PropertyNode dup() {
        //xxx: somewhat dirty trick to create new instances
        //subclasses must be instantiateable with "new T();" for it to work;
        //  they must have default/standard ctor!!!
        //  but it saves a lot of stupid code
        auto r = castStrict!(PropertyNode)(this.classinfo.create());
        assert(!!r);
        r.mName = mName;
        foreach (k, v; mHints) {
            r.mHints[k] = v;
        }
        r.copyFrom(this);
        return r;
    }

    //copy the contents from the given node to "this"; the types (and existence)
    //  of all nodes must be the same (all nodes in "from" must exist in "this",
    //  but "this" can have nodes that are not in "from")
    abstract void copyFrom(PropertyNode from);

    //revert to default values
    abstract void reset();
}

//represent an "atomic" value (== not a PropertyList)
abstract class PropertyValue : PropertyNode {

    final override void reset() {
        doReset();
        notifyChange(false);
    }

    //notification for value changes
    protected void notifyChange(bool set = true) {
        changed();
    }

    override void copyFrom(PropertyNode from) {
        PropertyValue v = from.asValue();
        //xxx not quite kosher
        if (v.classinfo !is this.classinfo)
            throw new PropertyException(this, "copyFrom(): incompatible types");
        doCopyFrom(v);
        changed();
    }

    //user readable (and even editable) representation of the value
    //can be read back into the property by setString()
    abstract char[] asString();
    //same, but for the default value
    abstract char[] asStringDefault();

    //may throw InvalidValue (on parse or validation errors)
    abstract void setAsString(char[] s);

    //just set the default value; caller cares about change notification etc.
    protected abstract void doReset();

    //just copy the actual data members; logic is done by copyFrom()
    protected abstract void doCopyFrom(PropertyValue source);
}

class PropertyString : PropertyValue {
    private char[] mValue, mDefaultValue;

    override char[] asString() { return mValue; }
    override char[] asStringDefault() { return mDefaultValue; }
    override void setAsString(char[] s) { mValue = s; notifyChange(); }
    override void doReset() { mValue = mDefaultValue; }

    //meh
    void setDefault(char[] s) {
        mDefaultValue = s;
        notifyChange(false);
    }

    override void doCopyFrom(PropertyValue source) {
        auto s = castStrict!(PropertyString)(source);
        mValue = s.mValue;
        mDefaultValue = s.mDefaultValue;
    }
}

//any class that allows reading a "direct" data type should derive from this
//that means PropertyNode.getval(T)() etc. can use them
//note that all properties support strings anyway (templated code can use
//  PropertyNode getval()/setval() to avoid special cases)
//NOTE: of course this doesn't handle "similar" types; e.g. PropertyInt only
//  supports long, and not int, short, or anything else; getval()/setval()
//  take care of this, and PropertyValueT!(short) will never be used
//  (could "solve" this by turning PropertyValueT into a templated interface,
//   and make PropertyInt implement PropertyValueT!(int), PropertyValueT!(long),
//   etc....)
abstract class PropertyValueT(T) : PropertyValue {
abstract:
    void setDefault(T def);
    void set(T v);
    T get();
    T getDefault();
}

template ValueTypeOf(T : PropertyValue) {
    static if (is(T == PropertyString)) {
        alias char[] ValueTypeOf;
    } else {
        alias typeof((cast(T)null).get()) ValueTypeOf;
    }
}

//wrapper for values of various data types
//some sort of low-rate Variant (didn't use Variant because equality tests at
//  runtime are iffy, e.g. an int Variant with value 1 != long Variant with
//  value 1; at least it seemed so; at least with tango.core.Variant)
//this is just an internal hack to reduce typing, pretend it doesn't exist
//users should either use the generic PropertyValue, or the aliases like
//  PropertyInt, PropertyString, etc.
//if it gets all to inconvenient and messy, use tango.core.Variant (and solve
//  its associated problems)
//if you want to use it from outside this module, think of something else, like
//  registering with a TypeInfo, or using template-free API functions
private class PropertyValueT_hurf(T) : PropertyValueT!(T) {
    private {
        T mValue;
        T mDefaultValue;
    }

    //only for intialization
    void setDefault(T def) {
        mDefaultValue = def;
        reset();
    }

    override void doReset() {
        mValue = mDefaultValue;
    }

    void set(T v) {
        if (v == mValue)
            return;
        mValue = v;
        notifyChange();
    }

    T get() {
        return mValue;
    }

    T getDefault() {
        return mDefaultValue;
    }

    override char[] asString() {
        return myformat("{}", get());
    }
    override char[] asStringDefault() {
        return myformat("{}", getDefault());
    }

    override void setAsString(char[] s) {
        try {
            //to!() accepts empty strings (???)
            if (s.length == 0)
                throw new ConversionException("empty string");
            set(to!(typeof(mValue))(s));
        } catch (ConversionException e) {
            invalidValue();
        }
    }

    override void doCopyFrom(PropertyValue source) {
        auto s = cast(typeof(this))source;
        assert(!!s);
        mValue = s.mValue;
        mDefaultValue = s.mDefaultValue;
    }
}

alias long Integer; //doesn't work with full range of ulong
alias double Float; //don't care about type real

//replaces T by types big enough to hold the other "sub" types
template ReduceType(T) {
    static if (isIntegerType!(T)) {
        alias Integer ReduceType;
    } else static if (isRealType!(T)) {
        alias Float ReduceType;
    } else {
        alias T ReduceType;
    }
}

//use these aliases, if you must access the stuff directly
alias PropertyValueT_hurf!(Integer) PropertyInt;
alias PropertyValueT_hurf!(Float) PropertyFloat;
alias PropertyValueT_hurf!(bool) PropertyBool;
class PropertyPercent : PropertyFloat {};  //0.0 to 1.0

//for PropertyList.add(T)
template CreateProperty(T) {
    static if (isIntegerType!(T)) {
        alias PropertyInt CreateProperty;
    } else static if (isRealType!(T)) {
        alias PropertyFloat CreateProperty;
    } else static if (is(T : char[])) {
        alias PropertyString CreateProperty;
    } else static if (is(T : bool)) {
        alias PropertyBool CreateProperty;
    } else {
        static assert(false, "type unsupported: "~T.stringof);
    }
}

//value is one of multiple choices (like an enum value)
class PropertyChoice : PropertyValue {
    private {
        Choice[] mValues;
        //indices into mValues
        int mDefault = -1;
        int mCurrent = -1;

        struct Choice {
            char[] value;
            int int_value;
        }
    }

    char[][] choices() {
        char[][] res;
        foreach (c; mValues) {
            res ~= c.value;
        }
        return res;
    }

    void add(char[] newchoice, int int_value = -1) {
        if (find(newchoice, false) >= 0)
            invalidValue(); //double entry
        mValues ~= Choice(newchoice, int_value);
        int pre = cur;
        if (mDefault < 0)
            mDefault = 0;
        notifyChange(cur != pre);
    }

    private int find(char[] s, bool force_valid) {
        foreach (int i, c; mValues) {
            if (c.value == s)
                return i;
        }
        if (force_valid)
            invalidValue();
        return -1;
    }

    bool isValidChoice(char[] s) {
        return find(s, false) >= 0;
    }

    private int cur() {
        return mCurrent >= 0 ? mCurrent : mDefault;
    }

    int asInteger() {
        return cur >= 0 ? mValues[cur].int_value : -1;
    }
    int asIndex() {
        return cur;
    }

    override char[] asString() {
        return cur >= 0 ? mValues[cur].value : "";
    }

    override char[] asStringDefault() {
        return mDefault >= 0 ? mValues[mDefault].value : "";
    }

    void setAsString(char[] s) {
        mCurrent = find(s, true);;
        notifyChange();
    }

    void setAsStringDefault(char[] s) {
        mDefault = find(s, true);
        notifyChange(false);
    }

    override void doReset() {
        mCurrent = mDefault;
    }

    override void doCopyFrom(PropertyValue source) {
        auto s = castStrict!(typeof(this))(source);
        mValues = s.mValues.dup;
        mCurrent = s.mCurrent;
        mDefault = s.mDefault;
    }
}

//pseudo value for change notification (may be useful hen binding a PropertyList
//  to a GUI)
class PropertyCommand : PropertyValue {
    private {
    }

    void delegate() onCommand;

    void touch() {
        notifyChange();
        if (onCommand)
            onCommand();
    }

    override char[] asString() {
        return "[command]";
    }

    override char[] asStringDefault() {
        return "(default)";
    }

    override void setAsString(char[] s) {
        //touch();
        notifyChange();
    }

    override void doReset() {
    }

    override void doCopyFrom(PropertyValue source) {
        auto other = castStrict!(PropertyCommand)(source);
    }
}

//it is explicitly allowed to add, remove or change entry definitions at runtime
final class PropertyList : PropertyNode {
    private {
        PropertyNode[] mValues;
    }

    //add function with static types for convenience
    //like PropertyNode.set/get, reduces T to an appropriate value type
    //if T is a struct, a PropertyList with add() for each struct member is
    //  created
    PropertyNode add(T)(char[] name, T defvalue = T.init, char[] help = null) {
        static if (is(T == struct)) {
            auto h = new PropertyList();
            h.addMembers!(T)(defvalue);
        } else {
            //fails horribly when T unsupported
            auto h = new CreateProperty!(T)();
            h.setDefault(defvalue);
        }
        addNode(h, name, help);
        return h;
    }

    //like above, but specify the PropertyValue type to use
    PropertyNode add(T : PropertyValue)(char[] name,
        ValueTypeOf!(T) defvalue = ValueTypeOf!(T).init, char[] help = null)
    {
        auto h = new T();
        h.setDefault(defvalue);
        addNode(h, name, help);
        return h;
    }

    //add members of the passed struct T as properties
    void addMembers(T)(T defaults = T.init) {
        static assert(is(T == struct));
        foreach (int idx, t; defaults.tupleof) {
            add(structProcName(defaults.tupleof[idx].stringof), t);
        }
    }

    private void addNode(PropertyNode node, char[] name, char[] help) {
        node.help = help;
        node.name = name;
        addNode(node);
    }

    void addNode(PropertyNode node) {
        assert(!!node);
        assert(!node.mParent, "node already added to a list");
        if (find(node.name))
            throw new Exception("property already exists: "~node.name);
        //patch up change level; needed when adding nodes while changes are
        //  inhibited
        //xxx be sure to do the same when nodes are removed
        for (int n = 0; n < mSilent; n++)
            node.changesStart();
        mValues ~= node;
        node.mParent = this;
        node.changed();
    }

    PropertyList addList(char[] name) {
        auto l = new PropertyList();
        l.name = name;
        addNode(l);
        return l;
    }

    //find sub node; null on failure
    //NOTE: parses the name for path separators (".")
    PropertyNode find(char[] name) {
        try {
            return sub(name);
        } catch (PropertyNotFound e) {
            return null;
        }
    }

    //like find(), but raise an exception if not found
    PropertyNode sub(char[] name) {
        auto res = str.split2(name, cPropertyPathSep);
        char[] base = res[0];
        char[] rest = res[1];
        foreach (v; mValues) {
            if (v.name == base) {
                if (rest.length) {
                    assert(rest[0] == cPropertyPathSep);
                    rest = rest[1..$];
                    auto list = cast(PropertyList)v;
                    if (!list)
                        throw new PropertyNotFound(this, name, true);
                    return list.sub(rest);
                } else {
                    return v;
                }
            }
        }
        throw new PropertyNotFound(this, name);
    }
    //like sub(), but return a PropertyList, else exception
    PropertyList sublist(char[] name) {
        auto res = sub(name);
        auto list = cast(PropertyList)res;
        if (!list)
            throw new PropertyNotFound(this, name, true);
        return list;
    }

    override void reset() {
        //just recurse into sub items and revert them
        changesStart();
        scope(exit) changesEnd();
        foreach (s; this) {
            s.reset();
        }
    }

    PropertyNode[] values() {
        return mValues.dup;
    }

    int opApply(int delegate(ref PropertyNode) cb) {
        foreach (v; mValues) {
            int res = cb(v);
            if (res)
                return res;
        }
        return 0;
    }

    override void copyFrom(PropertyNode from) {
        changesStart();
        scope(exit) changesEnd();
        PropertyList list = from.asList();
        foreach (sub; list) {
            auto other = find(sub.name);
            if (!other) {
                addNode(sub.dup());
            } else {
                other.copyFrom(sub);
            }
        }
    }

    //output key-value list for debugging
    debug void dump(void delegate(char[]) sink) {
        void dump(PropertyNode nd) {
            if (nd.isValue()) {
                auto v = nd.asValue();
                sink(myformat("{} = '{}'\n", v.path, v.asString()));
            } else {
                foreach (s; nd.asList()) {
                    dump(s);
                }
            }
        }
        dump(this);
    }
}

version(none)
unittest {
    auto list = new PropertyList();
    list.name = "root";
    list.add!(int)("foo", 34);
    Trace.formatln("{} == 34", list.sub("foo").getval!(int)());
    assert(list.sub("foo").path() == "root.foo");
    assert(list.sub("foo").path(list) == "foo");
    struct Foo {
        int a = 12;
        char[] b = "abc";
        bool c = true;
    }
    auto c = new PropertyChoice();
    c.name = "choice";
    c.add("bla");
    c.add("blu");
    c.add("blergh");
    list.addNode(c);
    Trace.formatln("{} = bla", list.sub("choice").asValue.asString());
    list.sub("choice").asValue.setAsString("blergh");
    Trace.formatln("{} = blergh", list.sub("choice").asValue.asString());
    list.add!(Foo)("sub");
    auto sub = list.sublist("sub");
    Foo x = Foo(0,"",false);
    x = sub.getval!(Foo)();
    Trace.formatln("{}=12, {}='abc', {}=true", x.a, x.b, x.c);
    auto hurf = new PropertyCommand();
    hurf.name = "command1";
    list.addNode(hurf);
    void notify1(PropertyNode owner, PropertyValue val) {
        Trace.formatln("change '{}' to '{}'", val.path(),
            val.asString());
    }
    void notify2(PropertyNode owner) {
        Trace.formatln("change node '{}'", owner.path());
    }
    list.addListener(&notify1);
    list.addListener(&notify2);
    Trace.formatln("changes start");
    list.changesStart();
    list.sub("sub.a").setval(666);
    list.sub("sub.a").setval(2);
    list.sub("sub.b").setval!(char[])("huhu");
    list.sub("sub.c").asValue.setAsString("false");
    auto t1 = list.sub("foo");
    t1.changesStart();
    t1.setval(222);
    auto t2 = castStrict!(PropertyCommand)(list.sub("command1"));
    t2.touch();
    t2.touch();
    t1.changesEnd();
    Trace.formatln("changes end");
    list.changesEnd();
    void sink(char[] s) {
        Trace.format("{}", s);
    }
    list.dump(&sink);
    auto list2 = list.dup().asList();
    list2.dump(&sink);
    auto list3 = new PropertyList();
    list3.name = "list3";
    list3.copyFrom(list2);
    list3.dump(&sink);
    list3.sub("sub.a").reset();
    list2.sub("sub.b").reset();
    list3.dump(&sink);
}
