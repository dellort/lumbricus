module net.marshal;

//I don't like text-based protocols :D

import utils.buffer;
import utils.misc;

import tango.core.Traits;

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
        static if (is(T T2 : T2[])) {
            writeArray!(T)(data);
        } else static if (is(T T2 == enum)) {
            write!(T2)(cast(T2)data);
        } else static if (isInteger!(T)) {
            writeInt!(T)(data);
        } else static if (isCharType!(T)) {
            writeChar!(T)(data);
        } else static if (isRealType!(T)) {
            writeReal!(T)(data);
        } else static if (is(T == bool)) {
            writeInt(cast(ubyte)data);
        } else static if (is(T == struct)) {
            foreach (int idx, x; data.tupleof) {
                write!(typeof(data.tupleof[idx]))(x);
            }
        } else {
            static assert(false, "No marshaller for: " ~ T.stringof);
        }
    }

    private void writeArray(T)(T data) {
        static if (isDynamicArrayType!(T))
            write(data.length);
        //xxx minor optimization possible for static arrays, but imo not
        //    worth the fuzz
        foreach (ref item; data) {
            write(item);
        }
    }

    private void writeInt(T)(T data) {
        static assert(isInteger!(T));
        //xxx endianness? maybe later
        mBuffer.write(&data, T.sizeof);
    }

    private void writeChar(T)(T data) {
        static assert(isCharType!(T));
        mBuffer.write(&data, T.sizeof);
    }

    private void writeReal(T)(T data) {
        static assert(isRealType!(T));
        //xxx just write out the data in memory, could go wrong across platforms
        mBuffer.write(&data, T.sizeof);
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
        static if (is(T T2 : T2[])) {
            return readArray!(T)();
        } else static if (is(T T2 == enum)) {
            return cast(T)read!(T2)();
        } else static if (isInteger!(T)) {
            return readInt!(T)();
        } else static if (isCharType!(T)) {
            return readChar!(T)();
        } else static if (isRealType!(T)) {
            return readReal!(T)();
        } else static if (is(T == bool)) {
            return cast(bool)readInt!(ubyte)();
        } else static if (is(T == struct)) {
            T ret;
            foreach (int idx, x; ret.tupleof) {
                static if (isStaticArrayType!(typeof(ret.tupleof[idx]))) {
                    //need slice operator to assign to static array
                    ret.tupleof[idx][] = read!(typeof(ret.tupleof[idx]))();
                } else {
                    ret.tupleof[idx] = read!(typeof(ret.tupleof[idx]))();
                }
            }
            return ret;
        } else {
            static assert(false, "No unmarshaller for: " ~ T.stringof);
        }
    }

    private RetType!(T) readArray(T)() {
        //even for static arrays, the return type needs to be dynamic
        RetType!(T) ret;
        static if (isDynamicArrayType!(T)) {
            //dynamic arrays store their size in the stream
            ret.length = read!(size_t);
        } else {
            //for static arrays, it's fixed
            ret.length = T.length;
        }
        //just to get item type
        static if (is(T T2 : T2[])) {
            for (int i = 0; i < ret.length; i++) {
                ret[i] = read!(T2)();
            }
        } else {
            static assert(false);
        }
        return ret;
    }

    //see above on why the following functions suck
    private T readInt(T)() {
        static assert(isInteger!(T));
        T ret;
        mBuffer.read(&ret, T.sizeof);
        return ret;
    }

    private T readChar(T)() {
        static assert(isCharType!(T));
        T ret;
        mBuffer.read(&ret, T.sizeof);
        return ret;
    }

    private T readReal(T)() {
        static assert(isRealType!(T));
        T ret;
        mBuffer.read(&ret, T.sizeof);
        return ret;
    }
}


unittest {
    enum E {
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
        wchar j;
        dchar k;
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
    s.i = s.j = s.k = 'A';
    s.l[] = "Hello";
    s.m = "Important data";
    s.n ~= "Item 1";
    s.n ~= "Item 2";
    s.n ~= "Item 3";
    s.o = E.item2;
    s.p = null;
    m.write(s);
    ubyte[] data = m.data();

    auto um = new UnmarshalBuffer(data);
    S s2 = um.read!(S);

    foreach (int idx, x; s2.tupleof) {
        //Trace.formatln("  {} = {}", s2.tupleof[idx].stringof, x);
        assert(s.tupleof[idx] == s2.tupleof[idx]);
    }
}
