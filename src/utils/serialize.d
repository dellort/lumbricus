module utils.serialize;

import utils.configfile;
import utils.reflect.all;
import utils.misc;
import utils.hashtable;
import str = utils.string;

import conv = tango.util.Convert;
import tango.core.Traits : isIntegerType, isFloatingPointType;

debug import tango.core.stacktrace.StackTrace : nameOfFunctionAt;

debug debug = CountClasses;

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
- Not supported at all:
  - pointers, function pointers, typedefs, unions, void[]
  - D standard classes like TypeInfo or ClassInfo
  (Although some could be supported, trivially or under certain conditions.)
+/

//type informations: mostly the stuff from utils.reflection, and possibly hooks
// for custom serializtion of special object types
class SerializeContext {
    struct CustomSerialize {
        CustomCreator creator;
        CustomReader reader;
        CustomWriter writer;
        Type type;
        char[] id;
    }

    private {
        Types mTypes;
        RefHashTable!(Object, char[]) mExternals;
        Object[char[]] mExternalsReverse;
        //ClassInfo[] mIgnored;

        RefHashTable!(TypeInfo, CustomSerialize) mCustomSerializers;
        TypeInfo[char[]] mCustomSerializerNames;
    }

    alias void function(SerializeBase, SafePtr, void delegate(SafePtr)) ExchDg;
    alias ExchDg CustomWriter;
    alias ExchDg CustomReader;
    alias Object function(SerializeBase, void delegate(SafePtr)) CustomCreator;

    this(Types a_types) {
        mTypes = a_types;
        mExternals = new typeof(mExternals);
        mCustomSerializers = new typeof(mCustomSerializers);
    }

    //register external object
    void addExternal(Object o, char[] id) {
        if (o in mExternals || id in mExternalsReverse)
            throw new Exception("external not unique");
        mExternals[o] = id;
        mExternalsReverse[id] = o;
    }

    //undo addExternal()
    //NOTE: if there were several strings mapping ot the same object, all
    //      entries will be removed
    void removeExternal(Object o) {
        mExternals.remove(o);
        //xxx: this can't be
        outer: while (true) {
            foreach (k, v; mExternalsReverse) {
                if (v is o) {
                    mExternalsReverse.remove(k);
                    continue outer;
                }
            }
            break;
        }
    }

    private CustomSerialize* find_cs(TypeInfo t, bool create) {
        auto p = t in mCustomSerializers;
        if (!p && create) {
            mCustomSerializers.insert(t, CustomSerialize.init);
            p = t in mCustomSerializers;
            assert(!!p);
        }
        return p;
    }

    CustomSerialize* lookupCustomSerializer(TypeInfo t) {
        return find_cs(t, false);
    }
    CustomSerialize* lookupCustomSerializer(char[] name) {
        auto p = name in mCustomSerializerNames;
        if (!p)
            return null;
        return *p in mCustomSerializers;
    }

    //add custom serialization for T
    //the reader/writer callbacks are called on serialization/deserialization
    //the creator callbacks is only needed for reference types, and is called
    //  on deserialization
    //because I'm stupid, both the reader and creator function can read further
    //  data using that void delegate(SafePtr) callback. with this callback,
    //  you can read custom data. the reader function can read any types
    //  (including object references), but the creator function is restricted to
    //  native types, structs, arrays, and AAs. if you have a better idea (I'm
    //  sure there will be one), tell me.
    void addCustomSerializer(T)(CustomCreator creator, CustomReader reader,
        CustomWriter writer)
    {
        auto mt = mTypes.getType!(T)();
        auto t = typeid(T);
        assert(!!writer);
        bool isref = !!cast(ReferenceType)mt;
        //only allowed / required for reference types
        assert(isref == (!!creator));
        //reader can be omitted for reference types
        assert(!isref || !reader);
        auto s = find_cs(t, true);
        if (s.creator) {
            assert(s.creator is creator);
            assert(s.reader is reader);
            assert(s.writer is writer);
            assert(s.type is mt);
        }
        s.creator = creator;
        s.reader = reader;
        s.writer = writer;
        s.type = mt;
        s.id = T.stringof; //just need some unique name
        mCustomSerializerNames[s.id] = t;
    }

