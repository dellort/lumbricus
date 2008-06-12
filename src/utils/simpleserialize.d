module utils.simpleserialize;

import str = std.string;
import conv = std.conv;

import utils.configfile;
import utils.factory;
import utils.output;
import utils.misc;
import utils.mybox;

//später als delegate, bitte
//char[] durch ConfigItem ersetzen (wegen komplexeren Datentypen: structs etc.)
alias MyBox function(char[] config) ConfigRead;
alias char[] function(MyBox data) ConfigWrite;

class ConfigIO {
    private {
        ConfigRead[TypeInfo] mReaders;
        ConfigWrite[TypeInfo] mWriters;
    }

    //the filter can replace specific data by other data
    //used to translate objects to object references
    MyBox delegate(MyBox data) write_filter;
    //write_filter backwards
    TypeInfo delegate(TypeInfo t) read_filter_type;
    MyBox delegate(TypeInfo orgtype, MyBox data) read_filter_data;

    char[] write(MyBox data) {
        //fehlerbehandlung...
        data = write_filter(data);
        std.stdio.writefln(data.type);
        return mWriters[data.type](data);
    }

    MyBox read(TypeInfo type, char[] config) {
        return read_filter_data(type, mReaders[read_filter_type(type)](config));
    }

    void register(TypeInfo t, ConfigRead r, ConfigWrite w) {
        mReaders[t] = r;
        mWriters[t] = w;
    }
}

//used to mark the object's constructor used for deserialization
//this is to avoid confusion with the default constructor
interface SerializeCtor {
}

//unlike magical Java, you need to implement the serialize-methods for this
interface Serializeable {
    //read/write members
    void serializeExchange(ObjectStream stream);
    //optional; fix up after serialization done
    //important if you need to use object references after serialization
    //two alternatives, #2 is implemented:
    //#1: when exchange() is called, these might be null
    //#2: when exchange() is called, refs might not be deserialized yet
    void serializeFixup();
}

class SerializeBase {
    private {
        ConfigIO mIO;
        ObjectStream mStream;
        Factory!(Serializeable, SerializeCtor) mClasses;
        ObjectID mObjectIDAlloc;
        Object[ObjectID] mIDtoObj;
        ObjectID[Object] mObjToID;
        Object[char[]] mExternals;
        Object[char[]] mRootSet;
        //during serialization
        Object[] mNewObjectQueue;
    }
    alias int ObjectID;
    const ObjectID cInvalidObjectID = ObjectID.init;
    const ObjectID cObjectIDNull = 1; //lol

    const char[] cSerializerVersion = "SillySerializer v0.000001";

    this() {
        mIO = new ConfigIO();
        mIO.write_filter = &do_write_filter;
        mIO.read_filter_data = &do_read_filter_data;
        mIO.read_filter_type = &do_read_filter_type;
        mClasses = new typeof(mClasses);
        mStream = new ObjectStream(this);
        //the null reference!
        mObjectIDAlloc = cObjectIDNull+1;
        addExternal("null", null);
        assert(lookupObject(null, false) == cObjectIDNull);
    }

    void registerClass(T)(char[] name) {
        mClasses.register!(T)(name);
    }

    //external objects are such ones, which are not serialized, but which are
    //still referenced by the serialized objects
    //they do not need to implement any special stuff
    //o can even be null
    void addExternal(char[] name, Object o) {
        assert(!(name in mExternals));
        mExternals[name] = o;
    }
    Object getExternal(char[] name) {
        return mExternals[name];
    }

    //typically used before serializing
    void addRoot(char[] name, Object o) {
        assert(!(name in mRootSet));
        assert(castStrict!(Serializeable)(o));
        mRootSet[name] = o;
        lookupObject(cast(Object)o, true);
    }

    //typically used after deserializing
    Object getRoot(char[] name) {
        return mRootSet[name];
    }

    //assign_id==true => never return cInvalidObjectID, instead enter it into
    //the object map
    ObjectID lookupObject(Object o, bool assign_id) {
        if (o is null)
            return cObjectIDNull;
        auto pid = o in mObjToID;
        if (pid)
            return *pid;
        if (!assign_id)
            return cInvalidObjectID;
        ObjectID id = ++mObjectIDAlloc;
        mIDtoObj[id] = o;
        mObjToID[o] = id;
        return id;
    }

    //throws an exception if ID invalid
    Object lookupID(ObjectID id) {
        if (id == cObjectIDNull)
            return null;
        auto pobj = id in mIDtoObj;
        if (!pobj)
            throw new Exception("object not found");
        return *pobj;
    }

