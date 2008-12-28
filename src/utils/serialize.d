module utils.serialize;

import utils.configfile;
import utils.reflection;
import utils.misc;
import utils.queue;

import str = std.string;

debug import std.stdio : writefln;

debug = CountClasses;

/+
Not-so-obvious limitations of the implemented serialization mechanism:
- (Obvious one) All classes in the serialized object graph must be registered.
- After serialization, arrays that pointed to the same data don't do that
  anymore. E.g.:
    class A {
        int[] x;
        int[] y;
    }
    A a = new A();
    a.x = [1,2,3];
    a.y = a.x;
    assert(a.x.ptr is a.y.ptr); //of course succeeds
    serialize(a);
    A b = deserialize();
    assert(b.x == b.y);         //succeeds
    assert(b.x.ptr is b.y.ptr); //fails
  Reason: referential integrity is maintained only across objects. Arrays are
    simply copied. It would be too complicated, especially when array slices are
    involved. If slices are disregarded, it wouldn't be that hard to handle
    arrays correctly, but because so much data is in arrays (e.g. strings), it
    probably would be rather inefficient.
  The same is true for maps (aka AAs).
  xxx: because AA variables either point to the same actual AA or are distinct,
       these might be simpler to implement; but you somehow have to extract the
       reference to the actual AA from the AA variable?
- Recursive arrays/maps that point to themselves don't work. Example:
    struct S {
        S[] guu;
    }
    S[] h;
    h.length = 1;
    h[0].guu = h;
  This will lead to a stack overflow when trying to serialize a class containing
  this array. Same reason as above.
- Enums are written as casted integers. Not doing so would require the user to
  register a name for each enum item.
  xxx: maybe one could at least add a check for .min and .max
- Delegates work, but all methods have to be registered with a name. This also
  means that all classes, that contain such methods, must be reflectable.
- Not supported at all: pointers, function pointers, typedefs, unions, void[].
- D standard classes like TypeInfo or ClassInfo are not supported.
  (Although they could, under certain conditions.)
+/

//type informations: mostly the stuff from utils.reflection, and possibly hooks
// for custom serializtion of special object types
class SerializeContext {
    private {
        Types mTypes;
    }

    this(Types a_types) {
        mTypes = a_types;
    }
}

typedef Exception SerializeError;

//base class for serializers/deserializers
//"external" objects: objects which aren't serialized, but which are still
// referenced by serialized objects. these objects must be added manually before
// serialization or deserialization, and they are referenced by name
class SerializeBase {
    private {
        SerializeContext mCtx;
        char[][Object] mExternals;
        Object[char[]] mExternalsReverse;
        ClassInfo[] mIgnored;
    }

    this(SerializeContext a_ctx) {
        mCtx = a_ctx;
    }

    //register external object
    void addExternal(Object o, char[] id) {
        if (o in mExternals || id in mExternalsReverse)
            throw new Exception("external not unique");
        mExternals[o] = id;
        mExternalsReverse[id] = o;
    }

    //this is a hack
    void addIgnoreClass(ClassInfo ignore) {
        mIgnored ~= ignore;
    }

    protected void typeError(SafePtr source, char[] add = "") {
        if (cast(ReferenceType)source.type) {
            Object o = source.toObject();
            if (o)
                throw new SerializeError(str.format("problem with: %s / %s %s",
                    source.type, o.classinfo.name, add));
        }
        throw new SerializeError(str.format("problem with: %s, ti=%s %s",
            source.type, source.type.typeInfo(), add));
    }

    //these functions are here because the inheritance hierarchy is hard to get
    //right (especially with all my ridiculous base classes); maybe interfaces
    //could be used, but these suck, also: templates?

    //several objects can be written sequentially; these can be read in the same
    //order when deserializing (like with a stream)
    //the object can depend from previously written objects (they share they
    //same object graph)
    void writeObject(Object o) {
        assert (false);
    }

    //parallel to writeObject()
    Object readObject() {
        assert (false);
        return null;
    }

    //like readObject(), but cast to T and make failure a deserialization error
    //by default, the result also must be non-null
    T readObjectT(T)(bool can_be_null = false) {
        auto o = readObject();
        T t = cast(T)o;
        if (o && !t)
            throw new SerializeError("unexpected object type");
        if (!o && !can_be_null)
            throw new SerializeError("object is null");
        return t;
    }
}

