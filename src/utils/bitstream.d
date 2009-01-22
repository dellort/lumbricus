module utils.bitstream;

//BitStream to read and write bits (free addressing possible)
//NOTE: D also has a std.bitarray.BitArray
//final: no virtual methods (just for satisfying performance paranoia)
final class BitStream {
    private {
        alias uint BitPos; //covers "only" 512 MB
        alias uint BitData; //used to store bits
        BitData[] mData;
        const BIT_COUNT = BitData.sizeof * 8;
        //when writing, mPos is the index after the last valid bit
        BitPos mBitPos, mBitSize;
    }

    /// Get data as ubyte[] (not copied).
    ubyte[] data() {
        return (cast(ubyte[])mData)[0..(mBitSize+7)/8];
    }

    /// Set data as ubyte[] (copied).
    void data(ubyte[] data) {
        //erm... to simplify things.
        bitPos = 0;
        bitSize = 0;
        writeAlignedBytes(data);
        bitPos = 0;
    }

    //actually write bits
    //this also increases the buffer as needed, and it doesn't overwrite bits
    //after (bitPos + count)
    private void doWriteBits(BitPos at, BitData data, uint count) {
        assert(count <= BIT_COUNT);
        if (count == 0)
            return;

        //mask unwanted bits to leave the stream bits following it unchanged
        //that if() is needed because (1<<32) == 1
        if (count > BIT_COUNT)
            data &= ((1<<count)-1);

        BitPos bitEndPos = at + count;

        //byteEnd is rounded up to the next byte, but actually, that doesn't
        //really matter, as long the array isn't too small...
        size_t byteEnd = (bitEndPos + BIT_COUNT - 1) / BIT_COUNT;
        if (mData.length < byteEnd)
            mData.length = byteEnd;

        BitPos bitStart = at % BIT_COUNT;
        BitPos bitLast = (bitEndPos-1) % BIT_COUNT;
        BitData maskBefore = ((1<<bitStart) - 1);   //before new bits
        BitData maskAfter = ~((1<<(bitLast+1)) - 1);  //after new bits
        //arrgh, (1<<32)==1?!
        if (bitLast+1 == BIT_COUNT) {
            assert(maskAfter == BitData.max);
            maskAfter = 0;
        }

        BitData* ptr = &mData[at / BIT_COUNT];

        if (bitStart + count <= BIT_COUNT) {
            ptr[0] = (ptr[0] & (maskBefore | maskAfter))
                | (data << bitStart);
        } else {
            ptr[0] = (ptr[0] & maskBefore) | (data << bitStart);
            ptr[1] = (ptr[1] & maskAfter) | (data >> (BIT_COUNT - bitStart));
        }

        if (mBitSize < bitEndPos)
            mBitSize = bitEndPos;
    }

    //actually read bits
    //(argh, core code is cut&paste from doWriteBits())
    BitData doReadBits(BitPos at, uint count) {
        assert(count <= BIT_COUNT);
        if (count == 0)
            return 0;

        BitPos bitEndPos = at + count;

        if (bitEndPos > mBitSize)
            throw new Exception("read beyond end of stream");

        BitPos bitStart = at % BIT_COUNT;

        BitData* ptr = &mData[at / BIT_COUNT];
        BitData res;

        res = ptr[0] >> bitStart;

        if (bitStart + count > BIT_COUNT) {
            res |= ptr[1] << (BIT_COUNT - bitStart);
        }

        return (count == BIT_COUNT) ? res : res & ((1<<count)-1);
    }

    void writeBits(uint bits, uint bitcount) {
        static assert(bits.sizeof >= BitData.sizeof);
        doWriteBits(mBitPos, bits, bitcount);
        mBitPos += bitcount;
    }
    uint readBits(uint bitcount) {
        uint res;
        static assert(res.sizeof >= BitData.sizeof);
        res = doReadBits(mBitPos, bitcount);
        mBitPos += bitcount;
        return res;
    }

    //of course these could be made faster...
    void writeBool(bool b) {
        doWriteBits(mBitPos, cast(uint)b, 1);
        mBitPos++;
    }
    bool readBool() {
        bool res = !!doReadBits(mBitPos, 1);
        mBitPos++;
        return res;
    }

    //write arbitrary amount of bits
    //inefficient (has to work hard for each byte)
    //NOTE: writeBits() cares about endianess, this doesn't at all *g*
    void writeAnyBits(void* data, uint bitcount) {
        //byte granularity to not-to-dereference past the data memory block
        ubyte* bytes = cast(ubyte*)data;
        while (bitcount >= 8) {
            writeBits(*bytes, 8);
            bitcount -= 8;
            bytes++;
        }
        //remainder (also works if 0)
        writeBits(*bytes, bitcount);
    }

    //(last byte is filled to zero if bitcount % 8 != 0)
    void readAnyBits(void* data, uint bitcount) {
        ubyte* bytes = cast(ubyte*)data;
        while (bitcount >= 8) {
            *bytes = readBits(8);
            bitcount -= 8;
            bytes++;
        }
        //remainder (also works if 0)
        *bytes = readBits(bitcount);
    }

