module utils.reflect.type;

import utils.reflect.types;
import utils.reflect.safeptr;
import utils.misc;

class Type {
    private {
        Types mOwner;
        TypeInfo mTI;
        size_t mSize;
        char[] mUniqueName;
        void[] mInit;
        char[] function(SafePtr) mToString;
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
        if (!mInit.ptr && mInit.length) {
            //array has a length, but ptr is null
            //an array descriptor like this is definitely... strange
            //bug report: http://d.puremagic.com/issues/show_bug.cgi?id=2990
            //for now work it around: no init.ptr means zero-initialize
            mInit = null; //allocated below instead
        }
        //length 0 => init all to bit pattern 0
        if (!mInit.length) {
            mInit = new ubyte[mSize];
        }
        assert(mInit.ptr || !mInit.length);
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

    //do initializations which require the static type
    //must be called by subclasses
    //why the fuck are constructors not templateable?
    package void do_init(T)() {
        assert(mTI is typeid(T));
        assert(!mToString);
        mToString = function char[](SafePtr p) {
            //fucking special cases!
            static if(is(T == void)) {
                return "[void]";
            } else {
                //equivalent to T d = p.read!(T)();
                //just that we can't do this with static arrays
                T* d = cast(T*)p.ptr;
                return myformat("{}", *d);
                return "";
            }
        };
        //NOTE: TypeInfo.toString won't work: dmd bug 3086
        //  (toString is not unique, although D uses it for TypeInfo.opEquals)
        mUniqueName = T.mangleof;
        //also, T.mangleof doesn't work for enums: dmd bug 3651
        //so, disambiguate somehow
        //using struct Mangle(T) {} alias Mangle!(T) M; M.mangleof works, but
        //  adds bloat to the compiled executable
        mUniqueName = mUniqueName ~ "-" ~ mTI.toString();
        mOwner.addName(this);
    }

    final SafePtr ptrOf(T)(T* ptr) {
        if (typeid(T) !is mTI)
            throw new Exception("type error");
        return SafePtr(this, ptr);
    }

    final TypeInfo typeInfo() {
        return mTI;
    }

    final size_t size() {
        return mSize;
    }

    final char[] uniqueName() {
        assert(mUniqueName != "");
        return mUniqueName;
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
    //xxx: comparision is different for floats and nans
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

    //convert the value in p (which must be of type this) to a string
    //meant for debugging only
    final char[] dataToString(SafePtr p) {
        assert(!!mToString);
        return mToString(p);
    }

    //true for all native types (+ enums), arrays with elements for which
    //  hasToString() is true, AAs for which key and value hasToString(),
    //  classes which override toString, and structs that have toString
    //  defined
    //basically returns if dataToString contains something remotely meaningful
    bool hasToString() {
        return false;
    }
}

class BaseType : Type {
    private char[] mName;

    private this(Types a_owner, TypeInfo a_ti, char[] a_name) {
        super(a_owner, a_ti);
        mName = a_name;
    }

    package static BaseType create(T)(Types a_owner) {
        auto t = new BaseType(a_owner, typeid(T), T.stringof);
        t.do_init!(T)();
        return t;
    }

    override char[] toString() {
        return "BaseType[" ~ mName ~ "]";
    }

    override bool hasToString() {
        return true;
    }
}

//dummy for some unhandled types (e.g. function pointers)
class UnknownType : Type {
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    package static UnknownType create(T)(Types a_owner) {
        return new UnknownType(a_owner, typeid(T));
    }

    override char[] toString() {
        return "UnknownType[" ~ typeInfo.toString() ~ "]";
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

    package static PointerType create(T)(Types a_owner) {
        PointerType t = new PointerType(a_owner, typeid(T));
        t.do_init!(T)();
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

    package static EnumType create(T)(Types a_owner) {
        EnumType t = new EnumType(a_owner, typeid(T));
        t.do_init!(T)();
        static if (is(T T2 == enum)) {
            t.mUnderlying = t.mOwner.getType!(T2)();
        } else {
            static assert (false, "not an enum type");
        }
        assert (t.size() == t.mUnderlying.size());
        return t;
    }

    override char[] toString() {
        return "EnumType[" ~ (mUnderlying ? mUnderlying.toString() : "?") ~ "]";
    }

    override bool hasToString() {
        return mUnderlying.hasToString();
    }
}

