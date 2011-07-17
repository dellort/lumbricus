//minimal wrapper for Tango IO
//this module cries "please kill me"
//(to be far, the Tango IO is an incomrepehensible clusterfuck, what happened to
// simplicity and ease of use?)
//main reasons:
//  - confusing .read()/.write() semantics
//  - SliceStream (couldn't find anything similar in Tango)
module utils.stream;

public import tango.io.device.Conduit : Conduit;
//important for file modes (many types/constants), even if File itself is unused
public import tango.io.device.File : File;

import tango.io.model.IConduit;
import tango.core.Runtime;
import utils.misc;

import marray = utils.array;

import std.file;
// maybe? the shitty phobos docs are nebulous
//alias FileException IOException;
import std.exception;
alias ErrnoException IOException;

//HAHAHAHAHAHAHAHAHAHAHAHAHA
//actually, I don't feel like inventing my own I/O API
//so, if anyone happens to know which are the exact Tango equivalents...
//
//Rationale: I wanted simple pipe-like I/O (no seeking), but somehow read/write
//  callbacks weren't enough; I needed additional calls like close().
//  => pack several callbacks into structs.
//
//Notes:
// - users shall use opCall, and avoid accessing the delegate vars directly
// - feel free to add more functions
// - feel free to add more delegates, as long as they are optional and/or can
//   be emulated with just the normal read/write delegate
// - the structs never must contain mutable state (makes them unsafe for
//   copying); allocate an object for that

//for writing
struct PipeOut {
    void delegate(ubyte[]) do_write;
    void delegate() do_close;

    static const PipeOut Null;

    static PipeOut opCall(typeof(do_write) w, typeof(do_close) c = null) {
        PipeOut r;
        assert(!!w);
        r.do_write = w;
        r.do_close = c;
        return r;
    }

    bool isNull() {
        return !do_write;
    }

    //semantics: see Stream.writeExact()
    void write(ubyte[] data) {
        if (do_write) {
            do_write(data);
        } else {
            throw new IOException("pipe not connected for writing");
        }
    }

    void close() {
        if (do_close) do_close();
        do_write = null;
        do_close = null;
    }

    //sz==ulong.max: special case; copy until eof
    void copyFrom(PipeIn source, ulong sz = ulong.max) {
        ubyte[4096*4] buffer = void;
        bool until_eof = sz == ulong.max;
        while (sz) {
            auto b = buffer[0..min(sz, buffer.length)];
            b = source.read(b);
            if (b.length == 0) {
                if (until_eof)
                    return;
                throw new IOException("not enough to read");
            }
            write(b);
            if (!until_eof)
                sz -= b.length;
        }
    }
}

//for reading
struct PipeIn {
    ubyte[] delegate(ubyte[]) do_read;
    void delegate() do_close;

    static const PipeIn Null;

    static PipeIn opCall(typeof(do_read) rd, typeof(do_close) c = null) {
        PipeIn r;
        assert(!!rd);
        r.do_read = rd;
        r.do_close = c;
        return r;
    }

    bool isNull() {
        return !do_read;
    }

    //semantics: see Stream.readUntilEof()
    //(everything is read, except on EOF)
    //xxx: simply "auto close" when EOF is reached?
    ubyte[] read(ubyte[] buffer) {
        if (do_read) {
            return do_read(buffer);
        } else {
            throw new IOException("pipe not connected for reading");
        }
    }
    void close() {
        if (do_close) do_close();
        do_read = null;
        do_close = null;
    }

    void readExact(ubyte[] d) {
        if (read(d).length != d.length)
            throw new IOException("could not read all data");
    }

    //works like readExact, but throw away read bytes
    void skip(size_t len) {
        //obviously room for improvement here
        ubyte[512] garbage = void;
        while (len) {
            size_t eat = min(len, garbage.length);
            readExact(garbage[0..eat]);
            len -= eat;
        }
    }

    //read until EOF is reached
    //should this automatically call close()???
    ubyte[] readAll(size_t size_hint = 0) {
        if (size_hint < 64)
            size_hint = 64;
        ubyte[] dest;
        dest.length = size_hint * 2;
        size_t pos = 0;
        for (;;) {
            assert(pos < dest.length);
            auto res = read(dest[pos..$]);
            pos += res.length;
            if (res.length == 0) {
                dest = dest[0..pos];
                //close();
                return dest;
            }
            //enlarge buffer
            dest.length = dest.length*2;
        }
    }
}


//meh
struct ArrayReader {
    ubyte[] data;