abstract class SerializeConfig : SerializeBase {
    private {
        ConfigNode mFile;
    }

    this(SerializeContext a_ctx, ConfigNode a_file) {
        super(a_ctx);
        mFile = a_file;
    }

}

class SerializeOutConfig : SerializeConfig {
    private {
        int mIDAlloc;
        int[Object] mObject2Id;
        Queue!(Object) mObjectQueue;
        debug (CountClasses) {
            int[Class] mCounter;
        }
    }

    this(SerializeContext a_ctx) {
        super(a_ctx, new ConfigNode());
        mObjectQueue = new Queue!(Object);
    }

    private bool doWriteNextObject(ConfigNode file) {
        if (mObjectQueue.empty)
            return false;
        Object o = mObjectQueue.pop;
        //(note that ptr actually points to "o", á la "ptr = &o;")
        SafePtr ptr = mCtx.mTypes.ptrOf(o);
        Class klass = mCtx.mTypes.findClass(o);
        if (!klass)
            typeError(ptr, "can't serialize ["~o.toString()~"]");
        debug (CountClasses) {
            auto pc = klass in mCounter;
            if (pc) {
                (*pc)++;
            } else {
                mCounter[klass] = 1;
            }
        }
        auto nid = mObject2Id[o];
        auto node = file.getSubNode(str.format("%d", nid));
        node["type"] = klass.name();
        doWriteMembers(file, node, klass, ptr);
        return true;
    }

    private char[] queueObject(Object o) {
        if (o is null) {
            return "null";
        }
        if (auto pid = o in mObject2Id) {
            return str.format("#%d", *pid);
        }
        if (auto pname = o in mExternals) {
            return "ext#" ~ *pname;
        }
        foreach (i; mIgnored) {
            if (o.classinfo is i)
                return "lolignored";
        }
        auto nid = ++mIDAlloc;
        mObject2Id[o] = nid;
        mObjectQueue.push(o);
        return str.format("#%d", nid);
    }

    private void doWriteMembers(ConfigNode file, ConfigNode cur, Class klass,
        SafePtr ptr)
    {
        assert (!!klass);
        //each class in the inheritance hierarchy gets a node (structs not)
        bool is_struct = !!cast(StructType)klass.type();
        if (is_struct)
            assert (!klass.superClass());
        Class ck = klass;
        while (ck) {
            //(not for structs)
            auto dest = is_struct ? cur : cur.addUnnamedNode();
            ptr.type = ck.type(); //should be safe...
            foreach (ClassMember m; ck.nontransientMembers()) {
                //don't write default values
                if (is_struct || !m.isInit(ptr)) {
                    SafePtr mptr = m.get(ptr);
                    doWriteMember(file, dest, m.name(), mptr);
                }
            }
            ck = ck.superClass();
        }
    }