    /+
    //this is a hack
    void addIgnoreClass(ClassInfo ignore) {
        mIgnored ~= ignore;
    }
    +/

    //debug: write out the object graph in graphviz format
    //here because it needs Types and mExternals
    debug char[] dumpGraph(Object root) {
        char[] r;
        int id_alloc;
        int[Object] visited; //map to id
        Object[] to_visit;
        r ~= `graph "a" {` \n;
        to_visit ~= root;
        visited[root] = ++id_alloc;
        //some other stuff
        bool[char[]] unknown, unregistered;

        void delegate(int cur, SafePtr ptr, Class c) fwdDoStructMembers;

        void doField(int cur, SafePtr ptr) {
            if (auto s = cast(StructType)ptr.type) {
                assert (!!s.klass());
                fwdDoStructMembers(cur, ptr, s.klass());
            } else if (auto rt = cast(ReferenceType)ptr.type) {
                //object reference
                Object n = ptr.toObject();
                if (!n)
                    return;
                int other;
                if (auto po = n in visited) {
                    other = *po;
                } else {
                    other = ++id_alloc;
                    visited[n] = other;
                    to_visit ~= n;
                }
                r ~= myformat("{} -- {}\n", cur, other);
            } else if (auto art = cast(ArrayType)ptr.type) {
                ArrayType.Array arr = art.getArray(ptr);
                for (int i = 0; i < arr.length; i++) {
                    doField(cur, arr.get(i));
                }
            }
        }

        void doStructMembers(int cur, SafePtr ptr, Class c) {
            foreach (ClassMember m; c.members()) {
                doField(cur, m.get(ptr));
            }
        }

        fwdDoStructMembers = &doStructMembers;

        while (to_visit.length) {
            Object cur = to_visit[0];
            to_visit = to_visit[1..$];
            int id = visited[cur];
            if (auto pname = cur in mExternals) {
                r ~= myformat(`{} [label="ext: {}"];` \n, id, *pname);
                continue;
            }
            SafePtr indirect = mTypes.ptrOf(cur);
            void* tmp;
            SafePtr ptr = indirect.mostSpecificClass(&tmp, true);
            if (!ptr.type) {
                //the actual class was never seen at runtime
                r ~= myformat(`{} [label="unknown: {}"];` \n, id,
                    cur.classinfo.name);
                unknown[cur.classinfo.name] = true;
                continue;
            }
            auto rt = castStrict!(ReferenceType)(ptr.type);
            assert (!rt.isInterface());
            Class c = rt.klass();
            if (!c) {
                //class wasn't registered for reflection
                r ~= myformat(`{} [label="unregistered: {}"];` \n, id,
                    cur.classinfo.name);
                unregistered[cur.classinfo.name] = true;
                continue;
            }
            r ~= myformat(`{} [label="class: {}"];` \n, id,
                ConfigFile.doEscape(cur.classinfo.name));
            while (c) {
                ptr.type = c.owner(); //dangerous, but should be ok
                doStructMembers(id, ptr, c);
                c = c.superClass();
            }
        }
        r ~= "}\n";

        char[][] s_unknown = unknown.keys, s_unreged = unregistered.keys;
        s_unknown.sort;
        s_unreged.sort;
        Trace.formatln("Completely unknown:");
        foreach (x; s_unknown)
            Trace.formatln("  {}", x);
        Trace.formatln("Unregistered:");
        foreach (x; s_unreged)
            Trace.formatln("  {}", x);

        return r;
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
    }

    this(SerializeContext a_ctx) {
        mCtx = a_ctx;
    }

    protected void typeError(SafePtr source, char[] add = "") {
        if (cast(ReferenceType)source.type) {
            Object o = source.toObject();
            if (o)
                throw new SerializeError(myformat("problem with: {} / {} {}",
                    source.type, o.classinfo.name, add));
        }
        throw new SerializeError(myformat("problem with: {}, ti={} {}",
            source.type, source.type.typeInfo(), add));
    }

