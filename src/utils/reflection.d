//doing all those things which D/Phobos should provide us
module utils.reflection;

import std.ctype : isalnum;
import str = std.string;
import std.traits : isStaticArray;
import utils.misc;
import utils.mybox;

debug import std.stdio;

///Pointer which carries type infos
///Compared to D, the type is the type pointed to
///e.g. a SafePtr(int, ...) corresponds to int*
///Because in D, "Object x;" is like "ActualMemory* x;" (object references are
/// always... references), ptr is _never_ equal to the value of x (in the same
/// way how in "int x;" ptr will never equal to x); this sucks a bit, but I
/// find it still better than to introduce a new pseudotype which would
/// correspond to "ActualMemory" in the above example.
///uses class Type, not directly the D TypeInfo
///which is why this might not be useful in general, because you can't simply
/// convert a TypeInfo to a Type
///Warning: this is always a pointer to the real data, even if the real data is
///         an object reference or a pointer
struct SafePtr {
    Type type;
    void* ptr;

    //throw an appropriate exception if types are incompatible
    void check(TypeInfo ti) {
        if (ti !is type.mTI)
            throw new Exception("incompatible types");
    }

    //check if exactly the same type (no conversions) and not a null ptr
    void checkExactNotNull(Type needed, char[] caller) {
        if (!ptr)
            throw new Exception("null SafePtr passed to " ~ caller);
        if (type !is needed)
            throw new Exception("SafePtr of wrong type passed to " ~ caller);
    }

    SafePtr deref() {
        if (!ptr)
            throw new Exception("deref() null pointer");
        PointerType pt = cast(PointerType)type;
        if (!pt)
            throw new Exception("deref() on non-pointer type");
        return SafePtr(pt.next, *cast(void**)ptr);
    }

    //returns the actual pointer to the object
    //this is like "Object x = something(); return (void*)x;"
    //in other cases, return the ptr itself (that's do-what-I-mean sometimes)
    void* realptr() {
        if (!cast(ReferenceType)type)
            return ptr;
        return *cast(void**)ptr;
    }

    //if null object reference
    //for other types (e.g. pointers), undefined return value
    bool isNullObject() {
        return !!realptr();
    }

    //return a pointer with the actual class as static type
    //  memory = you must provide some space, where the SafePtr will point to
    //           this is because SafePtr is always a pointer to the object
    //           reference, and casting interfaces might change the reference
    SafePtr mostSpecificClass(void** memory) {
        if (type is null || ptr is null)
            return *this;
        auto rt = cast(ReferenceType)type;
        if (!rt)
            throw new Exception("mostSpecificClass() on non-reference ptr");
        Object o = rt.castFrom(*cast(void**)ptr);
        assert (!!o);
        ReferenceType* rt2 = o.classinfo in type.mOwner.mCItoT;
        if (!rt2)
            throw new Exception("class not found, maybe it is not reflected?");
        *memory = (*rt2).castTo(o);
        return SafePtr(*rt2, memory);
    }

    //"strict" typed cast (no implicit conversions)
    T* castTo(T)() {
        check(typeid(T));
        return cast(T*)ptr;
    }

    MyBox box() {
        MyBox res;
        if (type !is null)
            res.boxFromPtr(type.typeInfo(), ptr);
        return res;
    }
}

//how the D compiler layouts a delegate
//args this is ABI dependent, but D doesn't allow to write to the delegate's
//.ptr and .funcptr properties, so we have to do this evil thing
//(ABI = can be different from platform to platform)
struct D_Delegate {
    void* ptr;
    void* funcptr;
}

//wow, an union template!
union DgConvert(T) {
    static assert(is(T == delegate));
    static assert(d1.sizeof == d2.sizeof);
    D_Delegate d1;
    T d2;
}

static this() {
    //test if the delegate ABI is as expected
    class TestDg { void foo() {} }
    TestDg t = new TestDg();
    auto dg = &t.foo;
    DgConvert!(typeof(dg)) dgc;
    dgc.d2 = dg;
    if (!(dgc.d1.ptr is dgc.d2.ptr && dgc.d1.funcptr is dgc.d2.funcptr))
        throw new Exception("ABI test in reflection.d failed.");
}

