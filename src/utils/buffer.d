///Phobos has std.outbuffer, but this sucks and doesn't have an input
///counterpart; so here is this.
module utils.buffer;

//boilerplate code for seeking
//could also be put into a superclass instead of a mixin...
//assumes existence of uint mPosition
template SeekMixin() {
    uint position() {
        return mPosition;
    }
    void position(uint pos) {
        mPosition = pos;
    }

    void seekRelative(int rel) {
        mPosition += rel;
    }
}

///stream-like interface for reading a byte buffer
///sorry for duplicating such stream things over and over everywhere...
///xxx relies on bounds checking (D specification says we must not rely on it)
///    (but in reality, bounds checking is always switched on anyway)
final class BufferRead {
    private {
        ubyte[] mData;   //immutable
        uint mPosition;
    }

    mixin SeekMixin;

    ///source.data shall not be modified while this instance is used
    this(ubyte[] source) {
        mData = source;
    }

    ubyte[] data() {
        return mData;
    }

    ///read a range of data; note that the returned buffer belongs to this class
    ///(must .dup before changing)
    ubyte[] read(uint length) {
        auto npos = mPosition + length;
        auto res = mData[mPosition .. npos];
        mPosition = npos;
        return res;
    }

    void read(void* dest, size_t len) {
        auto npos = mPosition + len;
        dest[0..len] = mData[mPosition .. npos];
        mPosition = npos;
    }

    ///read by copying into buffer
    void read(ubyte[] buffer) {
        read(buffer.ptr, buffer.length);
    }

    ubyte readByte() {
        return mData[mPosition++];
    }
}

final class BufferWrite {
    private {
        //NOTE: could do own buffer managment, if you don't trust Phobos
        // (normally, increasing .length doesn't always need relocation)
        ubyte[] mData;
        uint mPosition;
    }

    mixin SeekMixin;

    ubyte[] data() {
        return mData;
    }

    void need_size(uint sz) {
        if (mData.length < sz)
            mData.length = sz;
    }

    void write(ubyte[] bytes) {
        write(bytes.ptr, bytes.length);
    }

    void write(void* ptr, size_t len) {
        auto npos = mPosition + len;
        need_size(npos);
        mData[mPosition .. npos] = cast(ubyte[])ptr[0..len];
        mPosition = npos;
    }

    void writeByte(ubyte b) {
        need_size(mPosition+1);
        mData[mPosition++] = b;
    }
}

debug:

unittest {
    auto wr = new BufferWrite();
    wr.writeByte(1);
    wr.write([cast(ubyte)2, 3, 4, 5]);
    auto values = [cast(ubyte)1, 2, 3, 4, 5];
    assert(wr.data == values);
    auto rd = new BufferRead(wr.data);
    assert(rd.readByte() == 1);
    assert(rd.readByte() == 2);
    ubyte[3] rest;
    rd.read(rest);
    assert(rest == [cast(ubyte)3,4,5]);
}
