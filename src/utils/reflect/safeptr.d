module utils.reflect.safeptr;

import utils.reflect.type;
import utils.reflect.structtype;
import utils.reflect.dgtype;
import utils.reflect.classdef;
import utils.mybox;
import utils.misc;

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
    //use Types.ptrOf(), Type.ptrOf(), or Types.toSafePtr() for construction
    Type type;
    void* ptr;

    static const SafePtr Null = {null, null};

    static SafePtr get(T)(Type t, T* ptr) {
        assert (t.typeInfo() == typeid(T));
        return SafePtr(t, ptr);
    }

    //throw an appropriate exception if types are incompatible
    void check(TypeInfo ti) {
        if (ti !is type.typeInfo)
            throw new CustomException(myformat("incompatible types: got {}, expected"
                " {}", ti, type.typeInfo));
    }

    //check if exactly the same type (no conversions) and not a null ptr
    void checkExactNotNull(Type needed, char[] caller) {
        if (!ptr)
            throw new CustomException("null SafePtr passed to " ~ caller);
        if (type !is needed)
            throw new CustomException("SafePtr of wrong type passed to " ~ caller);
    }

    SafePtr deref() {
        if (!ptr)
            throw new CustomException("deref() null pointer");
        PointerType pt = cast(PointerType)type;
        if (!pt)
            throw new CustomException("deref() on non-pointer type");
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
    //           if not provided, allocate on heap
    SafePtr mostSpecificClass(void** memory = null, bool may_fail = false) {
        Object o = toObject(may_fail);
        ReferenceType* rt2;
        if (!o)
            return SafePtr.Null;
        rt2 = type.owner.findClassRef(o.classinfo);
        if (!rt2) {
            if (!may_fail)
                throw new CustomException("class not found, maybe it is not "
                    "reflected?");
            return SafePtr(null, null);
        }
        if (!memory)
            memory = new void*;
        *memory = (*rt2).castTo(o);
        return SafePtr(*rt2, memory);
    }

    //convert objects/interfaces to the type & pointer of the actual "this" ptr
    //conents untouched of ptr is null, or type is something else
    final SafePtr deepestType(void** memory = null) {
        SafePtr r = mostSpecificClass(memory, true);
        return (!r.type || !r.ptr) ? *this : r;
    }

    SafePtr toObjectPtr(void** memory) {
        Object o = toObject();
        if (!o)
            return SafePtr(null, null);
        *memory = cast(void*)o;
        return SafePtr(type.owner.tiToT(typeid(typeof(o))), memory);
    }

    Object toObject(bool may_fail = false) {
        if (type is null || ptr is null)
            return null;
        auto rt = cast(ReferenceType)type;
        if (!rt && !may_fail)
            throw new CustomException("toObject() on non-reference ptr");
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
            throw new CustomException("target not an object or interface type");
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

    //to access delegate properties directly
    private alias void delegate() Dg;

    //returns true on success
    //if failed, return false and leave obj/method untouched
    bool readDelegate(ref Object obj, ref ClassMethod method) {
        auto dgt = cast(DelegateType)type;
        if (!dgt) {
            //writefln("not a delegate type!");
            return false;
        }
        assert (!!ptr);
        Dg* dp = cast(Dg*)ptr;
        if (dp.ptr is null) {
            obj = null;
            method = null;
            return true;
        }
        ClassMethod m = type.owner.lookupMethod(dp.funcptr);
        if (!m) {
            //writefln("method not found");
            return false;
        }
        //if the code pointer points to a method, the ptr argument should be
        //the this pointer for the object (can't point into the stack etc.)
        Object o = cast(Object)dp.ptr;
        Class k = type.owner.findClass(o);
        //can happen, when the actual object is derived from a registered one
        //(which is why we have a ClassMethod m, but not a Class)
        if (!k) {
            //writefln("class not registered");
            return false;
        }
        //assert (k.isSubTypeOf(method.klass()));
        /+ xxx
        if (!k.isSubTypeOf(m.klass())) {
            Trace.formatln("{} {} {}", k.name, m.klass.name, m.name);
        }
        assert (k.isSubTypeOf(m.klass()));
        +/
        obj = o;
        method = m;
        return true;
    }

    //overwrite the variable, which ptr points to, with obj/method
    //return false if failed (wrong types)
    bool writeDelegate(Object obj, ClassMethod method) {
        auto dgt = cast(DelegateType)type;
        if (!dgt)
            throw new CustomException("not a delegate pointer");
        assert (!!ptr);
        Dg* dp = cast(Dg*)ptr;
        if (obj) {
            Class k = type.owner.findClass(obj);
            assert (!!k);
            //xxx for now disregard the following assert() urgs
            //assert (k.isSubTypeOf(method.klass()));
            if (method.type !is type)
                return false;
        }
        dp.ptr = cast(void*)obj;
        dp.funcptr = cast(void function())(method ? method.address() : null);
        return true;
    }
}

