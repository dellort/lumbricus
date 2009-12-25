module utils.reflect.refctor;

import utils.reflect.types;
import utils.reflect.classdef;
import utils.misc;

///Types used to make a reflected class' constructor different from the
///standard constructor
///oh, and also includes a way to get the Types class
///The constructor of a reflected class looks like this:
///  this(ReflectCtor c) {} //durrrr
final class ReflectCtor {
    private {
        Types mTypes;
        Class mCurrent;
        bool mRecreateTransient;
    }

    package this(Types t) {
        mTypes = t;
    }

    final Types types() {
        return mTypes;
    }

    ///mark a class member as transient (not serialized)
    ///member is still accessible for reflection
    ///set instance to this
    final void transient(T1, T2)(T1 owner, T2* member) {
        //xxx: what's this special case? whatever...
        if (!mCurrent)
            return;
        assert(!!member);
        assert(!!owner);
        //get relative offset
        auto p_obj = cast(void*)owner;
        size_t rel_offset = cast(size_t)member - cast(size_t)p_obj;
        mCurrent.addTransientMember(rel_offset);
    }

    ///with this function, the ctor can ask if the transient members shall be
    ///recreated (false for dummy members, true when deserializing objects)
    final bool recreateTransient() {
        return mRecreateTransient;
    }

    package final void recreateTransient(bool r) {
        mRecreateTransient = r;
    }

    package final Class current() {
        return mCurrent;
    }
    package final void current(Class cur) {
        mCurrent = cur;
    }

    //method(this, &method, "method")
    final void method(T1, T2)(T1 owner, T2 del, char[] name) {
        mTypes.registerMethod(owner, del, name);
    }
}

bool isReflectableClass(T)() {
    ReflectCtor c;
    T s; //static assert declareable
    static assert(is(T == class));
    return is(typeof(new T(c)));
}