    //internal
    protected void setObjectID(Object o, ObjectID id) {
        if (id == cObjectIDNull) {
            assert(o is null);
            return;
        }
        assert(!!o && id > cObjectIDNull);
        assert(!(id in mIDtoObj));
        assert(!(o in mObjToID));
        mIDtoObj[id] = o;
        mObjToID[o] = id;
    }

    protected ObjectID parseID(char[] v) {
        if (v.length < 4 || v[0..3] != "obj")
            throw new Exception("what");
        return conv.toInt(v[3..$]);
    }

    protected char[] idToStr(ObjectID id) {
        return str.format("obj%d", id);
    }
    protected char[] objToStrID(Object o) {
        return idToStr(lookupObject(o, false));
    }

    private MyBox do_write_filter(MyBox data) {
        if (cast(TypeInfo_Class)(data.type())) {
            std.stdio.writefln("a %s", data.type);
            Object o = data.asObject();
            ObjectID id = lookupObject(o, false);
            if (id == cInvalidObjectID) {
                id = lookupObject(o, true);
                mNewObjectQueue ~= o;
            }
            //it's a class => lookup object or enter it into the object map
            return MyBox.Box!(char[])(idToStr(id));
        } else {
            std.stdio.writefln("b %s", data.type);
            return data;
        }
    }

    private TypeInfo do_read_filter_type(TypeInfo t) {
        if (cast(TypeInfo_Class)t) {
            return typeid(char[]); //object reference
        } else {
            return t;
        }
    }

    private MyBox do_read_filter_data(TypeInfo orgtype, MyBox data) {
        if (cast(TypeInfo_Class)(orgtype)) {
            //it's a class => reverse lookup object
            MyBox b = MyBox.Box!(Object)(
                lookupID(parseID(data.unbox!(char[])())));
            b.convertObject(orgtype);
            return b;
        } else {
            return data;
        }
    }

    ConfigIO io() {
        return mIO;
    }
}

class Serializer : SerializeBase {
    void serialize(ConfigNode data) {
        data.setStringValue("comment", cSerializerVersion);
        //various tables
        auto roots = data.getSubNode("roots");
        foreach (char[] name, Object o; mRootSet) {
            roots.setStringValue(name, objToStrID(o));
        }
        auto exts = data.getSubNode("externals");
        foreach (char[] name, Object o; mExternals) {
            lookupObject(o, true); //be sure to alloc an ID
            exts.setStringValue(name, objToStrID(o));
        }
        //actually serialize objects
        auto objs = data.getSubNode("objects");
        void doSerialize(Object s) {
            auto c = objs.getSubNode(objToStrID(s));
            char[] name = mClasses.lookupDynamic((cast(Object)s).classinfo);
            assert(name != "");
            c.setStringValue("_class", name);
            mStream.reset(ObjectStream.Mode.Write, c);
            castStrict!(Serializeable)(s).serializeExchange(mStream);
            mStream.reset(ObjectStream.Mode.Error, null);
        }
        foreach (Object o; mRootSet) {
            doSerialize(o);
        }
        while (mNewObjectQueue.length) {
            Object[] queue = mNewObjectQueue;
            mNewObjectQueue = null;
            foreach (o; queue) {
                doSerialize(o);
            }
        }
    }
}

class Deserializer : SerializeBase {
    void deserialize(ConfigNode data) {
        if (data.getStringValue("comment") != cSerializerVersion)
            throw new Exception("oh noes!");
        //read externals; if an external object in this file wasn't added to
        //out SerializeBase, it's a user error (or bad file)
        foreach (char[] name, char[] value; data.getSubNode("externals")) {
            Object o = getExternal(name);
            setObjectID(o, parseID(value));
        }
        //first deserialization pass: create objects
        auto objsnode = data.getSubNode("objects");
        foreach (ConfigNode sub; objsnode) {
            Object c = cast(Object)
                mClasses.instantiate(sub.getStringValue("_class"), null);
            setObjectID(c, parseID(sub.name));
        }
        //second pass: actually deserialize
        //it's separate because else, objects couldn't be looked up
        foreach (ConfigNode sub; objsnode) {
            auto id = parseID(sub.name);
            Object o = lookupID(id);
            mStream.reset(ObjectStream.Mode.Read, sub);
            castStrict!(Serializeable)(o).serializeExchange(mStream);
            mStream.reset(ObjectStream.Mode.Error, null);
        }
        //load roots table
        foreach (char[] name, char[] value; data.getSubNode("roots")) {
            addRoot(name, lookupID(parseID(value)));
        }
        //yay
    }
}