    private void doWriteMember(ConfigNode file, ConfigNode cur, char[] member,
        SafePtr ptr)
    {
        if (auto et = cast(EnumType)ptr.type) {
            //dirty trick: do as if it was an integer; should be bitcompatible
            //don't try this at home!
            ptr.type = et.underlying();
            //fall through to BaseType
        }
        if (cast(BaseType)ptr.type) {
            cur[member] = convBaseType(ptr);
            return;
        }
        if (cast(ReferenceType)ptr.type) {
            //object references
            cur[member] = queueObject(ptr.toObject());
            return;
        }
        if (auto st = cast(StructType)ptr.type) {
            //write recursively
            Class k = st.klass();
            if (!k)
                typeError(ptr);
            doWriteMembers(file, cur.getSubNode(member), k, ptr);
            return;
        }
        //handle string arrays differently, having them as real arrays is... urgh
        if (ptr.type is mCtx.mTypes.getType!(char[])()) {
            cur[member] = ptr.read!(char[])();
            return;
        }
        //byte[] too, because for game saving, the bitmap is a byte[]
        if (ptr.type is mCtx.mTypes.getType!(byte[])()) {
            cur.setByteArrayValue(member, ptr.read!(byte[]), true);
            return;
        }
        if (auto art = cast(ArrayType)ptr.type) {
            auto sub = cur.getSubNode(member);
            ArrayType.Array arr = art.getArray(ptr);
            sub["length"] = str.format("%s", arr.length);
            for (int i = 0; i < arr.length; i++) {
                SafePtr eptr = arr.get(i);
                doWriteMember(file, sub, str.format("%d", i), eptr);
            }
            return;
        }
        if (auto map = cast(MapType)ptr.type) {
            auto sub = cur.getSubNode(member);
            map.iterate(ptr, (SafePtr key, SafePtr value) {
                auto subsub = sub.addUnnamedNode();
                doWriteMember(file, subsub, "key", key);
                doWriteMember(file, subsub, "value", value);
            });
            return;
        }
        if (auto dg = cast(DelegateType)ptr.type) {
            Object dg_o;
            ClassMethod dg_m;
            if (!mCtx.mTypes.readDelegate(ptr, dg_o, dg_m)) {
                D_Delegate* dgp = cast(D_Delegate*)ptr.ptr;
                //warning: this might crash, if the delegate points to the
                //         stack or a struct; we simply can't tell
                char[] what = "enable version debug to see why";
                debug {
                    writefln("hello, serialize.d might crash here.");
                    what = str.format("dest-class: %s function: %#x",
                        (cast(Object)dgp.ptr).classinfo.name, dgp.funcptr);
                }
                throw new SerializeError("couldn't write delegate, "~what);
            }
            auto sub = cur.getSubNode(member);
            sub["dg_object"] = queueObject(dg_o);
            //sub["dg_method"] = dg_m ?
              //  str.format("%s::%s", dg_m.klass.name, dg_m.name) : "null";
            sub["dg_method"] = dg_m ? dg_m.name : "null";
            return;
        }
        throw new SerializeError("couldn't serialize: "~ptr.type.toString());
    }

    private char[] convBaseType(SafePtr ptr) {
        Type t = ptr.type;
        assert (!!cast(BaseType)t);
        return blergh!(char, byte, ubyte, short, ushort, int, uint, long, ulong,
            float, double, bool)(ptr);
    }

    private char[] blergh(T...)(SafePtr ptr) {
        foreach (x; T) {
            if (ptr.type.typeInfo() is typeid(x)) {
                char[] fmt = "%s";
                static if (is(x == double) || is(x == float))
                    fmt = "%a";
                return str.format(fmt, ptr.read!(x)());
            }
        }
        typeError(ptr, "basetype");
        return "";
    }

    override void writeObject(Object o) {
        ConfigNode cur = mFile.getSubNode("serialized").addUnnamedNode();
        cur["_object"] = queueObject(o);
        while (doWriteNextObject(cur)) {}
    }

    ConfigNode finish() {
        /+
        auto exts = mFile.getSubNode("externals");
        foreach (char[] name; mExternals) {
            exts.setStringValue("", name);
        }
        +/
        debug (CountClasses) {
            printAnnoyingStats();
        }
        return mFile;
    }

    debug (CountClasses)
    private void printAnnoyingStats() {
        struct P {
            int count;
            Class c;
            int opCmp(P* other) {
                return count - other.count;
            }
        }
        P[] list;
        foreach (Class cl, int count; mCounter) {
            list ~= P(count, cl);
        }
        list.sort;
        writefln("Class count:");
        int sum = 0;
        foreach (x; list) {
            writefln("  %4d  %s", x.count, x.c.name);
            sum += x.count;
        }
        writefln("done, sum=%d.", sum);
    }
}

class SerializeInConfig : SerializeConfig {
    private {
        //for each readObject() call
        ConfigNode[] mObjectNodes;
        Object[int] mId2Object;
    }

    this(SerializeContext a_ctx, ConfigNode a_file) {
        super(a_ctx, a_file);
        foreach (ConfigNode node; mFile.getSubNode("serialized")) {
            mObjectNodes ~= node;
        }
    }

