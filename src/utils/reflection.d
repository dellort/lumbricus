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

    static const SafePtr Null = {null, null};

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
        if (auto rt = cast(ReferenceType)type) {
            if (!rt.isInterface())
                return *cast(void**)ptr;
        }
        return ptr;
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
    //           e.g. void* tmp; SafePtr p_tmp = x.mostSpecificClass(&tmp, ...)
    SafePtr mostSpecificClass(void** memory, bool may_fail = false) {
        Object o = toObject();
        if (!o)
            return SafePtr(null, null); //was a null reference
        ReferenceType* rt2 = o.classinfo in type.mOwner.mCItoT;
        if (!rt2 && !may_fail)
            throw new Exception("class not found, maybe it is not reflected?");
        if (!rt2)
            return SafePtr(null, null);
        *memory = (*rt2).castTo(o);
        return SafePtr(*rt2, memory);
    }

    SafePtr toObjectPtr(void** memory) {
        Object o = toObject();
        if (!o)
            return SafePtr(null, null);
        *memory = cast(void*)o;
        return SafePtr(type.mOwner.tiToT(typeid(typeof(o))), memory);
    }

    Object toObject(bool may_fail = false) {
        if (type is null || ptr is null)
            return null;
        auto rt = cast(ReferenceType)type;
        if (!rt && !may_fail)
            throw new Exception("toObject() on non-reference ptr");
        if (!rt)
            return null;
        return rt.castFrom(*cast(void**)ptr);
    }

    //"strict" typed cast (no implicit conversions)
    T* castTo(T)() {
        check(typeid(T));
        return cast(T*)ptr;
    }

    T read(T)() {
        return *castTo!(T)();
    }

    void write(T)(T data) {
        *castTo!(T) = data;
    }

    static SafePtr get(T)(Type t, T* ptr) {
        assert (t.typeInfo() == typeid(T));
        return SafePtr(t, ptr);
    }

    //return if "from" can be assigned to a variable pointed to by "this"
    //doesn't follow D semantics: if the cast fails, the destination isn't
    //assigned null, but is left untouched
    //warning: this.type must not be null
    //throws exception if type infos insufficient to check the cast
    //  (but actually, one could only use ClassInfo?)
    bool castAndAssignObject(Object from) {
        assert (!!type);
        auto rt = cast(ReferenceType)type;
        if (!rt)
            throw new Exception("target not an object or interface type");
        void* p = rt.castTo(from);
        if (!p && from)
            return false;
        *cast(void**)ptr = p;
        return true;
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
///oh, and also includes a way to get the Types class
///The constructor of a reflected class looks like this:
///  this(ReflectCtor c) {} //durrrr
interface ReflectCtor {
    Types types();

    ///mark a class member as transient (not serialized)
    ///member is still accessible for reflection
    ///set instance to this
    void transient(Object instance, void* member);

    ///with this function, the ctor can ask if the transient members shall be
    ///recreated (false for dummy members, true when deserializing objects)
    bool recreateTransient();
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
        ClassMethod[void*] mMethodMap;
        Class[char[]] mClassMap;
        FooHandler mFoo;
    }

    private class FooHandler : ReflectCtor {
        void delegate(size_t) mTransientHandler;
        bool mRecreate;

        override Types types() {
            return this.outer;
        }

        //need instance pointer because called while in constructor
        override void transient(Object instance, void* member) {
            if (mTransientHandler) {
                assert(!!instance && member);
                //get relative offset
                auto p_obj = cast(void*)instance;
                size_t rel_offset = cast(size_t)member - cast(size_t)p_obj;
                mTransientHandler(rel_offset);
            }
        }

        override bool recreateTransient() {
            return mRecreate;
        }
    }

    final Type[] allTypes() {
        return mTItoT.values;
    }

    final Class findClass(Object o) {
        if (!o)
            return null;
        ReferenceType* pt = o.classinfo in mCItoT;
        return pt ? (*pt).klass() : null;
    }

    final Class findClassByName(char[] name) {
        Class* pc = name in mClassMap;
        return pc ? *pc : null;
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

    //special handling for superclasses: this might not be instantiable (if they
    //are abstract), but they still need to be analyzed
    private final Class registerSuperClass(T)(Object dummy) {
        //static if (is(T == Object)) {
        //    return null;
        //}
        assert (!!dummy);
        assert (!!cast(T)dummy);
        static if (!isReflectableClass!(T)) {
            //abstract, but actually still reflectable base class?
            return doRegister!(T)(cast(T)dummy, null);
        } else {
            return registerClass!(T)();
        }
    }

    final Class registerClass(T)() {
        static assert (isReflectableClass!(T)(), "not reflectable: "~T.stringof);
        return doRegister!(T)(null, (ReflectCtor c) {
            return cast(Object)new T(c); }
        );
    }

    private Class doRegister(T)(T dummy, Object delegate(ReflectCtor c) inst) {
        ReferenceType t = castStrict!(ReferenceType)(getType!(T)());
        if (t.klass())
            return t.klass();
        auto cti = castStrict!(TypeInfo_Class)(t.typeInfo());
        auto klass = new Class(t, cti);
        assert (t.klass() is klass);
        klass.mName = cti.info.name;
        assert (!(klass.mName in mClassMap));
        mClassMap[klass.mName] = klass;
        klass.mCreateDg = inst;

        void membTransient(size_t relOffset) {
            klass.addTransientMember(relOffset);
        }

        if (!dummy) {
            //ctors can be called recursively
            //(when using registerClass() in a ctor)
            auto old = mFoo.mTransientHandler;
            mFoo.mTransientHandler = &membTransient;
            mFoo.mRecreate = false;
            ReflectCtor c = mFoo;
            dummy = cast(T)inst(c);
            //only during registration
            mFoo.mTransientHandler = old;
        }
        assert (!!dummy);
        klass.mDummy = dummy;
        auto def = new DefineClass(this, klass);
        def.autoclass!(T)();
        return t.klass();
    }

    final void registerClasses(T...)() {
        foreach (x; T) {
            registerClass!(x)();
        }
    }

    //NOTE: the owner field is required to check if the delegate points really
    //      to an object method (and not into the stack or so) (debugging)
    //name must be provided explicitely, there seems to be no other way
    final void registerMethod(T)(Object owner, T del, char[] name) {
        static assert (is(T == delegate));
        if (del.ptr !is cast(void*)owner)
            throw new Exception("not an object method?");
        Class klass = findClass(owner);
        //user is supposed to call registerMethod() in the reflection ctor, so
        //this shouldn't happen
        if (!klass)
            throw new Exception("class not registered");
        DelegateType dgt = cast(DelegateType)getType!(T)();
        assert (!!dgt);
        void* ptr = del.funcptr;
        assert (ptr.sizeof == del.funcptr.sizeof);
        klass.addMethod(dgt, ptr, name);
    }

/+
    //for all types call getType()
    final void encounter(T...)() {
        foreach (x; T) {
            getType!(x)();
        }
    }
+/

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
        } else static if (isAssocArrayType!(T)) {
            return MapType.create!(T)(this);
        } else {
            //nothing found
            assert(false, "can't handle type " ~ T.stringof);
        }
    }

    this() {
        mFoo = new FooHandler();
        //there are a lot of more base types in D, it's ridiculous!
        //add if needed
        addBaseTypes!(char, byte, ubyte, short, ushort, int, uint, long, ulong,
            float, double, real, bool)();
        getType!(Object)();
    }

    //returns true on success
    //if failed, return false and leave obj/method untouched
    bool readDelegate(SafePtr ptr, ref Object obj, ref ClassMethod method) {
        auto dgt = cast(DelegateType)ptr.type;
        if (!dgt) {
            //writefln("not a delegate type!");
            return false;
        }
        assert (!!ptr.ptr);
        D_Delegate* dp = cast(D_Delegate*)ptr.ptr;
        if (dp.ptr is null) {
            obj = null;
            method = null;
            return true;
        }
        ClassMethod* pm = dp.funcptr in mMethodMap;
        if (!pm) {
            //writefln("method not found");
            return false;
        }
        ClassMethod m = *pm;
        //if the code pointer points to a method, the ptr argument should be
        //the this pointer for the object (can't point into the stack etc.)
        Object o = cast(Object)dp.ptr;
        Class k = findClass(o);
        //can happen, when the actual object is derived from a registered one
        //(which is why we have a ClassMethod m, but not a Class)
        if (!k) {
            //writefln("class not registered");
            return false;
        }
        //assert (k.isSubTypeOf(method.klass()));
        /+ xxx
        if (!k.isSubTypeOf(m.klass())) {
            writefln("%s %s %s", k.name, m.klass.name, m.name);
        }
        assert (k.isSubTypeOf(m.klass()));
        +/
        obj = o;
        method = m;
        return true;
    }

    //overwrite the variable, which ptr points to, with obj/method
    //return false if failed (wrong types)
    bool writeDelegate(SafePtr ptr, Object obj, ClassMethod method) {
        auto dgt = cast(DelegateType)ptr.type;
        if (!dgt)
            throw new Exception("not a delegate pointer");
        assert (!!ptr.ptr);
        D_Delegate* dp = cast(D_Delegate*)ptr.ptr;
        if (obj) {
            Class k = findClass(obj);
            assert (!!k);
            //xxx for now disregard the following assert() urgs
            //assert (k.isSubTypeOf(method.klass()));
            if (method.mDgType !is ptr.type)
                return false;
        }
        dp.ptr = cast(void*)obj;
        dp.funcptr = method ? method.address() : null;
        return true;
    }
}