///Types used to make a reflected class' constructor different from the
///standard constructor
///The constructor of a reflected class looks like this:
///  this(ReflectCtor c) {} //durrrr
interface ReflectCtor {
}

bool isReflectableClass(T)() {
    ReflectCtor c;
    return is(typeof(new T(c)));
}

class Types {
    private {
        //argh, D doesn't provide ClassInfo -> TypeInfo
        ReferenceType[ClassInfo] mCItoT;
        //D types to internal ones
        Type[TypeInfo] mTItoT;
    }

    final Type[] allTypes() {
        return mTItoT.values;
    }

    final Class findClass(Object o) {
        ReferenceType* pt = o.classinfo in mCItoT;
        return pt ? (*pt).klass() : null;
    }

    final SafePtr ptrOf(T)(ref T x) {
        return toSafePtr(typeid(T), &x);
    }

    final SafePtr toSafePtr(TypeInfo ti, void* ptr) {
        return SafePtr(tiToT(ti), ptr);
    }

    ///TypeInfo -> Type; only works if the type was encountered at compile time
    /// can_fail = if false, throw an exception if the type can't be found,
    ///            else return null
    final Type tiToT(TypeInfo ti, bool can_fail = false) {
        Type* t = ti in mTItoT;
        if (t)
            return *t;
        if (can_fail)
            return null;
        throw new Exception("Type for TypeInfo >"~ti.toString()~"< not found");
    }

    final Class registerClass(T)() {
        static assert (isReflectableClass!(T)(), "not reflectable");
        TypeInfo ti = typeid(T);
        ReferenceType t = castStrict!(ReferenceType)(getType!(T)());
        //already described? it's called recursively?
        if (t.klass())
            return t.klass();
        ReflectCtor c;
        T dummy = new T(c);
        auto def = new DefineClass(this, t, dummy);
        def.autoclass!(T)();
        return t.klass();
    }

    private void addType(Type t) {
        assert(!(t.mTI in mTItoT));
        mTItoT[t.mTI] = t;
        if (auto cit = cast(TypeInfo_Class)t.typeInfo()) {
            assert (!(cit.info in mCItoT));
            mCItoT[cit.info] = castStrict!(ReferenceType)(t);
        }
    }

    private void addBaseTypes(T...)() {
        foreach (Type; T) {
            new BaseType(this, typeid(Type), Type.stringof);
        }
    }

    ///Return a Type describing T; if T is a base type, an array/a-array, a
    ///class/interface reference, a delegate, or an already defined enum.
    ///The difference to tiToT() is, that tiToT() might not know all types,
    ///while this function can create Type instances on demand.
    final Type getType(T)() {
        Type res = tiToT(typeid(T), true);
        if (res)
            return res;
        //create instance for a type
        static if (is(T == class) || is(T == interface)) {
            return ReferenceType.create!(T)(this);
        } else static if (is(T == struct)) {
            return StructType.create!(T)(this);
        } else static if (is(T T2 : T2*)) {
            return PointerType.create!(T)(this);
        } else static if (is(T == delegate)) {
            return DelegateType.create!(T)(this);
        } else static if (is(T T2 == enum)) { //enum, T2 is underlying type
            return EnumType.create!(T)(this);
        } else static if (is(T T2 : T2[])) { //array, T2 is element type
            return ArrayType.create!(T)(this);
        /*} else static if (isAssocArrayType!(T)) {
            return new MapTypeImpl!(T)(this);*/
        } else {
            //nothing found
            assert(false, "can't handle type " ~ T.stringof);
        }
    }

    this() {
        //there are a lot of more base types in D, it's ridiculous!
        //add if needed
        addBaseTypes!(char, byte, ubyte, short, ushort, int, uint, long, ulong,
            float, double, real, bool)();
        writefln("done");
    }
}

class Type {
    private {
        Types mOwner;
        TypeInfo mTI;
        size_t mSize;
    }

    private this(Types a_owner, TypeInfo a_ti) {
        mOwner = a_owner;
        mTI = a_ti;
        mSize = mTI.tsize();
        mOwner.addType(this);
    }

