module utils.reflect.arraytype;

import utils.reflect.type;
import utils.reflect.types;
import utils.reflect.safeptr;
import utils.misc;

import tango.core.Traits : isAssocArrayType, isStaticArrayType;

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
    //also, if you call setLength, an existing Array descriptor may become
    //  outdated (different .length and .ptr)
    Array getArray(SafePtr array) {
        array.checkExactNotNull(this, "Array.getArray()");
        return mGetArray(this, array);
    }
    //same as assigning the length property of a normal D array
    void setLength(SafePtr array, size_t len) {
        array.checkExactNotNull(this, "Array.setLength()");
        mSetLength(this, array, len);
    }

    package static ArrayType create(T)(Types a_owner) {
        ArrayType t = new ArrayType(a_owner, typeid(T));
        t.do_init!(T)();
        static if (is(T T2 : T2[])) {
            t.mMember = t.owner.getType!(T2)();
        } else {
            static assert (false, "not an array type");
        }
        t.mStaticLength = -1;
        static if (isStaticArrayType!(T)) {
            t.mStaticLength = T.length; //T.init doesn't work???
        }
        t.mSetLength = function void(ArrayType t, SafePtr array, size_t len) {
            static if (!isStaticArrayType!(T)) {
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
            return myformat("ArrayType[{}[{}]]", mMember, staticLength());
        }
    }

    override bool hasToString() {
        return mMember.hasToString();
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

    override bool hasToString() {
        return keyType.hasToString() && valueType.hasToString();
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

    package static MapType create(T)(Types a_owner) {
        //MapType t = new MapType(a_owner, typeid(T));
        return new MapTypeImpl!(T)(a_owner);
    }
}

class MapTypeImpl(T) : MapType {
    static assert(isAssocArrayType!(T));
    alias typeof(T.init.values[0]) V;
    alias typeof(T.init.keys[0]) K;
    static assert(is(T == V[K]));

    private this(Types a_owner) {
        super(a_owner, typeid(T));
        do_init!(T)();
        mKey = owner.getType!(K)();
        mValue = owner.getType!(V)();
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
        return myformat("MapType[{}, {}]", mKey, mValue);
    }
}