class Type {
    private {
        Types mOwner;
        TypeInfo mTI;
        size_t mSize;
        void[] mInit;
    }

    private this(Types a_owner, TypeInfo a_ti) {
        mOwner = a_owner;
        mTI = a_ti;
        mSize = mTI.tsize();
        mInit = mTI.init();
        //this check can be removed - just wanted to see if we maybe allocate
        //too much memory due to this function
        if (mSize > 16*1024)
            assert(false, "that's very big data: "~mTI.toString());
        if (!mInit.length) {
            mInit = new ubyte[mSize];
        }
        if (mInit.length != mSize) {
            //ok, it seems for static arrays, TypeInfo.init() contains only the
            //init data for the first element to save memory
            assert (!!cast(TypeInfo_StaticArray)mTI);
            assert ((mSize/mInit.length)*mInit.length == mSize);
            //fix by repeating the first element
            size_t oldlen = mInit.length;
            mInit.length = mSize;
            for (int n = 1; n < mSize/oldlen; n++) {
                mInit[n*oldlen .. (n+1)*oldlen] = mInit[0..oldlen];
            }
        }
        mOwner.addType(this);
    }

    final TypeInfo typeInfo() {
        return mTI;
    }

    final size_t size() {
        return mSize;
    }

    //default value, if this type is declared "stand alone" without initializer
    final void[] initData() {
        return mInit;
    }

