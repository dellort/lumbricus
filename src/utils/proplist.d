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
        super(myformat("{} (at '{}')", msg, from.fullPath()));
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

    //xxx doesn't do anything if this leads to multiple nodes with same name
    final void name(char[] name) {
        mName = name;
        changed();
    }

    //fully qualified path
    final char[] fullPath() {
        char[] path;
        if (parent)
            path = parent.fullPath() ~ cPropertyPathSep;
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

    //inhibit change notifiers temporarily
    //if released, all listeners are called
    //(use with care)
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
        } else {
            auto h = cast(MapProperty!(T))(asValue());
            if (!h) error();
            h.set(v);
        }
    }
    //if incompatible type, don't touch v and return false
    //else, write value to v and return true
    //using a struct will succeed if all struct members are present
    bool getval_maybe(T)(ref T v) {
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
        } else {
            if (auto h = cast(MapProperty!(T))this) {
                v = h.get();
                return true;
            }
            return false;
        }
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
        r.copyFrom(this, true, true);
        return r;
    }

    //copy the contents from the given node to "this"; the types (and existence)
    //  of all nodes must be the same (all nodes in "from" must exist in "this",
    //  but "this" can have nodes that are not in "from")
    //definition of "set": see PropertyValue.wasSet()
    //copy_unset: if false, a value is only copied if it was set in "from" ();
    //overwrite_set: if false, a value is only copied if wasn't set in "this"
    abstract void copyFrom(PropertyNode from, bool copy_unset = false,
        bool overwrite_set = true);

    //revert to default values
    //will set wasSet to false (for PropertyValues)
    abstract void reset();
}

//represent an "atomic" value (== not a PropertyList)
class PropertyValue : PropertyNode {
    private {
        bool mWasSet;
    }

    //return if the property was written by the user
    //NOTE: the actual value of the property can be the same as its default
    //  value even if wasSet returns true (in this case, the user set it
    //  manually to the default value); only reset() will clear the flag
    final bool wasSet() {
        return mWasSet;
    }

    final override void reset() {
        doReset();
        mWasSet = false;
        notifyChange(false);
    }

    //notification for value changes
    protected void notifyChange(bool set = true) {
        if (set)
            mWasSet = true;
        changed();
    }