    //these functions are here because the inheritance hierarchy is hard to get
    //right (especially with all my ridiculous base classes); maybe interfaces
    //could be used, but these suck, also: templates?

    //several objects can be written sequentially; these can be read in the same
    //order when deserializing (like with a stream)
    //the object can depend from previously written objects (they share they
    //same object graph)
    final void writeObject(Object o) {
        write(o);
    }

    //parallel to writeObject()
    final Object readObject() {
        return read!(Object)();
    }

    //like readObject(), but cast to T and make failure a deserialization error
    //by default, the result also must be non-null
    final T readObjectT(T)(bool can_be_null = false) {
        assert(is(T == class));
        auto o = read!(Object)();
        T t = cast(T)o;
        if (o && !t)
            throw new SerializeError("unexpected object type");
        if (!o && !can_be_null)
            throw new SerializeError("object is null");
        return t;
    }

    final void write(T)(T d) {
        writeDynamic(mCtx.mTypes.ptrOf(d));
    }

    final T read(T)() {
        T res;
        readDynamic(mCtx.mTypes.ptrOf(res));
        return res;
    }

    //overwritten by SerializeInConfig
    void readDynamic(SafePtr d) {
        assert(false);
    }

    //overwritten by SerializeOutConfig
    void writeDynamic(SafePtr d) {
        assert(false);
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
        int mIDAlloc = 0;
        RefHashTable!(Object, char[]) mObject2Id;
        Object[] mObjectStack;
        int mOSIdx = 0;
        debug (CountClasses) {
            int[Class] mCounter;
        }
    }

    this(SerializeContext a_ctx) {
        super(a_ctx, new ConfigNode());
        mObject2Id = new typeof(mObject2Id);
        //just some preallocation, I guess
        mObjectStack.length = 1024;
    }

    private bool doWriteNextObject(ConfigNode file) {
        if (mOSIdx <= 0)
            return false;
        mOSIdx--;
        Object o = mObjectStack[mOSIdx];

        auto node = file.getSubNode(mObject2Id[o]);
        auto tnode = node.getSubNode("type");

        //NOTE: ClassInfo.typeinfo was added somewhere >= dmd1.045
        TypeInfo ti = o.classinfo.typeinfo;
        if (auto cs = mCtx.lookupCustomSerializer(ti)) {
            //custom serialization
            tnode.value = "custom|" ~ cs.id;
            SafePtr ptr2 = mCtx.mTypes.objPtr(o);
            doWriteCustom(node, ptr2, *cs);
            return true;
        }

        //normal serialization

        //(note that ptr actually points to "o", á la "ptr = &o;")
        SafePtr ptr = mCtx.mTypes.ptrOf(o);
        Class klass = mCtx.mTypes.findClass(o);
        if (!klass)
            typeError(ptr, "can't serialize ["~o.toString()~"]");
        Object defobj = klass.defaultValues();
        SafePtr defptr = mCtx.mTypes.ptrOf(defobj);

        debug (CountClasses) {
            auto pc = klass in mCounter;
            if (pc) {
                (*pc)++;
            } else {
                mCounter[klass] = 1;
            }
        }

        tnode.value = klass.name();
        doWriteMembers(node, klass, ptr, defptr);

        return true;
    }

    //queue an object for writing, or return id reference if already written
    //if this returns an empty string, it means the object is ignored
    private char[] queueObject(Object o) {
        if (o is null) {
            return "null";
        }
        if (auto pid = o in mObject2Id) {
            return *pid;
        }
        if (auto pname = o in mCtx.mExternals) {
            return "ext#" ~ *pname;
        }
        /+
        foreach (i; mIgnored) {
            if (o.classinfo is i)
                return "";
        }
        +/
        auto nid = ++mIDAlloc;
        auto id = myformat("#{}", nid);
        mObject2Id[o] = id;
        if (mOSIdx >= mObjectStack.length)
            mObjectStack.length = mObjectStack.length*2;
        mObjectStack[mOSIdx] = o;
        mOSIdx++;
        return id;
    }

