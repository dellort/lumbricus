module utils.mybox;

import utils.misc;

//failed unboxing is serious business => not a CustomException
class MyBoxException : Exception {
    this(char[] msg) { super(msg); }
}

//dynamically check if sub is equal to or is below c
bool isSubClass(ClassInfo sub, ClassInfo c) {
    while (sub) {
        if (sub is c)
            return true;
        sub = sub.base;
    }
    return false;
}

//version = OldBox;

version (OldBox) {

/// most simple, but generic class that works similar to std.Boxer
/// this is nazi-typed and neither converts between integer types (i.e. if box
/// contains int, can't unpack as uint), not does it do upcasting for classes.
struct MyBox {
    private {
        TypeInfo mType;
        union {
            //what is used depends from size of stored type (mType)
            //(as in Phobo's boxer.d, try to avoid dynamic memory allocation)
            void[] mDynamicData;
            void[mDynamicData.sizeof] mStaticData;
        }
    }

    /// Box data (should work like assignment if there's no opAssign).
    void box(T)(T data) {
        mType = typeid(T);
        assert(T.sizeof == mType.tsize() && T.sizeof == data.sizeof);
        copyin(cast(void*)&data);
    }

    private void copyin(void* ptr) {
        size_t size = mType.tsize();
        if (size <= mStaticData.length) {
            mStaticData[0..size] = ptr[0..size];
        } else {
            mDynamicData = ptr[0..size].dup;
        }
    }

    void boxFromData(TypeInfo T, void[] data) {
        if (!T) {
            assert(data.length == 0);
            nullify();
            return;
        }
        if (T.tsize() != data.length) {
            throw new MyBoxException("invalid arguments");
        }
        mType = T;
        copyin(data.ptr);
    }

    //quite unsafe, for the lazy ones
    void boxFromPtr(TypeInfo T, void* data) {
        mType = T;
        copyin(data);
    }

    private void typecheck(TypeInfo T) {
        if (T !is mType) {
            throw new MyBoxException("MyBox says no: unbox "
                ~ (mType ? mType.toString : "<empty>") ~ " to " ~ T.toString);
        }
    }

    /// Unbox; throw an exception if the types are not exactly the same.
    /// Implicit conversion is never supported (not even upcasts).
    T unbox(T)() {
        typecheck(typeid(T));
        T data;
        assert(T.sizeof == mType.tsize() && T.sizeof == data.sizeof);
        copyout(&data);
        return data;
    }

    private void copyout(void* ptr) {
        size_t size = mType.tsize();
        if (size <= mStaticData.length) {
            ptr[0..size] = mStaticData[0..size];
        } else {
            ptr[0..size] = mDynamicData[];
        }
        return data;
    }

    void unboxToData(TypeInfo T, void[] data) {
        typecheck(T);
        if (T.tsize() != data.length) {
            throw new MyBoxException("invalid arguments");
        }
        copyout(data.ptr);
    }

    void unboxToPtr(TypeInfo T, void* data) {
        typecheck(T);
        copyout(data);
    }

    /// Like unbox(), but return type-default if box is empty.
    /// (Especially useful to get null-references for classes, if box empty)
    T unboxMaybe(T)(T def = T.init) {
        if (mType is null) {
            return def;
        } else {
            return unbox!(T)();
        }
    }

    /// Initialize box to contain that type with default initializer.
    void init(T)() {
        T lala;
        box!(T)(lala);
    }

    /// Dynamic version of init()().
    void initDynamic(TypeInfo type) {
        mType = type;
        void[] pData;
        size_t size = mType.tsize();
        if (size <= mStaticData.length) {
            pData = mStaticData[0..size];
        } else {
            mDynamicData = null;
            mDynamicData.length = size;
            pData = mDynamicData;
        }
        //copy initializer; docs say: if init is null, init with zero
        if (mType.init.length > 0) {
            pData[] = mType.init[];
        } else {
            (cast(ubyte[])pData)[] = 0;
        }
    }

    /// Type stored in the box; null if empty.
    TypeInfo type() {
        return mType;
    }
    bool empty() {
        return type is null;
    }

    /// Empty the box.
    void nullify() {
        mType = null;
        //not really needed
        mDynamicData = null;
    }

    /// Return raw data contained in the box.
    /// Not allowed on empty boxes.
    void[] data() {
        if (mType is null) {
            throw new MyBoxException("MyBox.data(): box is empty.");
        } else {
            if (mType.tsize() <= mStaticData.length) {
                return mStaticData[0..mType.tsize()];
            } else {
                assert(mType.tsize() == mDynamicData.length);
                return mDynamicData;
            }
        }
    }

    /// Compare two boxes;
    /// - If one of them is null, return false.
    /// - If different types, throw exception.
    /// - Otherwise invoke TypeInfo.compare(), which should correspond to "is".
    bool compare(in MyBox b) {
        if (mType is null || b.mType is null)
            return false;
        if (mType !is b.mType) {
            throw new MyBoxException("can't compare different types.");
        }
        return mType.compare(data().ptr, b.data().ptr) == 0;
    }

    /// If the contained type is a subclass of Object or an Interface, return
    /// it as Object; else, return... null? (uh, not so good)
    Object asObject() {
        if (cast(TypeInfo_Class)type()) {
            //this "should" be safe... hurrr
            Object o;
            unboxToPtr(type(), cast(void*)(&o));
            return o;
        } else if (auto ci = cast(TypeInfo_Interface)type()) {
            //???
            assert(false);
        }
        return null;
    }

    ///convert a box which contains an Object of any type to the class type to
    void convertObject(TypeInfo to) {
        auto cur = cast(TypeInfo_Class)type();
        auto toc = cast(TypeInfo_Class)to;
        if (!cur || !toc)
            throw new MyBoxException("incompatible types.");
        //xxx wrong, but it was 3:10 am
        if (!isSubClass(cur.info, toc.info) && !isSubClass(toc.info, cur.info))
            throw new MyBoxException(myformat("inconvertible types: {} {}.",
                cur, toc));
        mType = toc;
    }

    /// Default constructor: Empty box.
    static MyBox opCall()() {
        MyBox box;
        return box;
    }

    /// Construct a box with that parameter in it.
    /// Because opCall doesntwork it's named Box
    static MyBox Box(T)(T data) {
        MyBox box;
        box.box!(T)(data);
        return box;
    }
}

} else { //version (OldBox)

//this version of MyBox works better with the patches in dmd bugzilla #3463, and
//  doesn't force the contained type to be scanned conservatively - but it also
//  forces heap memory allocation even for small types (plus it loses some
//  other features of MyBox, but they are not used anywhere in lumbricus)

private class Container {
    abstract TypeInfo type();
}

private class ContainerT(T) : Container {
    T data;
    this(T a_data) {
        data = a_data;
    }
    override TypeInfo type() {
        return typeid(T);
    }
}

struct MyBox {
    private {
        Container mData;
    }

    /// Box data (should work like assignment if there's no opAssign).
    void box(T)(T data) {
        mData = new ContainerT!(T)(data);
    }

    /// Unbox; throw an exception if the types are not exactly the same.
    /// Implicit conversion is never supported (not even upcasts).
    T unbox(T)() {
        auto xdata = cast(ContainerT!(T))mData;
        if (!xdata) {
            throw new MyBoxException("MyBox says no: unbox "
                ~ (type ? type.toString : "<empty>") ~ " to " ~ T.stringof);
        }
        return xdata.data;
    }

    /// Like unbox(), but return type-default if box is empty.
    /// (Especially useful to get null-references for classes, if box empty)
    T unboxMaybe(T)(T def = T.init) {
        if (mData is null) {
            return def;
        } else {
            return unbox!(T)();
        }
    }

    /// Initialize box to contain that type with default initializer.
    void init(T)() {
        T lala;
        box!(T)(lala);
    }

    /// Type stored in the box; null if empty.
    TypeInfo type() {
        return mData ? mData.type : null;
    }
    bool empty() {
        return mData is null;
    }

    /// Empty the box.
    void nullify() {
        mData = null;
    }

    /// Default constructor: Empty box.
    static MyBox opCall()() {
        MyBox box;
        return box;
    }

    /// Construct a box with that parameter in it.
    /// Because opCall doesntwork it's named Box
    static MyBox Box(T)(T data) {
        MyBox box;
        box.box!(T)(data);
        return box;
    }
}

} //version(!OldBox)