    //return an already deserialized object (no on-demand loading)
    private Object getObject(char[] id) {
        if (id == "null") {
            return null;
        }
        if (id == "")
            throw new SerializeError("malformed ID: empty string");
        if (id[0] == '#') {
            int oid = -1;
            try {
                oid = conv.toInt(id[1..$]);
            } catch (conv.ConvError e) {
            } catch (conv.ConvOverflowError e) {
            }
            if (oid == -1)
                throw new SerializeError("malformed ID (2): "~id);
            auto pobj = oid in mId2Object;
            if (!pobj)
                throw new SerializeError("invalid object id (not found): "~id);
            return *pobj;
        }
        if (id.length > 4 && id[0..4] == "ext#") {
            id = id[4..$];
            auto pobj = id in mExternalsReverse;
            if (!pobj)
                throw new SerializeError("external not found: "~id);
            return *pobj;
        }
        throw new SerializeError("malformed ID (3): "~id);
    }

    //deserialize all objects in file
    private void doReadObjects(ConfigNode file) {
        struct QO {
            ConfigNode node;
            Class klass;
            Object o;
        }
        QO[] objects;
        //read all objects without members
        foreach (ConfigNode node; file) {
            //actually deserialize
            int oid = -1;
            try {
                oid = conv.toInt(node.name);
            } catch (conv.ConvError e) {
            } catch (conv.ConvOverflowError e) {
            }
            //error here, because this contains object nodes only
            if (oid < 0)
                throw new SerializeError("malformed ID: "~node.name);
            char[] type = node["type"];
            Class klass = mCtx.mTypes.findClassByName(type);
            if (!klass)
                throw new SerializeError("class not found: "~type);
            Object res = klass.newInstance();
            if (!res)
                throw new SerializeError("class could not be instantiated: "
                    ~type);
            mId2Object[oid] = res;
            objects ~= QO(node, klass, res);
        }
        //set all members
        foreach (qo; objects) {
            SafePtr ptr = mCtx.mTypes.ptrOf(qo.o);
            doReadMembers(qo.node, qo.klass, ptr);
        }
    }

    private void doReadMembers(ConfigNode cur, Class klass,
        SafePtr ptr)
    {
        assert (!!klass);
        //each class in the inheritance hierarchy gets a node (structs not)
        bool is_struct = !!cast(StructType)klass.type();
        Class ck = klass;
        //urgh, should have a ConfigNode iterator or so
        void doit(ConfigNode dest) {
            ptr.type = ck.type(); //should be safe...
            foreach (ClassMember m; ck.nontransientMembers()) {
                SafePtr mptr = m.get(ptr);
                doReadMember(dest, m.name(), mptr);
            }
        }
        if (is_struct) {
            assert (!ck.superClass());
            doit(cur);
            return;
        }
        foreach (ConfigNode dest; cur) {
            if (!ck)
                new SerializeError("what.");
            doit(dest);
            ck = ck.superClass();
        }
        if (ck)
            new SerializeError("what 2.");
    }