    final TypeInfo typeInfo() {
        return mTI;
    }

    final size_t size() {
        return mSize;
    }
}

class BaseType : Type {
    private char[] mName;

    private this(Types a_owner, TypeInfo a_ti, char[] a_name) {
        super(a_owner, a_ti);
        mName = a_name;
    }

    override char[] toString() {
        return "BaseType[" ~ mName ~ "]";
    }
}

class StructuredType : Type {
    private {
        Class mClass;
    }

    //might return null, if the class/struct itself was not described yet
    final Class klass() {
        return mClass;
    }

    //don't use this, use create(T)(a_owner)
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }
}

//interfaces or object references
class ReferenceType : StructuredType {
    private {
        bool mIsInterface; //?
        void* function(Object obj) mCastTo;
        Object function(void* ptr) mCastFrom;
    }

    //don't use this, use create(T)(a_owner)
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    //returns null, if the conversion is not possible
    //the type of the thing pointed to by void* must be equal to typeInfo()
    final void* castTo(Object obj) {
        return mCastTo(obj);
    }
    final Object castFrom(void* ptr) {
        return mCastFrom(ptr);
    }

    ///Cast to the exact static type of this class
    ///only works for the following types of conversions:
    /// 1. interface <=> interface
    /// 2. object <=> interface
    ///can_fail: if false, throw an Exception if conversion failed.
    final SafePtr castAny(SafePtr from, bool can_fail = false) {
        if (from.type is this)
            return from;
        SafePtr res;
        res.type = this;
        if (!from.type) {
            assert (!from.ptr);
            return res;
        }
        if (auto rtype = cast(ReferenceType)from.type) {
            assert (rtype is from.type);
            Object o = rtype.castFrom(from.ptr);
            res.ptr = castTo(o);
        }
        if (!res.ptr && !can_fail)
            throw new Exception("type cast with castFrom() failed.");
        return res;
    }

    private static ReferenceType create(T)(Types a_owner) {
        ReferenceType t = new ReferenceType(a_owner, typeid(T));
        t.mIsInterface = is(T == interface);
        t.mCastTo = function void*(Object obj) {
            return cast(void*)cast(T)obj;
        };
        t.mCastFrom = function Object(void* ptr) {
            return cast(Object)cast(T)ptr;
        };
        return t;
    }

    override char[] toString() {
        return "ReferenceType[" ~ (mClass ? mClass.name() : "?") ~ "]";
    }
}

class StructType : StructuredType {
    private {
    }

    //don't use this, use create(T)(a_owner)
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    private static StructType create(T)(Types a_owner) {
        StructType t = new StructType(a_owner, typeid(T));
        DefineClass dc = new DefineClass(a_owner, t);
        dc.autostruct!(T)();
        return t;
    }

    override char[] toString() {
        return "StructType[" ~ (mClass ? mClass.name() : "?") ~ "]";
    }
}

class PointerType : Type {
    private {
        Type mNext;
    }

    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    final Type next() {
        return mNext;
    }

    private static PointerType create(T)(Types a_owner) {
        PointerType t = new PointerType(a_owner, typeid(T));
        static if (is(T T2 : T2*)) {
            t.mNext = t.mOwner.getType!(T2)();
        } else {
            static assert (false, "not a pointer type");
        }
        return t;
    }

    override char[] toString() {
        return "PointerType[" ~ mNext.toString() ~ "]";
    }
}

class EnumType : Type {
    private {
        Type mUnderlying;
    }

    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    private static EnumType create(T)(Types a_owner) {
        EnumType t = new EnumType(a_owner, typeid(T));
        static if (is(T T2 == enum)) {
            t.mUnderlying = t.mOwner.getType!(T2)();
        } else {
            static assert (false, "not an enum type");
        }
        assert (t.size() == t.mUnderlying.size());
        return t;
    }

    override char[] toString() {
        return "EnumType[" ~ mUnderlying.toString() ~ "]";
    }
}