    private void doWriteMembers(ConfigNode cur, Class klass, SafePtr ptr,
        SafePtr defptr)
    {
        assert (!!klass);
        //each class in the inheritance hierarchy gets a node (structs not)
        bool is_struct = !!cast(StructType)klass.type();

        if (is_struct)
            assert (!klass.superClass());

        Class ck = klass;
        while (ck) {
            //(not for structs)
            auto dest = is_struct ? cur : cur.add();
            ptr.type = ck.type(); //should be safe...
            defptr.type = ptr.type;
            foreach (ClassMember m; ck.nontransientMembers()) {
                SafePtr mptr = m.get(ptr);
                SafePtr mdptr = defptr.ptr ? m.get(defptr) : SafePtr.Null;
                doWriteMember(dest, m.name(), mptr, mdptr);
            }
            ck = ck.superClass();
        }
    }

    private bool is_def(SafePtr data, SafePtr def) {
        assert(!def.type || data.type is def.type);
        if (!def.ptr)
            return false;
        return data.type.op_is(data, def);
    }

    private void doWriteMember(ConfigNode parent, char[] member_name,
        SafePtr ptr, SafePtr defptr)
    {
        //object references; always by ref, even for custom serialized types
        if (cast(ReferenceType)ptr.type) {
            if (is_def(ptr, defptr))
                return;
            auto member = parent.add(member_name);
            member.value = queueObject(ptr.toObject());
            return;
        }

        if (auto cs = mCtx.lookupCustomSerializer(ptr.type.typeInfo())) {
            auto member = parent.add(member_name);
            doWriteCustom(member, ptr, *cs);
            return;
        }

        //to save space, don't write stuff if it's equal to the
        //  enclosing (!) type's default value
        //only for normal serialization
        if (is_def(ptr, defptr))
            return;

        auto member = parent.add(member_name);

        //normal serialization

        if (auto et = cast(EnumType)ptr.type) {
            //dirty trick: do as if it was an integer; should be bitcompatible
            //don't try this at home!
            ptr.type = et.underlying();
            defptr.type = ptr.type;
            //fall through to BaseType
        }
        if (cast(BaseType)ptr.type) {
            member.value = convBaseType(ptr);
            return;
        }
        if (auto st = cast(StructType)ptr.type) {
            //write recursively
            Class k = st.klass();
            if (!k)
                typeError(ptr);
            doWriteMembers(member, k, ptr, defptr);
            return;
        }
        //handle string arrays differently, having them as real arrays is... urgh
        if (ptr.type is mCtx.mTypes.getType!(char[])()) {
            member.value = ptr.read!(char[])();
            return;
        }
        //byte[] too, because for game saving, the bitmap is a byte[]
        if (ptr.type is mCtx.mTypes.getType!(ubyte[])()) {
            member.setCurValue!(ubyte[])(ptr.read!(ubyte[]));
            return;
        }
        if (auto art = cast(ArrayType)ptr.type) {
            auto sub = member;
            ArrayType.Array arr = art.getArray(ptr);
            for (int i = 0; i < arr.length; i++) {
                SafePtr eptr = arr.get(i);
                //about default value: if it's a static array, and if we have
                //  defptr, we could call getArray/get on it and pass it here
                //for dynamic array, you could use the array item type's default
                //  initializer
                //warning: if we go back to checking default values, you must
                //  make sure array items are skipped on reading as well
                doWriteMember(sub, "", eptr, SafePtr.Null);
            }
            return;
        }
        if (auto map = cast(MapType)ptr.type) {
            auto sub = member;
            map.iterate(ptr, (SafePtr key, SafePtr value) {
                auto subsub = sub.add();
                doWriteMember(subsub, "k", key, SafePtr.Null);
                doWriteMember(subsub, "v", value, SafePtr.Null);
            });
            return;
        }
        if (auto dg = cast(DelegateType)ptr.type) {
            Object dg_o;
            ClassMethod dg_m;
            if (!ptr.readDelegate(dg_o, dg_m)) {
                D_Delegate* dgp = cast(D_Delegate*)ptr.ptr;
                //warning: this might crash, if the delegate points to the
                //         stack or a struct; we simply can't tell
                char[] what = "enable version debug to see why";
                debug {
                    //we can't tell to what dgp.ptr will point to
                    //if it's not an object, we'll just crash
                    //otherwise, output information useful for debugging
                    Trace.formatln("hello, serialize.d might crash here.");
                    char[] crashy = (cast(Object)dgp.ptr).classinfo.name;
                    char[] func = nameOfFunctionAt(dgp.funcptr);
                    what = myformat("dest-class: {} function: 0x{:x} '{}'",
                        crashy, dgp.funcptr, func);
                }
                throw new SerializeError("couldn't write delegate, "~what);
            }
            auto sub = member;
            char[] id = queueObject(dg_o);
            sub["dg_object"] = id;
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
                x val = ptr.read!(x)();
                static if (isFloatingPointType!(x)) {
                    return floatToHex(val);
                } else {
                    return myformat("{}", val);
                }
            }
        }
        typeError(ptr, "basetype");
        return "";
    }

    private void doWriteCustom(ConfigNode cur, SafePtr ptr,
        SerializeContext.CustomSerialize cs)
    {
        cs.writer(this, ptr, (SafePtr write) {
            doWriteMember(cur, "", ptr, SafePtr.Null);
        });
    }

    override void writeDynamic(SafePtr o) {
        ConfigNode cur = mFile.add();
        //when writing an object, this is like serializing a
        //  struct { Object o; }
        //in other words, this will only write an object reference into cur
        //that's required to keep referential integrity
        doWriteMember(cur, "data", o, o.type.initPtr());
        while (doWriteNextObject(cur.getSubNode("objects"))) {}
    }

    ConfigNode finish() {
        debug (CountClasses) {
            printAnnoyingStats();
        }
        auto f = mFile;
        mFile = null;
        return f;
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
        Trace.formatln("Class count:");
        int sum = 0;
        foreach (x; list) {
            Trace.formatln("  {:d4}  {}", x.count, x.c.name);
            sum += x.count;
        }
        Trace.formatln("done, sum={:d}.", sum);
    }
}