    private void doReadMember(ConfigNode cur, char[] member, SafePtr ptr)
    {
        if (!cur.hasValue(member) && !cur.hasNode(member)) {
            //std.stdio.writefln("%s not found, using default",member);
            return;
        }
        if (auto et = cast(EnumType)ptr.type) {
            //dirty trick...
            ptr.type = et.underlying();
            //fall through to BaseType
        }
        if (cast(BaseType)ptr.type) {
            unconvBaseType(ptr, cur[member]);
            return;
        }
        if (auto rt = cast(ReferenceType)ptr.type) {
            //object references
            //if (!rt.klass())
              //  typeError(ptr);
            Object o = getObject(cur[member]);
            if (!ptr.castAndAssignObject(o))
                throw new SerializeError("can't assign, t="~ptr.type.toString
                    ~", o="~(o?o.classinfo.name:"null"));
            return;
        }
        if (auto st = cast(StructType)ptr.type) {
            Class k = st.klass();
            if (!k)
                typeError(ptr);
            auto sub = cur.findNode(member);
            if (!sub)
                throw new SerializeError("struct ? -- "~st.toString~"::"~member);
            doReadMembers(sub, k, ptr);
            return;
        }
        if (ptr.type is mCtx.mTypes.getType!(char[])()) {
            //xxx error handling
            ptr.write!(char[])(cur[member]);
            return;
        }
        //byte[] too, because for game saving, the bitmap is a byte[]
        if (ptr.type is mCtx.mTypes.getType!(byte[])()) {
            //xxx error handling
            ptr.write!(byte[])(cur.getByteArrayValue(member));
            return;
        }
        if (auto art = cast(ArrayType)ptr.type) {
            ArrayType.Array arr = art.getArray(ptr);
            auto sub = cur.findNode(member);
            if (!sub)
                throw new SerializeError("? (2)");
            int length = -1;
            try {
                length = conv.toInt(sub["length"]);
            } catch (conv.ConvError e) {
            } catch (conv.ConvOverflowError e) { //oh god the pain
            }
            if (art.isStatic()) {
                if (arr.length != length)
                    throw new SerializeError("static array size mismatch");
            } else {
                art.setLength(ptr, length);
                arr = art.getArray(ptr);
            }
            for (int i = 0; i < arr.length; i++) {
                SafePtr eptr = arr.get(i);
                doReadMember(sub, str.format("%d", i), eptr);
            }
            return;
        }
        if (auto map = cast(MapType)ptr.type) {
            auto sub = cur.findNode(member);
            if (!sub)
                throw new SerializeError("? (3)");
            foreach (ConfigNode subsub; sub) {
                map.setKey2(ptr,
                    (SafePtr key) {
                        doReadMember(subsub, "key", key);
                    },
                    (SafePtr value) {
                        doReadMember(subsub, "value", value);
                    }
                );
            }
            return;
        }
        if (auto dg = cast(DelegateType)ptr.type) {
            auto sub = cur.findNode(member);
            if (!sub)
                throw new SerializeError("? (4)");
            Object dest = getObject(sub["dg_object"]);
            char[] method = sub["dg_method"];
            ClassMethod m;
            if (dest) {
                Class c = mCtx.mTypes.findClass(dest);
                assert (!!c); //we deserialized it
                m = c.findMethod(method);
                if (!m)
                    throw new SerializeError("method for delegate was not "
                        "found, name: "~method~" object: "~c.type.toString);
            }
            if (!mCtx.mTypes.writeDelegate(ptr, dest, m))
                throw new SerializeError("couldn't set delegate");
            return;
        }
        throw new SerializeError("couldn't deserialize: "~ptr.type.toString());
    }

    private void unconvBaseType(SafePtr ptr, char[] s) {
        Type t = ptr.type;
        assert (!!cast(BaseType)t);
        blergh!(char, byte, ubyte, short, ushort, int, uint, long, ulong,
            float, double, bool)(ptr, s);
    }

    private void blergh(T...)(SafePtr ptr, char[] s) {
        foreach (x; T) {
            if (ptr.type.typeInfo() is typeid(x)) {
                try {
                    //there don't seem to be any generically useable functions
                    //this is ok too for now
                    x val;
                    static if (is(x == char)) {
                        val = conv.toUbyte(s);
                    } else static if (isUnsigned!(x)) {
                        val = conv.toUlong(s);
                    } else static if (isSigned!(x)) {
                        val = conv.toLong(s);
                    } else static if (is(x == float)) {
                        val = conv.toFloat(s);
                    } else static if (is(x == double)) {
                        val = conv.toDouble(s);
                    } else static if (is(x == bool)) {
                        if (s == "true") {
                            val = true;
                        } else if (s == "false") {
                            val = false;
                        } else {
                            throw new conv.ConvError("not bool: "~s);
                        }
                    } else {
                        static assert (false);
                    }
                    ptr.write!(x)(val);
                    return;
                } catch (conv.ConvError e) {
                } catch (conv.ConvOverflowError e) {
                }
                throw new SerializeError("conversion failed: '"~s~"' -> "
                    ~ptr.type.toString);
            }
        }
        typeError(ptr, "basetype");
        return "";
    }

    override Object readObject() {
        if (!mObjectNodes.length)
            throw new SerializeError("no more objects for readObject()");
        ConfigNode cur = mObjectNodes[0];
        mObjectNodes = mObjectNodes[1..$];
        doReadObjects(cur);
        return getObject(cur["_object"]);
    }

    //like readObject(), but cast to T and make failure a deserialization error
    //by default, the result also must be non-null
    T readObjectT(T)(bool can_be_null = false) {
        auto o = readObject();
        T t = cast(T)o;
        if (o && !t)
            throw new SerializeError("unexpected object type");
        if (!o && !can_be_null)
            throw new SerializeError("object is null");
        return t;
    }
}