//I/O
class ObjectStream {
    enum Mode {
        Error,
        Read,
        Write,
    }

    private {
        SerializeBase mOwner;
        Mode mMode;
        ConfigNode mCur;
    }

    this(SerializeBase s) {
        mOwner = s;
    }

    void reset(Mode m, ConfigNode target) {
        mMode = m;
        mCur = target;
    }

    MyBox read(char[] name, TypeInfo type) {
        assert(mMode == Mode.Read);
        //fehler/default-wert bei nicht vorhandener config-node?
        auto val = mCur.getStringValue(name);
        return mOwner.io.read(type, val);
    }

    void write(char[] name, MyBox data) {
        assert(mMode == Mode.Write);
        mCur.setStringValue(name, mOwner.io.write(data));
    }

    void exchange(T)(char[] name, ref T data) {
        //generische Methode so klein wie möglich halten
        if (mMode == Mode.Read) {
            static if (is(T == interface)) {
                data = castStrict!(T)(read(name, typeid(Object))
                    .unbox!(Object)());
            } else {
                data = read(name, typeid(T)).unbox!(T)();
            }
        } else if (mMode == Mode.Write) {
            static if (is(T == interface)) {
                write(name, MyBox.Box!(Object)(data));
            } else {
                write(name, MyBox.Box(data));
            }
        } else {
            assert(false);
        }
    }
}


//------------------------ test
debug:

import std.stdio;

class TestC1 : Serializeable {
    int foo;
    int goo;
    TestC2 reference;
    TestC1 hurr;

    this(SerializeCtor sc) {
    }
    this() {
    }

    void serializeExchange(ObjectStream stream) {
        stream.exchange("foo", foo);
        stream.exchange("goo", goo);
        stream.exchange("reference", reference);
        stream.exchange("hurr", hurr);
    }
    void serializeFixup() {
    }
}

class TestC2 : Serializeable {
    int haha;
    TestC1 backref;
    Ext1 e1;

    this(SerializeCtor sc) {
    }
    this() {
    }

    void serializeExchange(ObjectStream stream) {
        stream.exchange("haha", haha);
        stream.exchange("backref", backref);
        stream.exchange("e1", e1);
    }
    void serializeFixup() {
    }
}

MyBox read_int(char[] s) {
    return MyBox.Box!(int)(conv.toInt(s));
}
char[] write_int(MyBox d) {
    return str.format("%d", d.unbox!(int)());
}

MyBox read_str(char[] s) {
    return MyBox.Box!(char[])(s);
}
char[] write_str(MyBox d) {
    return d.unbox!(char[])();
}

void registerClasses(SerializeBase sb) {
    sb.registerClass!(TestC1)("TestC1");
    sb.registerClass!(TestC2)("TestC2");
    sb.io.register(typeid(int), &read_int, &write_int);
    sb.io.register(typeid(char[]), &read_str, &write_str);
}

class Ext1 {
}

void main() {
    //zu testender objektgraph
    auto e1 = new Ext1();
    auto r1 = new TestC1();
    r1.foo = 123;
    r1.goo = 666;
    r1.reference = new TestC2();
    r1.reference.haha = 574;
    r1.reference.e1 = e1;
    r1.reference.backref = r1;
    r1.hurr = new TestC1();
    r1.hurr.foo = 120;
    r1.hurr.goo = 550;
    r1.hurr.reference = r1.reference;
    //serialisieren
    Serializer s = new Serializer();
    registerClasses(s);
    s.addExternal("ext1", e1);
    s.addRoot("root", r1);
    auto cnf = new ConfigNode();
    writefln("start serialize1");
    s.serialize(cnf);
    writefln("end serialize1, output:");
    auto so = new StringOutput();
    cnf.writeFile(so);
    writefln("> %s <", so.text);
    //deserialisieren
    Deserializer ds = new Deserializer();
    registerClasses(ds);
    ds.addExternal("ext1", e1);
    writefln("start deserialize1");
    ds.deserialize(cnf);
    writefln("end deserialize1");
    auto r1_2 = castStrict!(TestC1)(ds.getRoot("root"));
    assert(r1_2.foo == r1.foo);
    assert(r1_2.reference.e1 is e1);
    //nochmal serialisieren
    Serializer s2 = new Serializer();
    registerClasses(s2);
    s2.addExternal("ext1", e1);
    s2.addRoot("root", r1_2);
    auto cnf2 = new ConfigNode();
    writefln("start serialize2");
    s2.serialize(cnf2);
    writefln("end serialize2");
    so.text = null;
    cnf2.writeFile(so);
    writefln("> %s <", so.text);
}