class ArrayType : Type {
    private {
        Type mMember;  //type of the array items
        bool mIsStatic;
        Array function(ArrayType t, SafePtr array) mGetArray;
        void function(ArrayType t, SafePtr array, size_t len) mSetLength;
    }

    //(don't worry, not aliased to the compiler's internal data structure)
    struct Array {
        size_t length;
        SafePtr ptr; //pointer to first element

        SafePtr get(size_t element) {
            if (element >= length)
                throw new Exception("out of bounds");
            return SafePtr(ptr.type, ptr.ptr + element*ptr.type.size());
        }
    }

    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    final Type memberType() {
        return mMember;
    }

    //return a copy of the array descriptor
    Array getArray(SafePtr array) {
        array.checkExactNotNull(this, "Array.getArray()");
        return mGetArray(this, array);
    }
    //same as assigning the length property of a normal D array
    void setLength(SafePtr array, size_t len) {
        array.checkExactNotNull(this, "Array.setLength()");
        mSetLength(this, array, len);
    }

    private static ArrayType create(T)(Types a_owner) {
        ArrayType t = new ArrayType(a_owner, typeid(T));
        static if (is(T T2 : T2[])) {
            t.mMember = t.mOwner.getType!(T2)();
        } else {
            static assert (false, "not an array type");
        }
        t.mIsStatic = isStaticArray!(T);
        t.mSetLength = function void(ArrayType t, SafePtr array, size_t len) {
            static if (isStaticArray!(T)) {
                T* ta = array.castTo!(T)();
                (*ta).length = len;
            } else {
                throw new Exception("setting the length of a static array");
            }
        };
        t.mGetArray = function Array(ArrayType t, SafePtr array) {
            T* ta = array.castTo!(T)();
            Array res;
            res.length = (*ta).length;
            res.ptr.ptr = (*ta).ptr;
            res.ptr.type = t.mMember;
            return res;
        };
        return t;
    }

    override char[] toString() {
        return "ArrayType[" ~ mMember.toString() ~ "]";
    }
}

/*
class MapType : Type {
    private {
        Type mKey, mValue;  //aa is Value[Key]
        bool mIsStatic;
    }

    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    //length of the aa
    abstract size_t getLength(SafePtr map);
    //a pointer to the value, actually like: "return key in map;"
    abstract SafePtr getValuePtr(SafePtr map, SafePtr key);
    //like "map[key] = value;"
    abstract void setKey(SafePtr map, SafePtr key, SafePtr value);
    //like "foreach(key, value; map) { cb(key, value); }"
    abstract void iterate(SafePtr map,
        void delegate cb(SafePtr key, SafePtr value));
}

class MapTypeImpl(T) : Type {
    static assert(isAssocArrayType!(T));
    alias typeof(T.init.values[0]) V;
    alias typeof(T.init.values[0]) K;

    private this(Types a_owner) {
        super(a_owner, typeid(T));
        mKey = mOwner.getType!(K);
        mValue = mOwner.getType!(V);
    }

    override size_t getLength(SafePtr map) {
        return (*map.castTo!(T)()).length;
    }

    override SafePtr getValuePtr(SafePtr map, SafePtr key) {
        return (*key.castTo!(K)()) in (*map.castTo!(T)());
    }

    override void setKey(SafePtr map, SafePtr key, SafePtr value) {
        (*map.castTo!(T)())[*key.castTo!(K)()] = *value.castTo!(V)();
    }

    override void iterate(SafePtr map,
        void delegate cb(SafePtr key, SafePtr value))
    {
        foreach (K key, V value; *map.castTo!(T)()) {
            cb(SafePtr.get!(K)(mKey, &key), SafePtr.get!(V)(mValue, &value));
        }
    }
}
*/

/*
class DelegateType : Type {

    //NOTE: although there is is(T T2 == delegate), where T2 should be the
    //  function type of the delegate, this doesn't work as I thought or it
    //  is buggy, so work it around
    T tmp;
    alias typeof((cast(T)null).funcptr) T2;
}
*/