    override void copyFrom(PropertyNode from, bool copy_unset = false,
        bool overwrite_set = true)
    {
        PropertyValue v = from.asValue();
        //xxx not quite kosher
        if (v.classinfo !is this.classinfo)
            throw new PropertyException(this, "copyFrom(): incompatible types");
        //do as copyFrom() defines to handle overwriting
        if (!copy_unset && !v.wasSet())
            return;
        if (!overwrite_set && this.wasSet())
            return;
        //copy
        mWasSet = v.mWasSet;
        doCopyFrom(v);
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
private class PropertyValueT(T) : PropertyValue {
    private {
        T mValue;
        T mDefaultValue;

        //xxx template spaghetti programming
        const isString = is(T : char[]);
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
        static if (isString) {
            set(s);
        } else {
            try {
                //to!() accepts empty strings (???)
                if (s.length == 0)
                    throw new ConversionException("empty string");
                set(to!(typeof(mValue))(s));
            } catch (ConversionException e) {
                invalidValue();
            }
        }
    }

    override void doCopyFrom(PropertyValue source) {
        auto s = cast(typeof(this))source;
        assert(!!s);
        mValue = s.mValue;
        mDefaultValue = s.mDefaultValue;
    }
}

//types big enough to hold the other "sub" types
alias long Integer; //doesn't work with full range of ulong
alias double Float; //don't care about type real

//use these aliases
alias PropertyValueT!(Integer) PropertyInt;
alias PropertyValueT!(Float) PropertyFloat;
alias PropertyValueT!(char[]) PropertyString;
alias PropertyValueT!(bool) PropertyBool;

//map static type to handler class (which correspond to the aliases above)
template MapProperty(T) {
    static if (isIntegerType!(T)) {
        alias PropertyInt MapProperty;
    } else static if (isRealType!(T)) {
        alias PropertyFloat MapProperty;
    } else static if (is(T : char[])) {
        alias PropertyString MapProperty;
    } else static if (is(T : bool)) {
        alias PropertyBool MapProperty;
    } else static if (is(T == struct)) {
        //not really
        alias PropertyList MapProperty;
    } else {
        static assert(false, "unknown type: " ~ T.stringof);
    }
}

//pseudo value for change notification (may be useful hen binding a PropertyList
//  to a GUI)
class PropertyCommand : PropertyValue {
    private {
        //this is just a timestamp, not a real value
        //must be increased on every touch()
        //maybe it's better not to use it; user should rely on change events
        long mCounter;
    }

    void touch() {
        mCounter++;
        notifyChange();
    }

    override char[] asString() {
        return myformat("command(#{})", mCounter);
    }

    override char[] asStringDefault() {
        return "(default)";
    }

    override void setAsString(char[] s) {
        touch();
    }

    override void doReset() {
        mCounter = 0;
    }

    override void doCopyFrom(PropertyValue source) {
        auto other = castStrict!(PropertyCommand)(source);
        //kosher?
        mCounter = 0; //max(other.mCounter, mCounter) + 1;
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
        alias MapProperty!(T) Handler;
        auto h = new Handler();
        static if (is(T == struct)) {
            //(Handler is PropertyList)
            foreach (int idx, t; defvalue.tupleof) {
                h.add(structProcName(defvalue.tupleof[idx].stringof), t);
            }
        } else {
            h.setDefault(defvalue);
        }
        h.help = help;
        h.name = name;
        addNode(h);
        return h;
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

    //find sub node; null on failure
    //NOTE: parses the name for path separators (".")
    PropertyNode find(char[] name) {
        try {
            return get(name);
        } catch (PropertyNotFound e) {
            return null;
        }
    }

    //like find(), but raise an exception if not found
    PropertyNode get(char[] name) {
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
                    return list.get(rest);
                } else {
                    return v;
                }
            }
        }
        throw new PropertyNotFound(this, name);
    }
    //like get(), but return a PropertyList, else exception
    PropertyList getlist(char[] name) {
        auto res = get(name);
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

    override void copyFrom(PropertyNode from, bool copy_unset = false,
        bool overwrite_set = true)
    {
        changesStart();
        scope(exit) changesEnd();
        PropertyList list = from.asList();
        foreach (sub; list) {
            auto other = find(sub.name);
            if (!other) {
                addNode(sub.dup());
            } else {
                other.copyFrom(sub, copy_unset, overwrite_set);
            }
        }
    }

    //output key-value list for debugging
    debug void dump(void delegate(char[]) sink) {
        void dump(PropertyNode nd) {
            if (nd.isValue()) {
                auto v = nd.asValue();
                sink(myformat("{} = '{}'\n", v.fullPath, v.asString()));
            } else {
                foreach (s; nd.asList()) {
                    dump(s);
                }
            }
        }
        dump(this);
    }
}

unittest {
    auto list = new PropertyList();
    list.name = "root";
    list.add!(int)("foo", 34);
    Trace.formatln("{} == 34", list.get("foo").getval!(int)());
    struct Foo {
        int a = 12;
        char[] b = "abc";
        bool c = true;
    }
    list.add!(Foo)("sub");
    auto sub = list.getlist("sub");
    Foo x = Foo(0,"",false);
    x = sub.getval!(Foo)();
    Trace.formatln("{}=12, {}='abc', {}=true", x.a, x.b, x.c);
    auto hurf = new PropertyCommand();
    hurf.name = "command1";
    list.addNode(hurf);
    void notify1(PropertyNode owner, PropertyValue val) {
        Trace.formatln("change '{}' to '{}'", val.fullPath(),
            val.asString());
    }
    void notify2(PropertyNode owner) {
        Trace.formatln("change node '{}'", owner.fullPath());
    }
    list.addListener(&notify1);
    list.addListener(&notify2);
    Trace.formatln("changes start");
    list.changesStart();
    list.get("sub.a").setval(666);
    list.get("sub.a").setval(2);
    list.get("sub.b").setval("huhu");
    list.get("sub.c").asValue.setAsString("false");
    auto t1 = list.get("foo");
    t1.changesStart();
    t1.setval(222);
    auto t2 = castStrict!(PropertyCommand)(list.get("command1"));
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
    list3.get("sub.a").reset();
    list2.get("sub.b").reset();
    list3.dump(&sink);
}