    ubyte[] read(ubyte[] d) {
        size_t s = min(d.length, data.length);
        d[0..s] = data[0..s];
        data = data[s..$];
        return d[0..s];
    }

    PipeIn pipe() {
        return PipeIn(&read);
    }
}

struct ArrayWriter {
    //buffer that will be used (if large enough, no additional memory alloc.)
    //use data() to get actual data
    marray.Appender!(ubyte) out_buffer;

    ubyte[] data() {
        return out_buffer[];
    }

    void write(ubyte[] d) {
        if (!d.length)
            return;
        out_buffer ~= d;
    }

    PipeOut pipe() {
        return PipeOut(&write);
    }
}


abstract class Stream {
    abstract {
        ulong position();
        //I define that the actual position is only checked on read/write
        //  accesses => IOException never thrown
        void position(ulong pos);
        ulong size();

        //both calls:
        //  return a value 0 <= return <= data.length
        //  if 0 is returned and data.length>0 => EOF is reached
        //  else, if something < data.length is returned, then either
        //      - underlying stream couldn't handle all data, you must retry
        //        with data[return..$] (don't know what needs these semantics)
        //      - EOF was reached while reading data
        //actually, these semantics are almost the same as UNIX/stdio
        protected size_t writePartial(ubyte[] data);
        protected size_t readPartial(ubyte[] data);

        void close();
    }

    void seekRelative(ulong rel) {
        position = position + rel;
    }

    bool eof() {
        //yep. and it costs only 4 seek calls
        return position == size;
    }

    void writeExact(ubyte[] data) {
        while (data.length) {
            auto r = writePartial(data);
            if (r == 0)
                ioerror("?");
            data = data[r..$];
        }
    }

    void readExact(ubyte[] data) {
        while(data.length) {
            auto r = readPartial(data);
            if (r == 0)
                ioerror("end of file reached");
            data = data[r..$];
        }
    }

    //wanted to change all those calls, but gave up midways
    //don't use for new code or I'll punch you
    void writeExact(void* ptr, size_t sz) {
        writeExact(cast(ubyte[])ptr[0..sz]);
    }
    void readExact(void* ptr, size_t sz) {
        readExact(cast(ubyte[])ptr[0..sz]);
    }

    //like readExact, but a partial read when EOF is hit is allowed
    //if EOF isn't reached, behave exactly as readExact
    //the returned slice is data[0..size_actually_read]
    ubyte[] readUntilEof(ubyte[] data) {
        ubyte[] org = data;
        size_t read;
        while(data.length) {
            auto r = readPartial(data);
            if (r == 0)
                return org[0..read];
            read += r;
            data = data[r..$];
        }
        return org;
    }

    //read from position .. size
    ubyte[] readAll() {
        ubyte[] res;
        assert(position <= size);
        res.length = size - position;
        readExact(res);
        return res;
    }

    void ioerror(string msg) {
        throw new IOException(msg);
    }

    PipeOut pipeOut(bool allow_close = false) {
        return PipeOut(&writeExact, allow_close ? &close : null);
    }
    PipeIn pipeIn(bool allow_close = false) {
        return PipeIn(&readUntilEof, allow_close ? &close : null);
    }

    //meh
    static ConduitStream OpenFile(string path, string mode) {
        return new ShitStream(File(path, mode));
    }
}

//I wanted to name this PhobosStream, but I think this name is better
class ShitStream : Stream {
    private {
        File mShit;
    }

    //use File (which is a Conduit) from tango.io.device.File to open files
    this(File s) {
        mShit = s;
    }

    ulong position() {
        //XXXTANGO may throw
        return mShit.tell;
    }
    //I define that the actual position is only checked on read/write accesses
    // => IOException never thrown
    void position(ulong pos) {
        //XXXTANGO may throw
        mShit.seek(pos);
    }

    ulong size() {
        //XXXTANGO may throw
        return mShit.size;
    }

    size_t writePartial(ubyte[] data) {
        mShit.rawWrite(data);
        return data.length;
    }

    size_t readPartial(ubyte[] data) {
        return mShit.rawRead(data).length;
    }

    void close() {
        mShit.close();
    }
}

class SliceStream : Stream {
    private {
        Stream mSource;
        ulong mLow, mHigh;
        ulong mPos;
    }

    //window into byte range [low..inf) of source
    this(Stream source, ulong low) {
        this(source, low, ulong.max);
    }
    //window into byte range [low..high) of source
    this(Stream source, ulong low, ulong high) {
        mSource = source;
        mLow = low;
        mHigh = high;
        if (mLow > mHigh)
            assert(false, "SliceStream: low > high");
    }

