module utils.mybox;

class MyBoxException : Exception {
    this(char[] msg) { super(msg); }
}

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
            void[8] mStaticData;
        }

        static assert(this.sizeof == 12);
    }

    /// Box data (should work like assignment if there's no opAssign).
    void box(T)(T data) {
        mType = typeid(T);
        size_t size = mType.tsize();
        assert(T.sizeof == size && T.sizeof == data.sizeof);
        if (size <= mStaticData.length) {
            mStaticData[0..size] = (cast(void*)&data)[0..size];
        } else {
            mDynamicData = (cast(void*)&data)[0..size].dup;
        }
    }

    /// Unbox; throw an exception if the types are not exactly the same.
    /// Implicit conversion is never supported (not even upcasts).
    T unbox(T)() {
        if (typeid(T) !is mType) {
            throw new MyBoxException("MyBox says no: unbox "
                ~ (mType ? mType.toString : "<empty>") ~ " to " ~ T.stringof);
        }
        size_t size = mType.tsize();
        T data;
        assert(T.sizeof == size && T.sizeof == data.sizeof);
        if (size <= mStaticData.length) {
            (cast(void*)&data)[0..size] = mStaticData[0..size];
        } else {
            (cast(void*)&data)[0..size] = mDynamicData;
        }
        return data;
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
            mDynamicData.length = size;
            pData = mDynamicData;
        }
        //copy initializer; docs say: if init is null, init with zero
        if (mType.init.length > 0) {
            pData[] = mType.init;
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

debug import std.stdio;

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
        writefln("mybox.d unittest: zero-init not tested!");
    }
    box.initDynamic(typeid(int));
    assert(box.unbox!(int) == 0);

    box.initDynamic(typeid(huh));
    assert(box.unbox!(huh) == huh.init);

    box.initDynamic(typeid(FooFoo));
    assert(box.unbox!(FooFoo) == FooFoo.init);

    box.init!(huh)();
    assert(box.unbox!(huh) == huh.init);

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
    class Foo {
        char[34] blubber;
    }
    static assert(Foo.sizeof == (void*).sizeof);

    debug writefln("mybox.d unittest: passed.");
}
