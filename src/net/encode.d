//some helper routines to write data into a stream
module net.encode;

import utils.bitstream;
import utils.buffer;
import utils.misc;

///just another stream-like class, argghh!
///provides byte- and bit-writing methods, with a different byte and bit-stream
///this should be reasonable fast and space-efficient, but both streams are
///completely separate
final class NetWriter {
    private {
        BufferWrite mBytes;
        BitStream mBits;
    }

    this() {
        mBytes = new BufferWrite;
        mBits = new BitStream;
    }

    ///build a byte array which contains both streams
    ubyte[] flush() {
        ubyte[] bits = mBits.data();
        ubyte[] bytes = mBytes.data();
        ubyte[] result;
        result.length = 4 + bits.length + bytes.length;
        auto len = bits.length;
        result[0] = len & 0xff;
        result[1] = (len >> 8) & 0xff;
        result[2] = (len >> 16) & 0xff;
        result[3] = (len >> 24) & 0xff;
        result[4 .. 4 + len] = bits;
        result[4 + len .. 4 + len + bytes.length] = bytes;
        return result;
    }

    //-- bytestream
    void write(ubyte[] data) {
        mBytes.write(data);
    }
    void writeByte(ubyte b) {
        mBytes.writeByte(b);
    }

    //-- bitstream
    void writeBit(bool b) {
        mBits.writeBool(b);
    }
}

final class NetReader {
    private {
        BufferRead mBytes;
        BitStream mBits;
    }

    ///create a byte- and a bit-stream from a linear byte buffer
    /// data = what NetWriter.flush() delivered
    this(ubyte[] data) {
        uint len;
        len = data[0];
        len |= data[1] << 8;
        len |= data[2] << 16;
        len |= data[3] << 24;

        mBits = new BitStream();
        mBits.data = data[4 .. 4 + len];
        mBytes = new BufferRead(data[4 + len .. $]);
    }

    //-- bytestream
    void read(ubyte[] data) {
        mBytes.read(data);
    }
    ubyte readByte() {
        return mBytes.readByte();
    }

    //-- bitstream
    bool readBit() {
        return mBits.readBool();
    }
}

//byte granular variable length encodings of integers
//smaller numbers are encoded in less bytes
//uses the bitstream for the continuation flags
//(also possible: no bitstream and use highest bit for that flag => 7 bits data)

void write_unsigned_vlen(T)(NetWriter dest, T value) {
    static assert(isUnsigned!(T));
    int i;
    do {
        ubyte b = value;
        value = value >> 8;
        dest.writeByte(b);
        dest.writeBit(!!value);
    } while(value);
}

T read_unsigned_vlen(T)(NetReader source) {
    static assert(isUnsigned!(T));
    T res;
    int i;
    ubyte b;
    do {
        b = source.readByte();
        res |= (b) << (8*i);
        i++;
    } while (source.readBit());
    return res;
}

//infinitely perverted and stupid way to smushify a signed value into a
//  variable-length encodeable series of bits:
//  1. turn the 2 complements representation into (sign, number), no complements
//  2. rotate the sign bit so that it is the LSB
//  result: low (unsigned) numerical value for small negative/positive numbers
T smurf(T)(T value) {
    static assert(isSigned!(T));
    int neg = value < 0;
    if (neg)
        value = -value;
    value = neg | (value << 1);
    return value;
}

// unsmurf(smurf(x)) == x
T unsmurf(T)(T value) {
    static assert(isSigned!(T));
    //argh, >>> doesn't work, acts same as >>, wtf! so simply cast to unsigned.
    T r = cast(unsigned!(T))value >> 1;
    if (value & 1) {
        r = -r;
        //special case: "-0" is T.min
        if (r == 0)
            r = T.min;
    }
    return r;
}

T read_signed_vlen(T)(NetReader source) {
    static assert(isSigned!(T));
    return unsmurf!(T)(read_unsigned_vlen!(unsigned!(T))(source));
}

void write_signed_vlen(T)(NetWriter dest, T value) {
    static assert(isSigned!(T));
    write_unsigned_vlen!(unsigned!(T))(dest, smurf!(T)(value));
}

///write an integer type (any for which isInteger!(T) is true) with a byte-
///granular variable length
///i.e. unsigned values from 0..255 always need only 1 byte (+ 1 bit),
/// signed values from -128..127 also only one byte
void write_integer_vlen(T)(NetWriter dest, T value) {
    static assert(isInteger!(T));
    static if (isSigned!(T))
        write_signed_vlen!(T)(dest, value);
    else
        write_unsigned_vlen!(T)(dest, value);
}