    //templated functions, which should work for all value types
    //xxx: endian-situation unclear
    //xxx: currently actually only works for integers (but could be changed)
    void write(T)(T data, uint bitcount) {
        assert(bitcount <= T.sizeof*8);
        static if (T.sizeof > BitData.sizeof) {
            writeAnyBits(&data, bitcount);
        } else {
            doWriteBits(mBitPos, data, bitcount);
            mBitPos += bitcount;
        }
    }
    T read(T)(uint bitcount) {
        assert(bitcount <= T.sizeof*8);
        T data;
        static if (T.sizeof > BitData.sizeof) {
            readAnyBits(&data, bitcount);
        } else {
            data = doReadBits(mBitPos, bitcount);
            mBitPos += bitcount;
        }
        return data;
    }
    //read and use most significant bit for sign extension
    T readSigned(T)(uint bitcount) {
        T data = read!(T)(bitcount);
        if (data & (1<<(bitcount-1))) {
            data |= ~((1<<bitcount)-1);
        }
        return data;
    }

    size_t bitSize() {
        return mBitSize;
    }
    void bitSize(size_t set) {
        assert(mData.length == (mBitSize+BIT_COUNT-1) / BIT_COUNT);
        mData.length = (set+BIT_COUNT-1) / BIT_COUNT;
        if (set > mBitSize) {
            //kill left-over trailing bits
            BitPos pad = (set+BIT_COUNT-1) % BIT_COUNT;
            mData[mBitSize / BIT_COUNT] &= ~(1<<pad)-1;
        }
        mBitSize = set;
    }

    size_t bitPos() {
        return mBitPos;
    }
    void bitPos(size_t set) {
        mBitPos = set;
    }

    bool[] toBoolArray() {
        bool[] res;
        res.length = bitSize;
        foreach (int index, inout b; res) {
            b = !!doReadBits(index, 1);
        }
        return res;
    }

    void init(bool[] data) {
        bitSize = data.length;
        bitPos = 0;
        foreach (int index, b; data) {
            doWriteBits(index, cast(uint)b, 1);
        }
    }

    /// Align bitPos to next byte-boundary and then write the data bytes.
    void writeAlignedBytes(ubyte[] data) {
        bitPos = (bitPos+7) & ~7;
        size_t npos = bitPos + data.length * 8;
        bitSize = npos;
        (cast(ubyte[])mData)[bitPos/8 .. npos/8] = data[];
        bitPos = npos;
    }

    void clear() {
        mData = null;
        mBitSize = mBitPos = 0;
    }

    this() {
    }

    this(bool[] data) {
        init(data);
    }
}

debug import stdx.stdio;

unittest {
    BitStream s = new BitStream();

    //side effect: seek to end
    uint[] uints() {
        uint[] res;
        res.length = (s.bitSize+31)/32;
        s.bitPos = 0;
        s.readAnyBits(res.ptr, s.bitSize);
        return res;
    }

    //basic bit-reading
    bool[] foo = [cast(bool)1, 0, 1, 1, 0];
    s.init(foo);
    assert(uints() == [0b01101u]);
    assert(s.toBoolArray() == foo);
    s.bitPos = 0;
    assert(s.readBits(3) == 0b101);
    s.bitPos = 1;
    assert(s.readBits(3) == 0b110);
    s.bitPos = 2;
    assert(s.readBits(3) == 0b011);
    //... and writing
    s.bitPos = 1;
    s.writeBits(1, 1);
    assert(uints() == [0b1111u]);
    s.bitPos = 1;
    s.writeBits(0, 1);
    assert(uints() == [0b1101u]);
    s.bitPos = 2;
    s.writeBits(0b100, 3);
    assert(uints() == [0b10001u]);
    assert(s.bitSize == 5);
    s.writeBits(0b101, 3);
    assert(uints() == [0b10110001u]);
    assert(s.bitSize == 8);
    //reading & writing with boundaries
    assert(BitStream.BitData.sizeof == uint.sizeof); //correct test if not
    s.bitPos = 0;
    s.writeBits(0b10101010101010101010101010101010, 32);
    s.bitPos = 0;
    assert(s.readBits(32) == 0b10101010101010101010101010101010);
    s.bitPos = 32;
    s.writeBits(0b101, 3);
    s.bitPos = 32;
    assert(s.readBits(3) == 0b101);
    //cross-read
    s.bitPos = 32-3;
    assert(s.readBits(6) == 0b101101);
    //cross-write
    s.bitPos = 32-5;
    s.writeBits(0b0110111011, 10);
    assert(uints() == [0b11011010101010101010101010101010,0b01101]);

    //read sign extended
    s.bitPos = 0;
    s.write!(int)(-5, 4);
    s.write!(int)(0, 1);
    s.bitPos = 0;
    assert(s.read!(int)(5) == 0b01011);
    s.bitPos = 0;
    assert(s.readSigned!(int)(4) == -5);

    debug writefln("bitstream.d unittest: passed.");
}
