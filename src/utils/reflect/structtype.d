module utils.reflect.structtype;

import utils.reflect.type;
import utils.reflect.types;
import utils.reflect.safeptr;
import utils.reflect.classdef;
import utils.misc;

abstract class StructuredType : Type {
    private {
        Class mClass;
    }

    //might return null, if the class/struct itself was not described yet
    final Class klass() {
        return mClass;
    }

    package final void setClass(Class c) {
        assert(!mClass);
        mClass = c;
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
        auto cit = cast(TypeInfo_Class)typeInfo;
        auto iit = cast(TypeInfo_Interface)typeInfo;
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

    package static ReferenceType create(T)(Types a_owner) {
        ReferenceType t = new ReferenceType(a_owner, typeid(T));
        t.do_init!(T)();
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

    package static StructType create(T)(Types a_owner) {
        StructType t = new StructType(a_owner, typeid(T));
        t.do_init!(T)();
        DefineClass dc = new DefineClass(a_owner, t);
        dc.autostruct!(T)();
        return t;
    }

    override char[] toString() {
        return "StructType[" ~ (mClass ? mClass.name() : "?") ~ "]";
    }
}