///Describes the contents of a class or a struct
///This is not derived from Type, because ReferenceType is actually used to
///describe classes and interfaces. However, the class "Class" provides further
///information (like members), which can only be obtained at compiletime.
class Class {
    private {
        StructuredType mOwner;
        ClassInfo mCI;
        Class mSuper;
        size_t mClassSize; //just used for verificating stuff
        char[] mName;
        ClassElement[] mElements;
        Object mDummy; //for default values
    }

    private this(ReferenceType a_owner, TypeInfo_Class cti, Object dummy) {
        mOwner = a_owner;
        mCI = cti.info;
        mClassSize = mCI.init.length;
        mDummy = dummy;
        assert (mOwner.typeInfo() is cti);
        assert (cti.info is dummy.classinfo);
        assert (!a_owner.mClass);
        a_owner.mClass = this;
    }

    private this(StructType a_owner) {
        mOwner = a_owner;
        mClassSize = a_owner.size();
        assert (!a_owner.mClass);
        a_owner.mClass = this;
    }

    private void addElement(ClassElement e) {
        foreach (ClassElement old; mElements) {
            //NOTE: the only way this can happen is (besides an internal error)
            //      template mixins which are used several times
            assert (old.name() != e.name());
        }
        mElements = mElements ~ e;
    }

    final ClassElement[] elements() {
        return mElements;
    }

    final char[] name() {
        return mName;
    }

    final StructuredType type() {
        return mOwner;
    }

    final Class superClass() {
        return mSuper;
    }

    final bool isClass() {
        return !!mCI;
    }

    final bool isStruct() {
        return !isClass();
    }
}

//share code for ClassMember & ClassMethod
class ClassElement {
    private {
        Class mOwner;
        char[] mName;
    }

    private this(Class a_owner, char[] a_name) {
        mOwner = a_owner;
        mName = a_name;
        mOwner.addElement(this);
    }

    final char[] name() {
        return mName;
    }
}

///Class member as in a variable declaration in a class
class ClassMember : ClassElement {
    private {
        Type mType;
        size_t mOffset; //byte offset
    }

    private this(Class a_owner, char[] a_name, Type a_type, size_t a_offset) {
        super(a_owner, a_name);
        mType = a_type;
        mOffset = a_offset;
    }

    final Type type() {
        return mType;
    }

    final size_t offset() {
        return mOffset;
    }

    ///Return a pointer to the member of the passed object
    ///  obj = pointer to the object reference, must be of the exact type
    ///Note that the semantic is the same like in D: &someobject.member will
    ///return a pointer to member.
    SafePtr get(SafePtr obj) {
        obj.checkExactNotNull(mOwner.mOwner, "ClassMember.get()");
        void* ptr = obj.realptr();
        assert (!!ptr);
        return SafePtr(mType, ptr + mOffset);
    }
}

///Method of a class
///at least needed for serializing delegates
class ClassMethod : ClassElement {
    private {
        //type of the function ptr of the delegate
        TypeInfo_Function mFunctionTI;
        //address of the code
        void* mAddress;
    }

    private this(Class a_owner, char[] a_name, TypeInfo fti, void* addr) {
        super(a_owner, a_name);
        mFunctionTI = castStrict!(TypeInfo_Function)(fti);
        mAddress = addr;
    }

    ///invoke the method with a signature known at compile-time
    ///the argument types must fit exactly (no implicit conversions)
    /// T_ret = return type
    /// T... = signature of the method
    /// ptr = object on which the method should be called
    T_ret invoke(T_ret, T...)(SafePtr ptr, T args) {
        alias T_ret delegate(T) dg_t;
        if (typeid(dg_t) !is mTI)
            throw new Exception("wrong signature for method call");
        ptr.check(mOwner.mTI);
        DgConvert!(dg_t) dgc;
        dgc.ptr = ptr.ptr;
        dgc.funcptr = mAddress;
        //actually call it
        return dgc.d2(args);
    }
}

class DefineClass {
    private {
        Class mClass;
        Types mBase;
    }

    //ti = TypeInfo of the defined class
    this(Types a_owner, ReferenceType t, Object dummy) {
        auto cti = castStrict!(TypeInfo_Class)(t.typeInfo());
        mClass = new Class(t, cti, dummy);
        mBase = a_owner;
    }

