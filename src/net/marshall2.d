module net.marshall2;

import std.bitarray;
import std.string;
import std.traits;
import std.typetuple;

import net.encode;
import utils.buffer;
//import utils.staticbits;

///registers and lookups type handlers
class MarshallContext {
    private {
        Marshaller[TypeInfo] mMap;
    }

    Marshaller lookup(T)() {
        auto key = typeid(T);
        if (!(key in mMap)) {
            //first try to construct by well known recursive types...:
            Marshaller marshall;

            static if (isStaticArray!(T)) {
                //a static array
                marshall = new StaticArrayMarshaller!(T)(this);
            } else static if (is(T == struct)) {
                //a struct
                marshall = new StructMarshaller!(T)(this);
            }

            if (marshall) {
                register(marshall);
                return marshall;
            }
            throw new Exception("type not found: " ~ format(key));
        }
        return mMap[key];
    }
    void register(Marshaller m) {
        mMap[m.type()] = m;
    }
}

///Can marshall a D type which it's specialized on (i.e. StructMarshaller
///marshalls structs)
///Instantiate one using MarshallContext
///Pitfalls:
/// - Managed data must be able to be copied at once, as in D assignment
///   (implications: i.e. items of dynamic arrays must be immutable)
/// - Relies on D comparision to check for changes (i.e. tests if (a==b){...})
abstract class Marshaller {
    protected {
        TypeInfo mType;
    }

    final TypeInfo type() {
        return mType;
    }

    ///OS independent hash for this type to check for type compatibility over
    ///the network
    abstract char[] typeHash();

    ///NOTE about data pointers:
    ///     since generic access to (unmarshalled!) data is wishable and since
    ///     I somewhat failed at template mechanics, access is made generic by
    ///     moving the actual types templates into subclasses like
    ///     StructMarshaller, and above that you deal with somewhat-opaque
    ///     void* pointers.
    ///     They work similar to boxes: they can be copied by memcpy() without
    ///     breaking the D type system etc.; the size is fixed and given by
    ///     "type().tsize()".

    ///NOTE: Not overloadable, because the data structures are recursively
    ///     compared by D; this includes calls to opEqual()s.
    ///     If user-defined comparision is needed, override opEqual() of the
    ///     structs which are affected.
    ///     If this were overloadable, it wouldn't be clear whether the D or
    ///     the Marshaller mechanism is called (or: struct compares -> slower).
    ///Also: To just use D comparision in Marshallers is spread all over this
    ///      file, they won't use this function!
    ///And yes, these restrictions are just a speed optimization.
    final bool hasChanges(void* newdata, void* olddata) {
        return mType.compare(newdata, olddata) != 0;
    }

    ///write in_data into wr, delta-code against in_reference
    abstract void write(NetWriter wr, void* in_data, void* in_reference);
    ///read out_data from rd, which is delta-coded against in_reference
    abstract void read(NetReader rd, void* out_data, void* in_reference);

    ///copy in_data to result
    ///pretty trivial due to D's TypeInfo, haha
    final void* snapshot(void* in_data) {
        auto sz = mType.tsize();
        return in_data[0..sz].dup.ptr;
    }

    ///synchronize out_data with (local) in_sourcedata
    ///this is used when stuff actually isn't marshalled, but only copied
    ///Important: possibly clear out any "cached data"
    ///(i.e. clear the pointer of a NetRef, see there)
    ///but most time, simply copy as well
    ///NOTE: apart from hasChanges (possibly), the only function called in the
    ///     local non-network case
    void syncLocal(void* out_data, void* in_sourcedata) {
        auto sz = mType.tsize();
        //possible microoptimization: do this in a subclass where the type is
        //statically known, so it could be a real D language variable assignment
        out_data[0..sz] = in_sourcedata[0..sz];
    }
}

