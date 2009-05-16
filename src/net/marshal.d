module net.marshal;

//I don't like text-based protocols :D

import utils.buffer;
import utils.misc;

import tango.core.Traits;
import tango.core.ByteSwap;
import utf = stdx.utf;

//data is always written as big endian aka network byteorder
version (BigEndian) {
    private const bool cSwapBytes = false;
} else version (LittleEndian) {
    private const bool cSwapBytes = true;
} else {
    static assert(false, "no endian");
}

//do byte swapping, can be used to convert big <=> little endian
//xxx: could be extended to write arrays
void swapBytes(T)(ref T data) {
    static if (T.sizeof <= 1) {
    } else static if (T.sizeof == 2) {
        ByteSwap.swap16(&data, 2);
    } else static if (T.sizeof == 4) {
        ByteSwap.swap32(&data, 4);
    } else static if (T.sizeof == 8) {
        ByteSwap.swap64(&data, 8);
    } else {
        static assert(false);
    }
}

/++
 + converts basic, array and struct types into octets
 +   this doesn't define a "format", it just dumps D data types as bytes.
 +   instead, the format is defined by the data structures, and is language/
 +   cpu/abi independent; except for dynamic arrays.
 + basic data types: written literally, as big endian
 + bool: 1 byte, false=0, true=1; on reading, !=0 turns into true
 + static arrays: elements are written sequentially
 + dynamic arrays: like static arrays, but a 32 bit length value is prefixed
 + structs: members are written sequentially, without any padding
 + char[] arrays are handled specially: utf-8 encoding is verified on reading
 +
 + the struct is only here for practical reasons, no state is actually stored
 + you just need to set the writer before calling write()
 + writer is the only member var (you can do Marshaller(&yourwriter).write(...))
 +/
struct Marshaller {
    //write the passed array, if unsuccessful, it can throw an exception
    //(depending from the needs of the caller)
    void delegate(ubyte[]) writer;

    void write(T)(T data) {
        static if (is(T T2 : T2[])) {
            writeArray!(T)(data);
        } else static if (is(T T2 == enum)) {
            write!(T2)(cast(T2)data);
        } else static if (isIntegerType!(T) || isRealType!(T)) {
            writeNumeric!(T)(data);
        } else static if (is(T == char)) {
            write!(ubyte)(data);
        } else static if (is(T == bool)) {
            write!(ubyte)(data ? 1 : 0);
        } else static if (is(T == struct)) {
            foreach (int idx, x; data.tupleof) {
                write!(typeof(data.tupleof[idx]))(x);
            }
        } else {
            static assert(false, "No marshaller for: " ~ T.stringof);
        }
    }

    private void writeArray(T)(T data) {
        static if (isDynamicArrayType!(T)) {
            //always write as uint (length is size_t; usually uint or ulong)
            write!(uint)(data.length);
        }

        alias typeof(data[0]) ElementT;
        static if (is(ElementT == ubyte) || is(ElementT == char)) {
            //special handling just to speed up writing
            dump(data.ptr, data.length);
        } else {
            foreach (ref item; data) {
                static assert(is(typeof(item) == ElementT));
                write(item);
            }
        }
    }

    //T is any integer or float type
    //they all need to be byte swapped (possibly)
    //(not sure about floats)
    private void writeNumeric(T)(T data) {
        static if (cSwapBytes) {
            swapBytes(data);
        }
        dump(&data, data.sizeof);
    }

    private void dump(void* p, size_t s) {
        assert(!!writer);
        writer(cast(ubyte[])(p[0..s]));
    }
}

///reverse of Marshaller
struct Unmarshaller {
    //should read exactly the passed size and write the data into the result; if
    //not enough data, throw an exception
    void delegate(ubyte[]) reader;

    //functions cannot return static arrays, so this gets the equivalent
    //dynamic array type
    private template RetType(T) {
        static if (is(T T2 : T2[])) {
            alias T2[] RetType;
        } else {
            alias T RetType;
        }
    }

    RetType!(T) read(T)() {
        static if (is(T T2 : T2[])) {
            return readArray!(T)();
        } else static if (is(T T2 == enum)) {
            T tmp = cast(T)read!(T2)();
            if (tmp < T.min || tmp > T.max)
                throw new UnmarshalException("enum out of bounds");
            return tmp;
        } else static if (isIntegerType!(T) || isRealType!(T)) {
            return readNumeric!(T)();
        } else static if (is(T == char)) {
            return read!(ubyte)();
        } else static if (is(T == bool)) {
            return !!read!(ubyte)();
        } else static if (is(T == struct)) {
            T ret;
            foreach (int idx, x; ret.tupleof) {
                alias typeof(ret.tupleof[idx]) ElementT;
                static if (isStaticArrayType!(ElementT)) {
                    //need slice operator to assign to static array
                    ret.tupleof[idx][] = read!(ElementT)();
                } else {
                    ret.tupleof[idx] = read!(ElementT)();
                }
            }
            return ret;
        } else {
            static assert(false, "No marshaller for: " ~ T.stringof);
        }
    }