    this(Types a_owner, StructType t) {
        mClass = new Class(t);
        mBase = a_owner;
    }

    void autoclass(T)() {
        mClass.mName = T.stringof;
        T obj;
        static if (is(T == class)) {
            assert (!!mClass.mDummy);
            obj = castStrict!(T)(mClass.mDummy);
            T obj_addr = obj;
        } else {
            T* obj_addr = &obj;
        }
        size_t[] offsets;
        Type[] member_types;
        size_t member_count = obj.tupleof.length;
        offsets.length = member_count;
        member_types.length = member_count;
        foreach (int index, x; obj.tupleof) {
            //this is a manual .offsetof
            //it sucks much less than the compiler's builtin one
            auto p_obj = cast(void*)obj_addr;
            auto p_member = cast(void*)&obj.tupleof[index];
            offsets[index] = cast(size_t)p_member - cast(size_t)p_obj;
            member_types[index] = mBase.getType!(typeof(x))();
            //doesn't work! search for "dmd tupleof-enum bug"
            //char[] name = obj.tupleof[i].stringof;
            //recurse!
            static if (isReflectableClass!(typeof(x))()) {
                mBase.registerClass!(typeof(x))();
            }
        }
        //since the direct approach doesn't work, do this to get member names:
        //parse the tupleof string
        char[] names = obj.tupleof.stringof;
        const cPrefix = "tuple(";
        const cSuffix = ")";
        assert (startsWith(names, cPrefix));
        assert (endsWith(names, cSuffix));
        names = names[cPrefix.length .. $ - cSuffix.length];
        char[][] parsed_names = str.split(names, ",");
        assert (parsed_names.length == member_count);
        foreach (ref char[] name; parsed_names) {
            //older compiler versions include the name in ()
            //who knows in which ways future compilers will break this
            if (name.length && name[0] == '(' && name[$-1] == ')')
                name = name[1 .. $-1];
            char[] objstr = obj.stringof;
            assert (startsWith(name, objstr));
            name = name[objstr.length .. $];
            assert (name.length > 0 && name[0] == '.');
            name = name[1 .. $];
            //must be a valid D identifier now
            for (int n = 0; n < name.length; n++) {
                assert (isalnum(name[n]) || name[n] == '_');
            }
        }
        //actually add the fields
        for (int n = 0; n < member_count; n++) {
            addField(parsed_names[n], member_types[n], offsets[n]);
        }
        //handle super classes
        static if (is(T S == super)) {
            static if (!is(S[0] == Object)) {
                mClass.mSuper = mBase.registerClass!(S[0])();
            }
        }
    }

    void autostruct(T)() {
        autoclass!(T)();
    }

    void addField(char[] name, Type type, size_t offset) {
        auto p_obj = cast(void*)mClass.mDummy;
        auto p_member = p_obj + offset;
        assert(p_member >= p_obj
            && p_member + type.size() <= p_obj + mClass.mClassSize);
        new ClassMember(mClass, name, type, offset);
    }

    /// define a field for the class being defined - must pass an unique name,
    /// and a reference pointing to same field in the dummy object
    /// called like this: .field("field0", &field0);
    void field(T)(char[] name, T* member) {
        addField(name, mBase.getType!(T)(),
            cast(void*)member - cast(void*)mClass.mDummy);
    }

    /// like field(), but for methods
    /// called like this: .method("method0", &method0);
    /// (a real delegate is passed, not a pointer)
    void method(T)(char[] name, T del) {
        static assert(is(T == delegate));
        DgConvert!(T) dgc;
        dgc.d2 = del;
        //must be a delegate to a method of mDummy
        assert(dgc.d1.ptr is cast(void*)mClass.mDummy);
        mClass.addMember(new ClassMethod(mClass.mOwner, name,
            typeid(typeof(del.funcptr)), dgc.d1.funcptr));
    }
}

import utils.test : Test;
static this() {
    Test z = new Test();
    char[] res;
    foreach (int index, x; z.tupleof) {
        res ~= z.tupleof[index].stringof ~ "|";
    }
    assert (res == "z.a|z.b|z.c|");
}

