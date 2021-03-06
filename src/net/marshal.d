module net.marshal;

//I don't like text-based protocols :D

import utils.misc;

import std.traits;

import marray = utils.array;
import str = utils.string;
import std.base64;
import core.bitop;

//data is always written as big endian aka network byteorder
version (BigEndian) {
    private enum bool cSwapBytes = false;
} else version (LittleEndian) {
    private enum bool cSwapBytes = true;
} else {
    static assert(false, "no endian");
}

//do byte swapping, can be used to convert big <=> little endian
//xxx: could be extended to write arrays
void swapBytes(T)(ref T data) {
    //NOTE: core.bitop.bswap is apparently 32 bit (uint) only
    static if (T.sizeof <= 1) {
    } else static if (T.sizeof == 2) {
        ushort udata = cast(ushort)data;
        data = cast(T)((udata >> 8) | (udata << 8));
    } else static if (T.sizeof == 4) {
        data = cast(T)(bswap(cast(uint)data));
    } else static if (T.sizeof == 8) {
        ulong udata = cast(ulong)data;
        uint hi = udata >> 32;
        uint lo = udata & uint.max;
        data = cast(T)(bswap(hi) | ((cast(ulong)bswap(lo)) << 32));
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
 + string arrays are handled specially: utf-8 encoding is verified on reading
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
        } else static if (isIntegral!(T) || isFloatingPoint!(T)) {
            writeNumeric!(T)(data);
        } else static if (is(T == char) || is(T == immutable(char))
            || is(T == const(char)))
        {
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
        static if (isDynamicArray!(T)) {
            //always write as uint (length is size_t; usually uint or ulong)
            write!(uint)(cast(uint)data.length);
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
    //not enough data, throw an exception (an UnmarshalException would be best)
    //return value:
    //  return the number of bytes there's left _after_ the read data
    //  if you don't know exactly, return the maxmimal number of bytes possible
    //  (up to size_t.max)
    //  see require() for what this is needed
    size_t delegate(ubyte[]) reader;

    RetType!(T) read(T)() {
        static if (is(T T2 : T2[])) {
            return readArray!(T)();
        } else static if (is(T T2 == enum)) {
            T tmp = cast(T)read!(T2)();
            if (tmp < T.min || tmp > T.max)
                throw new UnmarshalException("enum out of bounds");
            return tmp;
        } else static if (isIntegral!(T) || isFloatingPoint!(T)) {
            return readNumeric!(T)();
        } else static if (is(T == char) || is(T == immutable(char))
            || is(T == const(char)))
        {
            return read!(ubyte)();
        } else static if (is(T == bool)) {
            return !!read!(ubyte)();
        } else static if (is(T == struct)) {
            T ret;
            foreach (int idx, x; ret.tupleof) {
                alias typeof(ret.tupleof[idx]) ElementT;
                ret.tupleof[idx] = read!(ElementT)();
            }
            return ret;
        } else {
            static assert(false, "No marshaller for: " ~ T.stringof);
        }
    }

    private RetType!(T) readArray(T)() {
        alias Unqual!(ForeachType!(T)) ElementUT;
        //even for static arrays, the return type needs to be dynamic
        ElementUT[] ret;

        static if (isDynamicArray!(T)) {
            //dynamic arrays store their size in the stream
            size_t arr_length = read!(uint)();
            //if a nonsensical value was read (corrupted data), avoid
            //allocating too much memory for the array...
            //assume each data element has at least one byte size
            require(arr_length);
            ret.length = arr_length;
        } else {
            //for static arrays, it's fixed
            ret.length = T.length;
        }

        //xxx: specialize for arrays that can be read on one go? (like ubyte[])
        //     1. must keep byteswapping (make swapBytes() work with arrays?)
        //     2. some types like bool or enums still need special handling
        static if (is(ElementUT == char) || is(ElementUT == ubyte)) {
            //for char and ubyte (and maybe byte), this is simple enough
            undump(ret.ptr, ret.length);
        } else {
            foreach (ref e; ret) {
                e = read!(ElementUT)();
            }
        }

        static if (isSomeString!(T)) {
            try {
                str.validate(ret);
            } catch (str.UnicodeException e) {
                throw new UnmarshalException("string not unicode conform");
            }
        }

        return cast(RetType!(T))(ret);
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

    //throw exception if not enough data in stream
    private void require(size_t size) {
        assert(!!reader);
        size_t data_left = reader(null);
        if (size > data_left)
            throw new UnmarshalException("not enough data");
    }

    //call this to ensure all data was read (no left over bytes allowed)
    void terminate() {
        assert(!!reader);
        if (reader(null) > 0)
            throw new UnmarshalException("input left after end");
    }
}

class UnmarshalException : CustomException {
    this(string msg) {
        super(msg);
    }
}

///writes out basic, array and struct types to a byte buffer
///using UnmarshalBuffer on the produced data gets the original back
///Note: stores no type information at all
///also note: allocating this as scope object (like
/// "scope marshal = new MarshalBuffer();" won't free the memory buffer; we
/// can't implement this, because the GC disallows accessing memory references
/// in the destructor)
class MarshalBuffer {
    private {
        marray.AppenderVolatile!(ubyte) mBuffer;
    }

    this() {
    }

    //clear buffer (same as a new MarshalBuffer object), but keep memory
    //arrays that have been returned by data() may be overwritten
    void reset() {
        mBuffer.length = 0;
    }

    ubyte[] data() {
        return mBuffer[];
    }

    void write(T)(T data) {
        Marshaller(&writeRaw).write!(T)(data);
    }

    final void writeRaw(ubyte[] bytes) {
        mBuffer ~= bytes;
    }
}

class UnmarshalBuffer {
    private {
        //the array is sliced as stuff is read
        ubyte[] mBuffer;
    }

    this(ubyte[] source) {
        mBuffer = source;
    }

    RetType!(T) read(T)() {
        return Unmarshaller(&readRaw).read!(T)();
    }

    private void require(size_t nbytes) {
        if (mBuffer.length < nbytes) {
            throw new UnmarshalException("Not enough data");
        }
    }

    private size_t readRaw(ubyte[] data) {
        require(data.length);
        data[] = mBuffer[0..data.length];
        mBuffer = mBuffer[data.length .. $];
        return mBuffer.length;
    }

    //reference to raw bytes from current position until end
    ubyte[] getRest() {
        return mBuffer;
    }
}

//now this is a speciality...
string marshalBase64(T)(T data) {
    auto marsh = new MarshalBuffer();
    marsh.write!(T)(data);
    return Base64.encode(marsh.data()).idup;
}

RetType!(T) unmarshalBase64(T)(string data) {
    ubyte[] dec;
    try {
        dec = Base64.decode(data);
    } catch (Exception e) {
        //base64 decoding errors (maybe)
        //the tango idiots didn't use a more appropriate Exception type
        throw new UnmarshalException("invalid base64");
    }
    auto marsh = new UnmarshalBuffer(dec);
    return marsh.read!(T)();
}

//another speciality
//Tango also has something similar, but it looked to complex etc.
//this thing is simple, stupid, and (hopefully) fast
final class Hasher {
    uint hash_value;
    bool enabled = true;

    void reset() {
        hash_value = 0;
    }

    void hash(T)(T v) {
        if (enabled)
            Marshaller(&hash_raw).write!(T)(v);
    }

    void hash_raw(ubyte[] raw) {
        foreach (b; raw) {
            hash_value ^= b;
            //rotate or something, not that it would make any sense
            hash_value = (hash_value >> 1) | (hash_value << 31);
        }
    }
}

//xxx what about a structCompare() function in misc.d?
debug void asserteq(T)(T x1, T x2) {
    foreach (int idx, _; x2.tupleof) {
        //Trace.formatln("  %s = %s", s2.tupleof[idx].stringof, x);
        assert(x1.tupleof[idx] == x2.tupleof[idx]);
    }
}

debug unittest {
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
        int[3] l2;
        string m;
        string[] n;
        E o;
        string p;
    }

    auto m = new MarshalBuffer();
    S s;
    s.a = s.c = s.e = -5;
    s.g = 123;
    s.b = s.d = s.f = 5;
    s.h = 5;
    s.i = /+s.j = s.k =+/ 'A';
    s.l[] = "Hello";
    s.l2[] = [1,2,3];
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

    asserteq(s, s2);

    assert(um.read!(E2) == E2.item3);

    asserteq(unmarshalBase64!(S)(marshalBase64(s)), s);

    ubyte[1] bb;
    um = new UnmarshalBuffer(bb);
    try {
        //needs to throw UnmarshalException
        int err = um.read!(int);
        assert(false);
    } catch (UnmarshalException e) {}
}