    ulong position() {
        return mPos;
    }
    void position(ulong pos) {
        mPos = pos;
    }

    ulong size() {
        return clampRangeC(mSource.size, mLow, mHigh) - mLow;
    }

    private void fixAndSeek(ref ubyte[] data) {
        ulong dest = mPos + mLow; //final write position
        if (dest >= mHigh) {
            data = null;
            return;
        }
        //don't allow to read/write beyond mHigh limit
        data = data[0..min(data.length, mHigh - dest)];
        //seek... meh, on every single read/write
        mSource.position = dest;
    }

    size_t writePartial(ubyte[] data) {
        fixAndSeek(data);
        auto res = mSource.writePartial(data);
        mPos += res;
        return res;
    }

    size_t readPartial(ubyte[] data) {
        fixAndSeek(data);
        auto res = mSource.readPartial(data);
        mPos += res;
        return res;
    }

    void close() {
        //you don't want to close the source stream
        //actually, the source stream should be ref-counted or so
        //disable access to source stream, though
        mSource = null;
    }

    //return null if closed
    Stream source() {
        return mSource;
    }
}

//add seek functionality to a non-seekable stream
//when seeking outside the buffer area, the stream will be recreated
//xxx holy stupidity xD
class SeekFixStream : Stream {
    private ulong mForcedSize;
    private ulong mPos;
    InputStream delegate() mOpenDg;
    InputStream mInput;
    //Very often (read: in lumbricus, over 90%), only a small header area is
    //  read and then the position is reset to 0
    //In that case, we do not need to recreate the base stream but can use
    //  the buffered content
    //The other 10% are long seeks over the whole filesize and not relevant for
    //  buffering
    ubyte[256] mBuffer;
    size_t mBufferSize;

    this(InputStream delegate() open, ulong forcedSize) {
        mOpenDg = open;
        mInput = open();
        mForcedSize = forcedSize;
    }

    ulong size() {
        return mForcedSize;
    }

    ulong position() {
        return mPos;
    }
    void position(ulong pos) {
        if (mPos != pos) {
            if (mPos <= mBufferSize && pos < mBufferSize) {
                //going back inside buffer area
                mPos = pos;
            } else {
                //input is not seekable, so recreate and skip to pos
                mInput = mOpenDg();
                mPos = 0;
                skip(pos);
            }
        }
    }

    //skip over count bytes (because we cannot seek)
    private void skip(ulong count) {
        size_t bufs = mInput.conduit.bufferSize;
        auto buffer = new ubyte[bufs];
        while (count > bufs) {
            readPartial(buffer);
            count -= bufs;
        }
        readPartial(buffer[0..count]);
    }

    protected size_t writePartial(ubyte[] data) {
        ioerror("read only");
        return 0;
    }

    protected size_t readPartial(ubyte[] data) {
        size_t res;
        if (mPos < mBufferSize) {
            //buffered
            res = min(data.length, mBufferSize - cast(size_t)mPos);
            data[0..res] = mBuffer[mPos..mPos+res];
            mPos += res;
        }
        if (res < data.length) {
            //not buffered
            ubyte[] rdata = data[res..$];
            size_t readRes = mInput.read(rdata);
            if (readRes == Conduit.Eof)
                readRes = 0;
            if (mBufferSize < mBuffer.length && readRes > 0) {
                size_t count = min(mBuffer.length - mBufferSize, readRes);
                mBuffer[mBufferSize..mBufferSize+count] = rdata[0..count];
                mBufferSize += count;
            }
            mPos += readRes;
            res += readRes;
        }
        return res;
    }

    void close() {
        mInput.close();
        mOpenDg = null;
        mBufferSize = 0;
    }
}

//needed this for debugging

class MemoryStream : Stream {
    private {
        ubyte[] mBloat;
        size_t mPos;
    }

    ulong position() {
        return mPos;
    }

    void position(ulong pos) {
        mPos = pos;
    }

    ulong size() {
        return mBloat.length;
    }

    protected size_t writePartial(ubyte[] data) {
        mBloat.length = position + data.length;
        mBloat[position .. position + data.length] = data;
        mPos += data.length;
        return data.length;
    }

    protected size_t readPartial(ubyte[] data) {
        auto max = min(position + data.length, mBloat.length);
        if (max < position)
            return 0;
        size_t len = max - position;
        data[0..len] = mBloat[position .. max];
        mPos += len;
        return len;
    }

    void close() {
        mBloat = null;
    }
}