//-------
debug:

import utils.strparser;
import utils.list2;

enum X {
    xa,
    xb,
}

struct S {
    Test1 a;
    int b = 2;
    Test2 c;
}

class Test1 {
    int a = 1;
    int b = 2;
    char c = 'p';
    short[] d = [3,4,5];
    X e;
    Test2 f;
    S g;
    List2!(Test2) h;

    void foo() {
    }

    public this() {
    }

    public this(ReflectCtor ct) {
    }
}

class Test2 {
    int a = 1;
    float b = 2.45;
    Test1[] c;

    ListNode foo;

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

class Test3 : Test1 {
    ushort a = 1;
    char[] b = "hullo";

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

void main() {
    Types t = new Types();
    Class c = t.registerClass!(Test1)();
    foreach (Type type; t.allTypes()) {
        writefln("%s", type);
        if (auto rt = cast(StructuredType)type) {
            if (auto cl = rt.klass()) {
                writefln("  structured type '%s', known members:", cl.name());
                foreach (ClassElement e; cl.elements()) {
                    if (auto m = cast(ClassMember)e) {
                        writefln("  - %s @ %s : %s", m.name(), m.offset(),
                            m.type());
                    }
                }
            }
        }
    }
    Test1 x = new Test1();
    x.g.c = new Test2();
    x.g.c.c ~= x;
    x.g.c.c ~= new Test3();
    t.registerClass!(Test3)();
    SafePtr px = t.ptrOf(x);
    bool[void*] done;
    SafePtr[] items = [px];
    done[null] = true;
    assert (null in done);
    while (items.length) {
        SafePtr cur = items[0];
        assert (cur.ptr !is null);
        items = items[1..$];
        char[] sp2str(SafePtr sp) {
            char[] s = "?";
            auto b = sp.box();
            if (b.type() in gBoxUnParsers) {
                s = boxToString(b);
            } else if (auto r = cast(ReferenceType)sp.type) {
                s = "? " ~ str.format("%#8x", sp.realptr());
            } else {
                s = "? " ~ sp.type.toString();
            }
            return s;
        }
        void check(SafePtr pm) {
            if (cast(StructuredType)pm.type || cast(ArrayType)pm.type) {
                void* rptr = pm.realptr();
                if (!(rptr in done)) {
                    items ~= pm;
                    done[rptr] = true;
                }
            }
        }
        if (auto st = cast(StructuredType)cur.type) {
            void* tmp;
            if (cast(ReferenceType)cur.type)
                cur = cur.mostSpecificClass(&tmp);
            writefln("%s %s %#8x:", cast(StructType)st ? "class" : "struct",
                cur.type, cur.ptr);
            Class xc = castStrict!(StructuredType)(cur.type).klass();
            if (!xc) {
                writefln("  no info");
                continue;
            }
            while (xc) {
                cur.type = xc.type(); //xxx unclean
                foreach (ClassElement e; xc.elements()) {
                    if (auto m = cast(ClassMember)e) {
                        SafePtr pm = m.get(cur);
                        writefln("  %s = (%#8x) '%s'", m.name(), pm.ptr, sp2str(pm));
                        check(pm);
                    }
                }
                xc = xc.superClass();
            }
        } else if (auto art = cast(ArrayType)cur.type) {
            writef("    [");
            ArrayType.Array arr = art.getArray(cur);
            for (int i = 0; i < arr.length; i++) {
                if (i != 0)
                    writef(", ");
                writef(sp2str(arr.get(i)));
                check(arr.get(i));
            }
            writefln("]");
        }
    }
}

/+
This is what I call "dmd tupleof-enum bug":

Source:

import std.stdio;

enum X {
  bla
}

class Test {
   int a;
   X b;
}

void main() {
   Test t = new Test();
   writefln(t.tupleof.stringof);
   foreach (int i, x; t.tupleof) {
       writefln(t.tupleof[i].stringof);
   }
}

Output:
    tuple((t.a),(t.b))
    t.a
    int

The third line should be "t.b".
Newer dmd versions output the type of the enum instead of "int" or "t.b".
Status: doesn't work with v1.037

+/
