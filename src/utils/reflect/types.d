module utils.reflect.types;

import utils.reflect.structtype;
import utils.reflect.type;
import utils.reflect.classdef;
import utils.reflect.refctor;
import utils.reflect.safeptr;
import utils.reflect.arraytype;
import utils.reflect.dgtype;
import utils.hashtable : RefHashTable;
import utils.misc;

import tango.core.Traits : isAssocArrayType;
//import memory = tango.core.Memory;
debug import tango.core.tools.StackTrace : nameOfFunctionAt;

class Types {
    private {
        //argh, D doesn't provide ClassInfo -> TypeInfo
        ReferenceType[ClassInfo] mCItoT;
        //D types to internal ones
        //Type[TypeInfo] mTItoT;
        //can't use AA, comparing TypeInfo with == is broken:
        //  http://d.puremagic.com/issues/show_bug.cgi?id=3086
        RefHashTable!(TypeInfo, Type) mTItoT;
        ClassMethod[void*] mMethodMap;
        Class[char[]] mClassMap;
        ReflectCtor mFoo;
    }

    this() {
        mTItoT = new typeof(mTItoT)();
        mFoo = new ReflectCtor(this);
        //there are a lot of more base types in D, it's ridiculous!
        //add if needed
        addBaseTypes!(void, char, byte, ubyte, short, ushort, int, uint, long,
            ulong, float, double, real, bool)();
        getType!(Object)();
    }

    package final ReflectCtor refCtor() {
        return mFoo;
    }

    final Type[] allTypes() {
        return mTItoT.values;
    }

    //map classes to reflection type (always return null on failure)
    final Class findClass(Object o) {
        if (!o)
            return null;
        return findClass(o.classinfo);

    }
    final Class findClass(ClassInfo ci) {
        ReferenceType* pt = findClassRef(ci);
        return pt ? (*pt).klass() : null;
    }
    package final ReferenceType* findClassRef(ClassInfo ci) {
        assert(!!ci);
        return ci in mCItoT;
    }
    final Class findClassByName(char[] name) {
        Class* pc = name in mClassMap;
        return pc ? *pc : null;
    }

    final SafePtr ptrOf(T)(ref T x) {
        getType!(T)(); //make sure type is registered
        return toSafePtr(typeid(T), &x);
    }

    //pointer to an object, where the .type property refers to the exact type
    //  of the object...:
    //  Object o = ...; SafePtr ptr = types.objPtr(o);
    //  assert(ptr.type.typeInfo is o.classinfo.typeinfo);
    //if obj is null, type is Object
    final SafePtr objPtr(Object x, void** memory = null, bool may_fail = false)
    {
        if (!memory)
            memory = new void*;
        //yes this could fail
        Type t = tiToT((x ? x.classinfo : Object.classinfo).typeinfo, may_fail);
        if (!t && may_fail)
            return SafePtr.Null;
        assert(!!t);
        *memory = castStrict!(ReferenceType)(t).castTo(x);
        SafePtr res;
        res.ptr = memory;
        res.type = t;
        return res;
    }

    final SafePtr toSafePtr(TypeInfo ti, void* ptr) {
        return SafePtr(tiToT(ti), ptr);
    }

    ///TypeInfo -> Type; only works if the type was encountered at compile time
    /// can_fail = if false, throw an exception if the type can't be found,
    ///            else return null
    final Type tiToT(TypeInfo ti, bool can_fail = false) {
        Type* t = ti in mTItoT;
        if (t) {
            assert((*t).typeInfo() is ti);
            return *t;
        }
        if (can_fail)
            return null;
        throw new Exception("Type for TypeInfo >"~ti.toString()~"< not found");
    }

    //special handling for superclasses: this might not be instantiable (if they
    //are abstract), but they still need to be analyzed
    package final Class registerSuperClass(T)(Object dummy) {
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
        klass.name = cti.info.name;
        assert (!(klass.name in mClassMap));
        mClassMap[klass.name] = klass;
        klass.createDg = inst;

        if (!dummy) {
            //ctors can be called recursively
            //(when using registerClass() in a ctor)
            //xxx: umm, we could just create a new ReflectCtor instance...
            auto old_current = mFoo.current;
            assert(!mFoo.recreateTransient);
            scope(exit) {
                //only during registration
                mFoo.current = old_current;
            }
            mFoo.current = klass;
            dummy = cast(T)inst(mFoo);
        }
        assert (!!dummy);
        klass.dummy = dummy;
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
    final void registerMethod(T1, T2)(T1 owner, T2 del, char[] name) {
        static assert (is(T1 == class));
        static assert (is(T2 == delegate));
        if (del.ptr !is cast(void*)owner)
            throw new Exception("not an object method?");
        Class klass = findClass(owner);
        //user is supposed to call registerMethod() in the reflection ctor, so
        //this shouldn't happen
        if (!klass)
            throw new Exception("class not registered");
        DelegateType dgt = cast(DelegateType)getType!(T2)();
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

    package void addType(Type t) {
        assert(!(t.typeInfo in mTItoT));
        mTItoT[t.typeInfo] = t;
        if (auto cit = cast(TypeInfo_Class)t.typeInfo()) {
            assert (!(cit.info in mCItoT));
            mCItoT[cit.info] = castStrict!(ReferenceType)(t);
        }
    }

    private void addBaseTypes(T...)() {
        foreach (Type; T) {
            BaseType.create!(Type)(this);
        }
    }

    ///Return a Type describing T; if T is a base type, an array/a-array, a
    ///class/interface reference, a delegate, or an already defined enum.
    ///The difference to tiToT() is, that tiToT() might not know all types,
    ///while this function can create Type instances on demand.
    final Type getType(T)()
    out(res) {
        assert(!!res);
    }
    body {
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

    package ClassMethod lookupMethod(void* fptr) {
        ClassMethod* pm = fptr in mMethodMap;
        if (pm)
            return *pm;
        return null;
    }

    package void addMethod(void* fptr, ClassMethod m) {
        assert(!!m);
        assert(!!fptr);
        mMethodMap[fptr] = m;
    }

    //when readDelegate has failed, and you don't know why, call this
    //raises an error and never returns (throws exception or crashes)
    //ptr = pointer to delegate
    //where = part of error message
    void readDelegateError(SafePtr ptr, char[] where) {
        Object t1;
        ClassMethod t2;
        assert(!ptr.readDelegate(t1, t2), "caller is fraudulent");
        assert(!!cast(DelegateType)ptr.type);

        alias void delegate() Dg;
        Dg* dgp = cast(Dg*)ptr.ptr;
        //warning: this might crash, if the delegate points to the
        //         stack or a struct; we simply can't tell
        //could use GC to find out, if ptr points to the start of a block; if
        //  not, then it can't really be a class (if yes, it still could be a
        //  new'ed struct)
        char[] crashy = "[enable version debug to see]";
        char[] func = "?";
        debug {
            //we can't tell to what dgp.ptr will point to
            //if it's not an object, we'll just crash
            //otherwise, output information useful for debugging
            Trace.formatln("hello, {}:{} might crash here.", __FILE__,
                __LINE__);
            crashy = (cast(Object)dgp.ptr).classinfo.name;

            func = nameOfFunctionAt(dgp.funcptr);
        }
        char[] what = myformat("dest-class: {} function: 0x{:x} '{}'",
            crashy, dgp.funcptr, func);

        throw new Exception(myformat("{}: couldn't write delegate, {}",
            where, what));
    }
}