class SerializeInConfig : SerializeConfig {
    private {
        //for each readDynamic() call
        ConfigNode[] mEntryNodes;
        Object[int] mId2Object;
    }

    this(SerializeContext a_ctx, ConfigNode a_file) {
        super(a_ctx, a_file);
        foreach (ConfigNode node; mFile) {
            mEntryNodes ~= node;
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
                oid = conv.to!(int)(id[1..$]);
            } catch (conv.ConversionException e) {
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
            auto pobj = id in mCtx.mExternalsReverse;
            if (!pobj)
                throw new SerializeError("external not found: "~id);
            return *pobj;
        }
        throw new SerializeError("malformed ID (3): "~id);
    }

    //deserialize all objects in this node
    private void doReadObjects(ConfigNode onode) {
        struct QO {
            ConfigNode node;
            Class klass;
            Object o;
            ConfigNode[] stuff;
        }
        QO[] objects;
        //preallocation trick...
        objects.length = onode.count();
        objects.length = 0;
        //read all objects without members
        foreach (ConfigNode node; onode) {
            //if (node.value.length)
            //    continue;
            //actually deserialize
            int oid = -1;
            if (node.name.length > 0 && node.name[0] == '#') {
                try {
                    oid = conv.to!(int)(node.name[1..$]);
                } catch (conv.ConversionException e) {
                }
            }
            //error here, because this contains object nodes only
            if (oid < 0)
                throw new SerializeError("malformed ID: "~node.name);
            Object obj;
            Class klass;
            ConfigNode[] stuff;
            char[] type = node["type"];
            if (str.eatStart(type, "custom|")) {
                auto cs = mCtx.lookupCustomSerializer(type);
                if (!cs)
                    throw new SerializeError("custom serializer not found for: "
                        ~type);
                assert(!!cs.creator);
                stuff = node.getSubNode("data").subNodesToArray();
                obj = cs.creator(this, (SafePtr ptr) {
                    if (!stuff.length)
                        throw new SerializeError("no more data for custom"
                            " deserializer");
                    doReadMember(stuff[0], ptr);
                    stuff = stuff[1..$];
                });
                assert(!!obj);
            } else {
                klass = mCtx.mTypes.findClassByName(type);
                if (!klass)
                    throw new SerializeError("class not found: "~type);
                obj = klass.newInstance();
                if (!obj)
                    throw new SerializeError("class could not be instantiated: "
                        ~type);
            }
            mId2Object[oid] = obj;
            objects ~= QO(node, klass, obj, stuff);
        }
        //set all members
        foreach (qo; objects) {
            SafePtr ptr = mCtx.mTypes.ptrOf(qo.o);

            if (qo.klass) {
                doReadMembers(qo.node, qo.klass, ptr);
            } else {
                TypeInfo ti = qo.o.classinfo.typeinfo;
                auto cs = mCtx.lookupCustomSerializer(ti);
                assert(!!cs);
                SafePtr ptr2 = mCtx.mTypes.objPtr(qo.o);
                doReadCustom(qo.stuff, ptr2, *cs);
            }
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
                auto sub = dest.findNode(m.name());
                //if null, then either
                //  - writer saw a default value and didn't write the member
                //  - the type was different and didn't have this member
                if (sub)
                    doReadMember(sub, mptr);
            }
        }
        if (is_struct) {
            assert (!ck.superClass());
            doit(cur);
            return;
        }
        foreach (ConfigNode dest; cur) {
            if (dest.name.length)
                continue; //oops, hack
            if (!ck)
                new SerializeError("what.");
            doit(dest);
            ck = ck.superClass();
        }
        if (ck)
            new SerializeError("what 2.");
    }

    private void doReadMember(ConfigNode member, SafePtr ptr) {
        //object references
        if (auto rt = cast(ReferenceType)ptr.type) {
            Object o = getObject(member.value);
            if (!ptr.castAndAssignObject(o))
                throw new SerializeError("can't assign, t="~ptr.type.toString
                    ~", o="~(o?o.classinfo.name:"null"));
            return;
        }

        if (auto cs = mCtx.lookupCustomSerializer(ptr.type.typeInfo())) {
            doReadCustom(member.subNodesToArray(), ptr, *cs);
            return;
        }

        if (auto et = cast(EnumType)ptr.type) {
            //dirty trick...
            ptr.type = et.underlying();
            //fall through to BaseType
        }
        if (cast(BaseType)ptr.type) {
            unconvBaseType(ptr, member.value);
            return;
        }
        if (auto st = cast(StructType)ptr.type) {
            Class k = st.klass();
            if (!k)
                typeError(ptr);
            doReadMembers(member, k, ptr);
            return;
        }
        if (ptr.type is mCtx.mTypes.getType!(char[])()) {
            //xxx error handling
            ptr.write!(char[])(member.value);
            return;
        }
        //byte[] too, because for game saving, the bitmap is a byte[]
        if (ptr.type is mCtx.mTypes.getType!(ubyte[])()) {
            //xxx error handling
            ptr.write!(ubyte[])(member.getCurValue!(ubyte[])());
            return;
        }
        if (auto art = cast(ArrayType)ptr.type) {
            ArrayType.Array arr = art.getArray(ptr);
            auto sub = member;
            int length = sub.count();
            if (art.isStatic()) {
                if (arr.length != length)
                    throw new SerializeError("static array size mismatch");
            } else {
                art.setLength(ptr, length);
                arr = art.getArray(ptr);
            }
            int index = 0;
            foreach (ConfigNode s; sub) {
                SafePtr eptr = arr.get(index);
                doReadMember(s, eptr);
                index++;
            }
            return;
        }
        if (auto map = cast(MapType)ptr.type) {
            auto sub = member;
            foreach (ConfigNode subsub; sub) {
                map.setKey2(ptr,
                    (SafePtr key) {
                        doReadMember(subsub.getSubNode("k"), key);
                    },
                    (SafePtr value) {
                        doReadMember(subsub.getSubNode("v"), value);
                    }
                );
            }
            return;
        }
        if (auto dg = cast(DelegateType)ptr.type) {
            auto sub = member;
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
            if (!ptr.writeDelegate(dest, m))
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
                        val = conv.to!(ubyte)(s);
                    } else static if (isIntegerType!(x)) {
                        val = conv.to!(x)(s);
                    } else static if (isFloatingPointType!(x)) {
                        //xxx (see end of file)
                        val = toReal(s);
                    } else static if (is(x == bool)) {
                        if (s == "true") {
                            val = true;
                        } else if (s == "false") {
                            val = false;
                        } else {
                            throw new conv.ConversionException("not bool: "~s);
                        }
                    } else {
                        static assert (false);
                    }
                    ptr.write!(x)(val);
                    return;
                } catch (conv.ConversionException e) {
                }
                throw new SerializeError("conversion failed: '"~s~"' -> "
                    ~ptr.type.toString);
            }
        }
        typeError(ptr, "basetype");
        return "";
    }

    private void doReadCustom(ConfigNode[] stuff, SafePtr ptr,
        SerializeContext.CustomSerialize cs)
    {
        if (!cs.reader)
            return;
        cs.reader(this, ptr, (SafePtr read) {
            if (!stuff.length)
                throw new SerializeError("no more data for custom deserializer");
            doReadMember(stuff[0], ptr);
            stuff = stuff[1..$];
        });
    }

    override void readDynamic(SafePtr p) {
        //clear data before deserializing (just ensure correct default values)
        p.type.assign(p, p.type.initPtr());

        if (!mEntryNodes.length)
            throw new SerializeError("no more objects for readObject()");
        ConfigNode cur = mEntryNodes[0];
        mEntryNodes = mEntryNodes[1..$];

        doReadObjects(cur.getSubNode("objects"));
        doReadMember(cur.getSubNode("data"), p);
    }
}



