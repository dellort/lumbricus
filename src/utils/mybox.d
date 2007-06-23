module utils.mybox;

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
            throw new Exception("MyBox says no.");
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

    /// Copy the box including contents. Should work like a normal assignment,
    /// at least if there's no opAssign.
    /// (Simply assinging a box will copy contents only if data is small enough)
    MyBox copy() {
        MyBox c = *this;
        if (mType.tsize() > mStaticData.length) {
            c.mDynamicData = mDynamicData.dup;
        }
        return c;
    }

    /// Type stored in the box; null if empty.
    TypeInfo type() {
        return mType;
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
            throw new Exception("MyBox.data(): box is empty.");
        } else {
            if (mType.tsize() <= mStaticData.length) {
                return mStaticData[0..mType.tsize()];
            } else {
                assert(mType.size.length == mDynamicData.length);
                return mDynamicData;
            }
        }
    }

    /// Compare two boxes;
    /// - If different types, throw exception.
    /// - If one of them is null, return false.
    /// - Otherwise invoke TypeInfo.compare(), which should correspond to "is".
    bool compare(MyBox b) {
        if (mType is null || b.mType is null)
            return false;
        if (mType !is b.mType) {
            throw new Exception("can't compare different types.");
        }
        return mType.compare(data().ptr, b.data().ptr);
    }
}

debug import std.stdio;

unittest {
    MyBox box;

    box.box!(int)(-4);
    assert(box.unbox!(int)() == -4);

    box.box!(long)(-56);
    assert(box.unbox!(long)() == -56);

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

    //just to be sure MyBox will work for object references
    class Foo {
        char[34] blubber;
    }
    static assert(Foo.sizeof == (void*).sizeof);

    debug writefln("mybox.d unittest: passed.");
}