    //same as initData, actually redundant, maybe remove initData()
    final SafePtr initPtr() {
        return SafePtr(this, mInit.ptr);
    }

    final Types owner() {
        return mOwner;
    }

    //compare two values with the is operator
    //the types of both pa and pb must be this type
    //xxx: currently do a byte-for-byte comparision, which "should" be ok in
    //     most cases
    bool op_is(SafePtr pa, SafePtr pb) {
        if (pa.type !is this || pb.type !is this)
            throw new Exception("type error");
        return pa.ptr[0..mSize] == pb.ptr[0..mSize];
    }

    //xxx: same as in op_is()
    final void assign(SafePtr dest, SafePtr src) {
        if (dest.type !is src.type)
            throw new Exception("type error");
        dest.ptr[0..mSize] = src.ptr[0..mSize];
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
        ClassInfo mInfo;
        bool mIsInterface;
        void* function(Object obj) mCastTo;
        Object function(void* ptr) mCastFrom;
    }

    //don't use this, use create(T)(a_owner)
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
        auto cit = cast(TypeInfo_Class)mTI;
        auto iit = cast(TypeInfo_Interface)mTI;
        assert (cit || iit);
        if (cit) {
            mInfo = cit.info;
        } else {
            mInfo = iit.info;
        }
    }

    final bool isInterface() {
        return mIsInterface;
    }

    final ClassInfo classInfo() {
        return mInfo;
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
    ///xxx slightly unsafe, because it can return a pointer to a variable with
    ///    a completely different type
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

    final Type underlying() {
        return mUnderlying;
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
        int mStaticLength;
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

    //-1 if not a static array, else the length
    final int staticLength() {
        return mStaticLength;
    }

    final bool isStatic() {
        return mStaticLength >= 0;
    }

    final Type memberType() {
        return mMember;
    }

    //return a copy of the array descriptor
    //xxx doesn't match with D semantics, blergh
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
        t.mStaticLength = -1;
        if (isStaticArray!(T)) {
            T x;
            t.mStaticLength = x.length; //T.init doesn't work???
        }
        t.mSetLength = function void(ArrayType t, SafePtr array, size_t len) {
            static if (!isStaticArray!(T)) {
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
        if (staticLength() < 0) {
            return "ArrayType[" ~ mMember.toString() ~ "]";
        } else {
            return str.format("ArrayType[%s[%d]]", mMember, staticLength());
        }
    }
}

class MapType : Type {
    private {
        Type mKey, mValue;  //aa is Value[Key]
    }

    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    final Type keyType() {
        return mKey;
    }
    final Type valueType() {
        return mValue;
    }

    //length of the aa
    abstract size_t getLength(SafePtr map);
    //a pointer to the value, actually like: "return key in map;"
    abstract SafePtr getValuePtr(SafePtr map, SafePtr key);
    //like "map[key] = value;"
    abstract void setKey(SafePtr map, SafePtr key, SafePtr value);
    //this fuckery is to enable us to deserialize a map without allocating
    //"dummy" memory for key/value, and then call setKey to copy them in
    //both delegates are guaranteed to be called only once, key is called first
    abstract void setKey2(SafePtr map, void delegate(SafePtr key) dg_getKey,
        void delegate(SafePtr value) dg_getValue);
    //like "foreach(key, value; map) { cb(key, value); }"
    abstract void iterate(SafePtr map,
        void delegate(SafePtr key, SafePtr value) cb);

    private static MapType create(T)(Types a_owner) {
        //MapType t = new MapType(a_owner, typeid(T));
        //return t;
        return new MapTypeImpl!(T)(a_owner);
    }
}

//--> stolen from tango
//use this because "static if (is(T T2 : T2[T3]))" doesn't work
//http://www.dsource.org/projects/tango/browser/trunk/tango/core/Traits.d?rev=4134#L253
private template isAssocArrayType( T ) {
    const bool isAssocArrayType = is( typeof(T.init.values[0])
        [typeof(T.init.keys[0])] == T );
}
//<--

class MapTypeImpl(T) : MapType {
    static assert(isAssocArrayType!(T));
    alias typeof(T.init.values[0]) V;
    alias typeof(T.init.keys[0]) K;

    private this(Types a_owner) {
        super(a_owner, typeid(T));
        mKey = mOwner.getType!(K);
        mValue = mOwner.getType!(V);
    }

    override size_t getLength(SafePtr map) {
        return (*map.castTo!(T)()).length;
    }

    override SafePtr getValuePtr(SafePtr map, SafePtr key) {
        return SafePtr.get!(V)(mValue,
            (*key.castTo!(K)()) in (*map.castTo!(T)()));
    }

    override void setKey(SafePtr map, SafePtr key, SafePtr value) {
        (*map.castTo!(T)())[*key.castTo!(K)()] = *value.castTo!(V)();
    }

    override void setKey2(SafePtr map, void delegate(SafePtr key) dg_getKey,
        void delegate(SafePtr value) dg_getValue)
    {
        K key;
        V value;
        dg_getKey(SafePtr.get!(K)(mKey, &key));
        dg_getValue(SafePtr.get!(V)(mValue, &value));
        (*map.castTo!(T)())[key] = value;
    }

    override void iterate(SafePtr map,
        void delegate(SafePtr key, SafePtr value) cb)
    {
        foreach (K key, ref V value; *map.castTo!(T)()) {
            cb(SafePtr.get!(K)(mKey, &key), SafePtr.get!(V)(mValue, &value));
        }
    }

    override char[] toString() {
        return str.format("MapType[%s, %s]", mKey, mValue);
    }
}

class DelegateType : Type {
    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    private static DelegateType create(T)(Types a_owner) {
        DelegateType t = new DelegateType(a_owner, typeid(T));
        //xxx: etc.
        return t;
    }

    override char[] toString() {
        //note that the return value from TypeInfo_Delegate.toString() looks
        //like D syntax, but the arguments are not included
        //e.g. "long delegate(int z)" => "long delegate()"
        return "DelegateType[" ~ typeInfo().toString() ~ "...]";
    }
}

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
        ClassMember[] mMembers, mNTMembers;
        ClassMethod[] mMethods;
        Object mDummy; //for default values - only if isClass()
        void[] mInit; //for default values - only if isStruct()
        Object delegate(ReflectCtor c) mCreateDg;
        bool[size_t] mTransientCache;  //
    }

    private this(ReferenceType a_owner, TypeInfo_Class cti) {
        mOwner = a_owner;
        mCI = cti.info;
        mClassSize = mCI.init.length;
        assert (mOwner.typeInfo() is cti);
        assert (!a_owner.mClass);
        a_owner.mClass = this;
    }

    private this(StructType a_owner) {
        mOwner = a_owner;
        mClassSize = a_owner.size();
        assert (!a_owner.mClass);
        a_owner.mClass = this;
        //TypeInfo.init() can be null
        //for the sake of generality, allocate a byte array in this case
        TypeInfo ti = mOwner.typeInfo();
        mInit = mOwner.initData();
        assert (mInit.length == mOwner.size());
    }

    private void addElement(ClassElement e) {
        foreach (ClassElement old; mElements) {
            //NOTE: the only way this can happen is (besides an internal error)
            //      template mixins which are used several times
            assert (old.name() != e.name());
        }
        mElements = mElements ~ e;
        if (auto me = cast(ClassMember)e) {
            mMembers ~= me;
            if (!(me.offset in mTransientCache))
                mNTMembers ~= me;
        }
        if (auto md = cast(ClassMethod)e)
            mMethods ~= md;
    }

    private void addTransientMember(size_t relOffset) {
        mTransientCache[relOffset] = true;
    }

    final ClassElement[] elements() {
        return mElements;
    }

    final ClassMember[] members() {
        return mMembers;
    }

    final ClassMember[] nontransientMembers() {
        return mNTMembers;
    }

    final ClassMethod[] methods() {
        return mMethods;
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

    final StructuredType owner() {
        return mOwner;
    }

    private void addMethod(DelegateType dgt, void* funcptr, char[] name) {
        foreach (ClassMethod m; mMethods) {
            if (m.name() == name) {
                if (m.mDgType !is dgt || m.mAddress !is funcptr)
                    throw new Exception("different method with same name");
                return;
            }
        }
        if (auto mp = funcptr in owner.owner.mMethodMap) {
            ClassMethod other = *mp;
            //for a class hierarchy, all ctors are called, when a dummy object
            //is created, and so, a subclass will try to register all methods
            //from a super class
            //note that supertypes register their methods first...
            // simply assume that this.isSubTypeOf(other.klass())==true
            //can't really check that, too much foobar which prevents that
            //xxx won't work if the superclass is abstract, maybe just add all
            //    possible classes to the address? ClassMethod[][void*] map
            assert (name == other.name);
            //writefln("huh: %s: %s %s", name, this.name, other.klass.name);
            //ok, add the method anyway, who cares
            //return;
        }
        new ClassMethod(this, dgt, funcptr, name);
    }

    //find a method by name; also searches superclasses
    //return null if not found
    final ClassMethod findMethod(char[] name) {
        Class ck = this;
        outer: while (ck) {
            foreach (ClassMethod curm; ck.methods()) {
                if (curm.name() == name) {
                    return curm;
                }
            }
            ck = ck.superClass();
        }
        return null;
    }

    //return if "this" is inherited from (or the same as) "other"
    final bool isSubTypeOf(Class other) {
        Class cur = this;
        while (cur) {
            if (cur is other)
                return true;
            cur = cur.mSuper;
        }
        return false;
    }

    final Types types() {
        return mOwner.mOwner;
    }

    final Object newInstance() {
        if (!mCreateDg) {
            debug writefln("no: %s", name());
            return null;
        }
        auto c = types().mFoo;
        c.mRecreate = true;
        Object o = mCreateDg(c);
        assert (!!o);
        assert (types.findClass(o) is this);
        return o;
    }

    //everything about this is read-only
    //null for structs
    final Object defaultValues() {
        return mDummy;
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

    final Class klass() {
        return mOwner;
    }
}

///Class member as in a variable declaration in a class
class ClassMember : ClassElement {
    private {
        Type mType;
        size_t mOffset; //byte offset
    }

    private this(Class a_owner, char[] a_name, Type a_type, size_t a_offset) {
        mType = a_type;
        mOffset = a_offset;
        super(a_owner, a_name);
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

    ///check if this member is set to the default value on the passed object
    bool isInit(SafePtr obj) {
        SafePtr memberPtr = get(obj);
        byte* bptr_m = cast(byte*)memberPtr.ptr;
        assert(bptr_m);
        byte* bptr_def;
        if (mOwner.isClass) {
            //class, check against dummy instance
            bptr_def = (cast(byte*)mOwner.mDummy) + mOffset;
        } else {
            //struct, check against typeinfo
            //attention: checks against default struct initializer,
            //    not member initializer in class definition
            bptr_def = (cast(byte*)mOwner.mInit.ptr) + mOffset;
        }
        return bptr_m[0..type.size] == bptr_def[0..type.size];
    }
}

///Method of a class
///at least needed for serializing delegates
class ClassMethod : ClassElement {
    private {
        //type of the function ptr of the delegate
        DelegateType mDgType;
        //address of the code
        void* mAddress;
    }

    private this(Class a_owner, DelegateType dgt, void* addr, char[] a_name) {
        super(a_owner, a_name);
        mDgType = dgt;
        mAddress = addr;
        Types t = mOwner.mOwner.mOwner; //oh absurdity
        //xxx maybe could happen if the user registers two virtual functions
        //    (overridden ones, with the same name), and then removes the one
        //    in the sub class => no compiletime or runtime error, but this
//        assert (!(addr in t.mMethodMap));
        t.mMethodMap[addr] = this;
    }

    final void* address() {
        return mAddress;
    }

    ///invoke the method with a signature known at compile-time
    ///the argument types must fit exactly (no implicit conversions)
    /// T_ret = return type
    /// T... = signature of the method
    /// ptr = object on which the method should be called
    T_ret invoke(T_ret, T...)(SafePtr ptr, T args) {
        alias T_ret delegate(T) dg_t;
        if (typeid(dg_t) !is mDgType.typeInfo())
            throw new Exception("wrong signature for method call");
        ptr.check(mOwner.mTI);
        DgConvert!(dg_t) dgc;
        dgc.ptr = ptr.ptr;
        dgc.funcptr = mAddress;
        //actually call it
        return dgc.d2(args);
    }
}

char[] structFullyQualifiedName(T)() {
    //better way?
    return typeid(T).toString();
}

class DefineClass {
    private {
        Class mClass;
        Types mBase;
    }

    //ti = TypeInfo of the defined class
    this(Types a_owner, Class k) {
        mClass = k;
        mBase = a_owner;
    }

    this(Types a_owner, StructType t) {
        mClass = new Class(t);
        mBase = a_owner;
    }

    //also used for structs
    void autoclass(T)() {
        T obj;
        static if (is(T == class)) {
            assert (!!mClass.mDummy);
            obj = castStrict!(T)(mClass.mDummy);
            T obj_addr = obj;
            //uh, moved getting the name
        } else {
            T* obj_addr = &obj;
            mClass.mName = structFullyQualifiedName!(T);
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
            /+ probably not a good idea: instantiates a lot of templates
            static if (isReflectableClass!(typeof(x))()) {
                mBase.registerClass!(typeof(x))();
            }
            +/
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
                //mClass.mSuper = mBase.registerClass!(S[0])();
                mClass.mSuper = mBase.registerSuperClass!(S[0])(mClass.mDummy);
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

//unittest, as static ctor because failures can lead to silent breakages
import utils.test : Test;
static this() {
    Test z = new Test();
    char[] res;
    foreach (int index, x; z.tupleof) {
        res ~= z.tupleof[index].stringof ~ "|";
    }
    assert (res == "z.a|z.b|z.c|z.d|");
    assert (structFullyQualifiedName!(Test.S) == "utils.test.Test.S");
}

//-------
debug:

import utils.strparser;

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

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

class Test3 : Test1 {
    ushort a = 1;
    char[] b = "hullo";
    float[3] c = [0.3, 0.5, 0.7];

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

void not_main() {
    Types t = new Types();
    Class c = t.registerClass!(Test1)();
    Test1 x = new Test1();
    x.g.c = new Test2();
    x.g.c.c ~= x;
    x.g.c.c ~= new Test3();
    t.registerClass!(Test3)();
    debugDumpTypeInfos(t);
    debugDumpClassGraph(t, x);
}

void debugDumpTypeInfos(Types t) {
    foreach (Type type; t.allTypes()) {
        writefln("%s", type);
        if (auto rt = cast(StructuredType)type) {
            if (auto cl = rt.klass()) {
                writefln("  structured type '%s', known members:", cl.name());
                foreach (ClassElement e; cl.elements()) {
                    if (auto m = cast(ClassMember)e) {
                        writefln("  - %s @ %s : %s", m.name(), m.offset(),
                            m.type());
                    } else if (auto m = cast(ClassMethod)e) {
                        writefln("  - %s() @ %#x", m.name(), m.address());
                    }
                }
            }
        }
    }
}

void debugDumpClassGraph(Types t, Object x) {
    char[][TypeInfo] unknown;
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
            TypeInfo orgtype = cur.type.typeInfo;
            assert (!!orgtype);
            if (cast(ReferenceType)cur.type)
                cur = cur.mostSpecificClass(&tmp, true);
            if (cur.type is null) {
                if (orgtype in unknown)
                    continue;
                char[] info = "unencountered";
                if (auto tic = cast(TypeInfo_Class)orgtype) {
                    if (cur.ptr) {
                        void** p = cast(void**)cur.ptr;
                        Object o = cast(Object)*p;
                        info ~= " [ci: " ~ o.classinfo.name ~ "]";
                    }
                }
                unknown[orgtype] = info;
                writefln("unknown class");
                continue;
            }
            writefln("%s %s %#8x:", cast(StructType)st ? "struct" : "class",
                cur.type, cur.ptr);
            Class xc = castStrict!(StructuredType)(cur.type).klass();
            if (!xc) {
                unknown[cur.type.typeInfo] = "no info";
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
            writefln("array %s len=%d %#8x:", cur.type, art.getArray(cur).length,
                cur.ptr);
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
    writefln("unknown types:");
    foreach (TypeInfo k, char[] v; unknown) {
        char[] more = v;
        if (auto tic = cast(TypeInfo_Class)k) {
            more ~= " (" ~ tic.info.name ~ ")";
        }
        writefln("'%s': %s", k, more);
    }
    writefln("done.");
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