///NOTE: parts of it are compile-time, parts are runtime:
///      the struct members/types are really known at compile-time, but the
///      functions (i.e. read/write member) are at run-time
//xxx class was final, dmd doesn't like it (=> compiler error, bug I guess)
class StructMarshaller(T) : Marshaller {
    const cFieldCount = typeof(T.tupleof).length;
    private {
        //marshaller for each member
        Marshaller[cFieldCount] mFieldMarshallers;
        //offset into the struct for each member
        size_t[cFieldCount] mFieldOffsets;
    }

    this(MarshallContext ctx) {
        mType = typeid(T);

        T tmp1; //dummy for foreach()
        foreach (int index, tmp2; tmp1.tupleof) {
            //.offsetof really seems to work wrt. to the struct
            //(i.e. the tuple doesn't mess up alignments etc.)
            mFieldOffsets[index] = T.tupleof[index].offsetof;
            mFieldMarshallers[index] = ctx.lookup!(typeof(T.tupleof[index]))();
        }
    }

    override char[] typeHash() {
        char[] r = "s[";
        foreach (m; mFieldMarshallers) {
            r ~= m.typeHash ~ ".";
        }
        return r ~ "]";
    }

    final void write(NetWriter wr, void* in_data, void* in_reference) {
        T tmp1; //dummy member to foreach() over it (iterating with for -> noes)
        foreach (uint index, tmp2; tmp1.tupleof) {
            bool change = (cast(T*)in_data).tupleof[index] !=
                (cast(T*)in_reference).tupleof[index];
            write_bool(wr, change);
            if (change) {
                auto o = mFieldOffsets[index];
                auto m = mFieldMarshallers[index];
                m.write(wr, in_data+o, in_reference+o);
            }
        }
        //and this is the (also working, but out of date) dynamic version of it
        /+
        for (int i = 0; i < cFieldCount; i++) {
            auto o = mFieldOffsets[i];
            auto m = mFieldMarshallers[i];
            //simple D comparision to check if there's a change
            bool change = m.type.compare(in_data+o, in_reference+o) != 0;
            write_bool(wr, change);
            if (change) {
                m.write(wr, in_data+o, in_reference+o);
            }
        }
        +/
    }

    final void read(NetReader rd, void* out_data, void* in_reference) {
        for (int i = 0; i < cFieldCount; i++) {
            auto change = read_bool(rd);
            if (change) {
                auto o = mFieldOffsets[i];
                mFieldMarshallers[i].read(rd, out_data+o, in_reference+o);
            }
        }
    }
}

class StaticArrayMarshaller(T) : Marshaller {
    //following lines commented out, rebuild doesn't like it so much
    //static assert(isStaticArray!(T));
    const cLength = T.length;

    static if (is(T T2 : T2[])) {
        alias T2 RecursiveType;
    } else {
        static assert(false, "failed, no array?: " ~ T.stringof);
    }

    private {
        Marshaller mRecursive;
    }

    this(MarshallContext ctx) {
        mType = typeid(T);
        mRecursive = ctx.lookup!(RecursiveType)();
    }

    private RecursiveType* index(void* ptr, int n) {
        //no idea if this is correct, but still, it seems to work
        return &(*cast(T*)ptr)[n];
    }

    final void write(NetWriter wr, void* in_data, void* in_reference) {
        for (int n = 0; n < cLength; n++) {
            mRecursive.write(wr, index(in_data, n), index(in_reference, n));
        }
    }

    final void read(NetReader rd, void* out_data, void* in_reference) {
        for (int n = 0; n < cLength; n++) {
            mRecursive.read(rd, index(out_data, n), index(in_reference, n));
        }
    }

    char[] typeHash() {
        return format("A[%s/%s]", cLength, mRecursive.typeHash);
    }
}

//marshall using a read and a write function; required signatures:
//  T read_function_delta(T)(NetReaderer rd, T refvalue);
//  void write_function_delta(T)(NetWriterr wr, T newvalue, T refvalue);
class BaseMarshaller(T, alias read_function_delta, alias write_function_delta)
    : Marshaller
{
    this() {
        mType = typeid(T);
    }

    final void write(NetWriter wr, void* in_data, void* in_reference) {
        T a = *cast(T*)in_data;
        T b = *cast(T*)in_reference;
        write_function_delta(wr, a, b);
    }

    final void read(NetReader rd, void* out_data, void* in_reference) {
        T b = *cast(T*)in_reference;
        *cast(T*)out_data = read_function_delta(rd, b);
    }

    char[] typeHash() {
        return T.stringof;
    }
}