//As tango.text.convert.Float.toFloat can't read hexadecimal floats,
//toFloat code from phobos follows

//xxx imports
import tango.stdc.stringz : toStringz;
import tango.stdc.stdlib : strtold;
import tango.stdc.stdio : snprintf;
import tango.stdc.errno;
import tango.text.Util : isSpace;

private int getErrno() {
    return errno();
}
private void setErrno(int val) {
    errno = val;
}

//from phobos: std.conv
//ok, slightly changed and renamed from toFloat to toReal
real toReal(in char[] s)
{
    real f;
    char* endptr;
    char* sz;

    //writefln("toFloat('{}')", s);
    sz = toStringz(s);
    if (isSpace(*sz))
    goto Lerr;

    // BUG: should set __locale_decpoint to "." for DMC

    setErrno(0);
    static assert(is(typeof(strtold(null, null) == typeof(f))));
    f = strtold(sz, &endptr);
    if (getErrno() == ERANGE)
    goto Lerr;
    if (endptr && (endptr == sz || *endptr != 0))
    goto Lerr;

    return f;

  Lerr:
    throw new conv.ConversionException(s ~ " not representable as a float");
    assert(0);
}

//return something like std.format("%a", f)
//also similar to Phobos, but code not really copied
char[] floatToHex(real f) {
    char[20] tmp = void;
    char[] buf = tmp;
    for (;;) {
        //NOTE: the C function expects "long double"
        //  according to std.format's impl., this is equal to D's real
        int res = snprintf(buf.ptr, buf.length, "%La\0", f);
        if (res < 0) {
            //error? can this happen?
            assert (false);
            return "error";
        }
        if (res <= buf.length) {
            buf = buf[0..res];
            break;
        }
        buf.length = buf.length * 2;
    }
    return buf.dup;
}