    private RetType!(T) readArray(T)() {
        //even for static arrays, the return type needs to be dynamic
        RetType!(T) ret;

        static if (isDynamicArrayType!(T)) {
            //dynamic arrays store their size in the stream
            ret.length = read!(uint)();
        } else {
            //for static arrays, it's fixed
            ret.length = T.length;
        }

        //xxx: specialize for arrays that can be read on one go? (like ubyte[])
        //     1. must keep byteswapping (make swapBytes() work with arrays?)
        //     2. some types like bool or enums still need special handling
        alias typeof(ret[0]) ElementT;
        for (int i = 0; i < ret.length; i++) {
            ret[i] = read!(ElementT)();
        }

        static if (is(ElementT == char)) {
            try {
                utf.validate(ret);
            } catch (utf.UtfException e) {
                throw new UnmarshalException("string not utf-8 conform");
            }
        }

        return ret;
    }

    //T is any integer or float type
    //they all need to be byte swapped (possibly)
    //(not sure about floats)
    private T readNumeric(T)() {
        T data;
        undump(&data, data.sizeof);
        static if (cSwapBytes) {
            swapBytes(data);
        }
        return data;
    }

    private void undump(void* p, size_t s) {
        assert(!!reader);
        reader(cast(ubyte[])(p[0..s]));
    }
}

class UnmarshalException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

///writes out basic, array and struct types to a byte buffer
///using UnmarshalBuffer on the produced data gets the original back
///Note: stores no type information at all
class MarshalBuffer {
    private {
        BufferWrite mBuffer;
    }

    this() {
        mBuffer = new BufferWrite();
    }

    ubyte[] data() {
        return mBuffer.data();
    }

    void write(T)(T data) {
        Marshaller(&writeRaw).write!(T)(data);
    }

    void writeRaw(ubyte[] bytes) {
        mBuffer.write(bytes);
    }
}

class UnmarshalBuffer {
    private {
        BufferRead mBuffer;

        //functions cannot return static arrays, so this gets the equivalent
        //dynamic array type
        template RetType(T) {
            static if (is(T T2 : T2[])) {
                alias T2[] RetType;
            } else {
                alias T RetType;
            }
        }
    }

    this(ubyte[] source) {
        mBuffer = new BufferRead(source);
    }

    RetType!(T) read(T)() {
        return Unmarshaller(&readRaw).read!(T)();
    }

    private void require(uint nbytes) {
        if (mBuffer.data.length - mBuffer.position < nbytes) {
            throw new UnmarshalException("Not enough data");
        }
    }

    private void readRaw(ubyte[] data) {
        require(data.length);
        mBuffer.read(data.ptr, data.length);
    }

    //reference to raw bytes from current position until end
    ubyte[] getRest() {
        //xxx bounds checking required because position could have any value?
        return mBuffer.data()[mBuffer.position .. $];
    }
}


unittest {
    enum E {
        item1,
        item2,
        item3,
    }
    enum E2 : ushort {
        item1,
        item2,
        item3,
    }
    struct S {
        int a;
        uint b;
        short c;
        ushort d;
        byte e;
        ubyte f;
        long g;
        ulong h;
        char i;
        //wchar j;
        //dchar k;
        char[5] l;
        char[] m;
        char[][] n;
        E o;
        char[] p;
    }

    auto m = new MarshalBuffer();
    S s;
    s.a = s.c = s.e = s.g = -5;
    s.b = s.d = s.f = s.h = 5;
    s.i = /+s.j = s.k =+/ 'A';
    s.l[] = "Hello";
    s.m = "Important data";
    s.n ~= "Item 1";
    s.n ~= "Item 2";
    s.n ~= "Item 3";
    s.o = E.item2;
    s.p = null;
    m.write(s);
    m.write(E2.item3);
    ubyte[] data = m.data();

    auto um = new UnmarshalBuffer(data);
    S s2 = um.read!(S);

    foreach (int idx, x; s2.tupleof) {
        //Trace.formatln("  {} = {}", s2.tupleof[idx].stringof, x);
        assert(s.tupleof[idx] == s2.tupleof[idx]);
    }

    assert(um.read!(E2) == E2.item3);

    ubyte[1] bb;
    um = new UnmarshalBuffer(bb);
    try {
        //needs to throw UnmarshalException
        int err = um.read!(int);
        assert(false);
    } catch (UnmarshalException e) {}
}