template IntMarshaller(T) {
    alias BaseMarshaller!(T, read_integer_delta, write_integer_delta)
        IntMarshaller;
}

template ByteMarshaller(T) {
    alias BaseMarshaller!(T, read_byte_delta, write_byte_delta) ByteMarshaller;
}

alias BaseMarshaller!(bool, read_bool_delta, write_bool_delta) BoolMarshaller;

//instantiate and register Marshallers for some base types
void registerBaseMarshallers(MarshallContext ctx) {
    TypeTuple!(
        IntMarshaller!(short), IntMarshaller!(ushort),
        IntMarshaller!(int), IntMarshaller!(uint),
        IntMarshaller!(long), IntMarshaller!(ulong),
        ByteMarshaller!(byte), ByteMarshaller!(ubyte), ByteMarshaller!(char),
        BoolMarshaller,
        BaseMarshaller!(float, read_float_delta, write_float_delta)
    ) stuff;
    //FYI: compiler "unrolls" this loop for each item (type) in the tuple
    foreach (x; stuff) {
        alias typeof(x) T; //wtf? template workings are strange
        auto marshaller = new T;
        ctx.register(marshaller);
    }
}

///helper function to serialize "any" (almost) type
///might be slow, but still useful for i.e. structs
///(not use as backend for net.netobject, hmm)
private MarshallContext getSerializer() {
    static MarshallContext gSerializer;
    if (!gSerializer) {
        gSerializer = new MarshallContext();
        registerBaseMarshallers(gSerializer);
    }
    return gSerializer;
}
void serialize(T)(NetWriter wr, ref T data) {
    auto ctx = getSerializer();
    auto marshall = ctx.lookup!(T)();
    //marshaller always requires delta coding (??), so delta-code against init
    T def;
    marshall.write(wr, &data, &def);
}
void unserialize(T)(NetReader rd, ref T data) {
    auto ctx = getSerializer();
    auto marshall = ctx.lookup!(T)();
    T def;
    marshall.read(rd, &data, &def);
}

debug import std.stdio;
debug struct Test {
    int a = 1;
    char b = 2;
    byte c = 3;
    uint d = 4;
    ubyte e = 5;
    short f = 6;
    long g = 7;
    ulong h = 8;
    ushort i = 9;
    bool j = true;
    struct Nested {
        int hurhur = 456;
        short[6] static_array = [1,2,3,4,5,6];
    }
    Nested k;
    float l = 1.0f;
}
unittest {
    auto ctx = new MarshallContext();
    registerBaseMarshallers(ctx);
    auto g = new StructMarshaller!(Test)(ctx);

    auto wr = new NetWriter();
    Test a1;
    a1.e = 0xF0; //shouldn't be "transmitted" in this test (delta coding)
    Test a2 = a1;
    assert(!g.hasChanges(&a1, &a2));
    a2.k.static_array[4] = 12345;
    assert(g.hasChanges(&a1, &a2));
    a2.h = 0x1234;
    a2.l = 2.0f;
    assert(g.hasChanges(&a1, &a2));
    g.write(wr, &a2, &a1);
    //writefln(wr.flush);
    auto rd = new NetReader(wr.flush);
    Test a3 = a1; //a3 must correspond to initial version
    assert(a3.k.static_array[4] == 5);
    g.read(rd, &a3, &a1); //must decode against the stuff it was delta-coded
    assert(a3 == a2);

    assert(g.typeHash ==
        "s[int.char.byte.uint.ubyte.short.long.ulong.ushort.bool"
        ".s[int.A[6/short].].float.]");

    debug writefln("net.marshall2 unittest passed.");
}