unittest {
    MyBox box;

    box.box!(int)(-4);
    assert(box.unbox!(int)() == -4);

    box.box!(long)(-56);
    assert(box.unbox!(long)() == -56);

    bool thrown = false;
    try {
        box.box!(int)(5);
        box.unbox!(uint);
    } catch (MyBoxException) {
        thrown = true;
    }
    assert(thrown);

    struct FooFoo {
        char[12] foofoo;
        //trailing zero-initialized members to test MyBox.init*
        int moo1, moo2, moo3;
    }
    FooFoo test;
    test.foofoo[] = "abcdefghijkl";
    box.box!(FooFoo)(test);
    assert(box.unbox!(FooFoo)().foofoo == "abcdefghijkl");

    typedef int huh = 4;
    box.nullify();
    assert(box.unboxMaybe!(huh)() == 4);
    box.box!(huh)(123);
    assert(box.unboxMaybe!(huh)() == 123);

    //NOTE: assume compiler sets init to null, because int is intialized with
    //      zero; doesn't need to be true.
    if (typeid(int).init.length > 0) {
        debug Trace.formatln("mybox.d unittest: zero-init not tested!");
    }

    box.init!(huh)();
    assert(box.unbox!(huh) == huh.init);

version (OldBox) {
    box.initDynamic(typeid(int));
    assert(box.unbox!(int) == 0);

    box.initDynamic(typeid(huh));
    assert(box.unbox!(huh) == huh.init);

    box.initDynamic(typeid(FooFoo));
    assert(box.unbox!(FooFoo) == FooFoo.init);

    MyBox box2;
    box.box!(int)(7);
    assert(!box.compare(box2));
    box2.box!(int)(8);
    assert(!box.compare(box2));
    box2.box!(int)(7);
    assert(box.compare(box2));
    box2.box!(uint)(7);

    thrown = false;
    try { box.compare(box2); } catch (Exception e) { thrown = true; }
    assert(thrown);

    //just to be sure MyBox will work for object references
    interface X {
    }
    class Foo : X {
        char[34] blubber;
    }
    static assert(Foo.sizeof == (void*).sizeof);

    MyBox box3;
    Foo f = new Foo();
    box3.box!(Foo)(f);
    assert(box3.asObject() is f);
    //box3.box!(X)(f);
    //assert(box3.toObject() is f);
    box3.box!(long)(123);
    assert(box3.asObject() is null);
}

}