///opposite of write_integer_vlen(T)
T read_integer_vlen(T)(NetReader source) {
    static assert(isInteger!(T));
    static if (isSigned!(T))
        return read_signed_vlen!(T)(source);
    else
        return read_unsigned_vlen!(T)(source);
}

///as needed by marshaller
void write_integer_delta(T)(NetWriter dest, T newv, T oldv) {
    write_integer_vlen!(forceSigned!(T))(dest, newv - oldv);
}
T read_integer_delta(T)(NetReader source, T oldv) {
    return read_integer_vlen!(forceSigned!(T))(source) + oldv;
}

void write_bool(NetWriter dest, bool b) {
    dest.writeBit(b);
}
bool read_bool(NetReader source) {
    return source.readBit();
}

//trivial wrappers
//no delta coding, makes no sense here
void write_bool_delta(NetWriter dest, bool newv, bool oldv) {
    write_bool(dest, newv);
}
bool read_bool_delta(NetReader source, bool oldv) {
    return read_bool(source);
}
//delta coding would only make sense with bitstreams or so
//for ubyte, byte, char
void write_byte_delta(T)(NetWriter dest, T newv, T oldv) {
    dest.writeByte(cast(ubyte)newv);
}
T read_byte_delta(T)(NetReader source, T oldv) {
    return cast(T)source.readByte();
}

//quite stupid encoding of floats just so that we can encode/decode them at all
//needs better encoding (i.e. somewhat compressed)
private union FloatToBytes {
    float f;
    ubyte[4] i;
}
void write_float(NetWriter dest, float f) {
    FloatToBytes fb;
    fb.f = f;
    dest.write(fb.i);
}
float read_float(NetReader source) {
    FloatToBytes fb;
    source.read(fb.i);
    return fb.f;
}

//dummies for marshaller stuff (needs compression etc.)
//encoding is already lossful (by the substraction/addition)
//on idea to implement can be found here (packing a float into a bitfield):
//  http://www.gamedev.net/community/forums/showfaq.asp?forum_id=15
void write_float_delta(NetWriter dest, float newv, float oldv) {
    write_float(dest, newv - oldv);
}
float read_float_delta(NetReader source, float oldv) {
    return read_float(source) + oldv;
}

debug import std.stdio, std.string;

debug void smurftest(T)() {
    void dotest(T num) {
        assert(unsmurf!(T)(smurf!(T)(num)) == num);
    }
    dotest(6);
    dotest(-6);
    dotest(0);
    dotest(T.max);
    dotest(T.min);
    dotest(T.max-1);
    dotest(T.min+1);
}

unittest {
    smurftest!(long)();
    smurftest!(int)();
    smurftest!(short)();
    smurftest!(byte)();
    //just ensure it does what it's supposed to
    assert(cast(uint)smurf(5) < 64u && cast(uint)smurf(-5) < 64u);

    //write some values, expect them to get back
    auto wr = new NetWriter;

    //16384 = 2^14
    uint[] values = [9,123,123456,16383,16384,uint.max-1,uint.max];
    foreach (i; values) {
        write_unsigned_vlen!(uint)(wr, i);
    }
    int[] ivalues = [3,-65,45,-24,int.min,int.min+1,16383,16384,-16383,-16484];
    foreach (i; ivalues) {
        write_signed_vlen!(int)(wr, i);
    }
    write_signed_vlen!(byte)(wr, -123);
    write_integer_delta!(short)(wr, -123, 16666);
    write_bool(wr, false);
    write_bool(wr, true);
    write_float(wr, float.infinity);

    auto data = wr.flush;
    //writefln(data);
    auto rd = new NetReader(data);

    foreach (i; values) {
        auto v = read_unsigned_vlen!(uint)(rd);
        assert(v == i);
    }
    foreach (i; ivalues) {
        auto v = read_signed_vlen!(int)(rd);
        assert(v == i);
    }
    assert(read_signed_vlen!(byte)(rd) == -123);
    assert(read_integer_delta!(short)(rd, 16666) == -123);
    assert(read_bool(rd) == false);
    assert(read_bool(rd) == true);
    assert(read_float(rd) == float.infinity);

    //assert(rd.position == rd.data.length);

    debug writefln("net.encode unittest passed.");
}
