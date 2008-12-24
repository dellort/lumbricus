module utils.serialize;

import utils.configfile;
import utils.reflection;

import str = std.string;

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
}

class SerializeOutConfig : SerializeBase {
    private {
        int mIDAlloc;
        int[Object] mObject2Id;
        ConfigNode mOutput;
    }

    this(SerializeContext a_ctx) {
        super(a_ctx);
        mOutput = new ConfigNode();
    }

    private char[] doWriteObject(ConfigNode file, Object o) {
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
        //(note that ptr actually points to "o", á la "ptr = &o;")
        SafePtr ptr = mCtx.mTypes.ptrOf(o);
        Class klass = mCtx.mTypes.findClass(o);
        if (!klass)
            typeError(ptr);
        auto nid = ++mIDAlloc;
        mObject2Id[o] = nid;
        auto node = file.getSubNode(str.format("%d", nid));
        node["type"] = klass.name();
        doWriteMembers(file, node, klass, ptr);
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
            foreach (ClassMember m; ck.members()) {
                SafePtr mptr = m.get(ptr);
                doWriteMember(file, dest, m.name(), mptr);
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
            cur[member] = doWriteObject(file, ptr.toObject());
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
                throw new Exception(str.format("couldn't write delegate, "
                    "dest-class: %s function: %#x",
                    (cast(Object)dgp.ptr).classinfo.name, dgp.funcptr));
            }
            auto sub = cur.getSubNode(member);
            sub["dg_object"] = doWriteObject(file, dg_o);
            sub["dg_method"] = dg_m ?
                str.format("%s::%s", dg_m.klass.name, dg_m.name) : "null";
            return;
        }
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
                return str.format("%s", ptr.read!(x)());
            }
        }
        typeError(ptr, "basetype");
        return "";
    }

    void writeObject(Object o) {
        ConfigNode cur = mOutput.getSubNode("serialized").addUnnamedNode();
        doWriteObject(cur, o);
    }

    private void typeError(SafePtr source, char[] add = "") {
        if (cast(ReferenceType)source.type) {
            Object o = source.toObject();
            if (o)
                throw new Exception(str.format("problem with: %s / %s %s",
                    source.type, o.classinfo.name, add));
        }
        throw new Exception(str.format("problem with: %s %s", source.type, add));
    }

    ConfigNode finish() {
        auto exts = mOutput.getSubNode("externals");
        foreach (char[] name; mExternals) {
            exts.setStringValue("", name);
        }
        return mOutput;
    }
}
