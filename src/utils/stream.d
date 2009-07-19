//minimal wrapper for Tango IO
//this module cries "please kill me"
//(to be far, the Tango IO is an incomrepehensible clusterfuck, what happened to
// simplicity and ease of use?)
//main reasons:
//  - confusing .read()/.write() semantics
//  - SliceStream (couldn't find anything similar in Tango)
module utils.stream;

public import tango.core.Exception : IOException;
public import tango.io.device.Conduit : Conduit;
//important for file modes (many types/constants), even if File itself is unused
public import tango.io.device.File : File;

import tango.io.model.IConduit;
import utils.misc;




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
    }

    void readExact(ubyte[] d) {
        if (read(d).length != d.length)
            throw new IOException("could not read all data");
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
    ubyte[] out_buffer;
    size_t size;

    ubyte[] data() {
        return out_buffer[0..size];
    }

    void write(ubyte[] d) {
        if (!d.length)
            return;
        size_t left = out_buffer.length - size;
        if (d.length > left) {
            //grow array to correct size
            //somehow reduce number of future allocations by preallocating
            auto ns = out_buffer.length;
            while (ns < size+d.length) {
                ns *= 2;
                if (ns < 64)
                    ns = 64;
            }
            out_buffer.length = ns;
        }
        out_buffer[size..size+d.length] = d;
        size += d.length;
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
    void copyFrom(Stream source, ulong sz) {
        ubyte[4096*4] buffer = void;
        while (sz) {
            auto b = buffer[0..min(sz, buffer.length)];
            b = source.readUntilEof(b);
            if (b.length == 0)
                ioerror("this function sucks");
            writeExact(b);
            sz -= b.length;
        }
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
        assert(position < size);
        res.length = size - position;
        readExact(res);
        return res;
    }

    void ioerror(char[] msg) {
        throw new IOException(msg);
    }

    PipeOut pipeOut(bool allow_close = false) {
        return PipeOut(&writeExact, allow_close ? &close : null);
    }
    PipeIn pipeIn(bool allow_close = false) {
        return PipeIn(&readUntilEof, allow_close ? &close : null);
    }

    //meh
    static ConduitStream OpenFile(char[] path,
        File.Style mode = File.ReadExisting)
    {
        return new ConduitStream(castStrict!(Conduit)(new File(path, mode)));
    }
}

class ConduitStream : Stream {
    private {
        InputStream mInput;
        OutputStream mOutput;
    }

    //use File (which is a Conduit) from tango.io.device.File to open files
    this(Conduit c) {
        assert(!!c);
        //both calls return the Conduit itself
        mInput = c.input();
        mOutput = c.output();
        assert(cast(Object)mInput is cast(Object)mOutput);
    }

    //comedy
    this(InputStream i) {
        //using i.conduit() here would be wrong, because it destroys the
        //  InputFilter chain
        assert(!!i);
        mInput = i;
    }

    //returns Conduit from constructor, or null if created with an InputStream
    Conduit conduit() {
        return cast(Conduit)mInput;
    }

    ulong position() {
        //???????
        return mInput.seek(0, Conduit.Anchor.Current);
    }
    //I define that the actual position is only checked on read/write accesses
    // => IOException never thrown
    void position(ulong pos) {
        mInput.seek(pos, Conduit.Anchor.Begin);
    }

    ulong size() {
        //??????????????????????
        auto cur = position;
        auto sz = mInput.seek(0, Conduit.Anchor.End);
        position = cur;
        return sz;
    }

    size_t writePartial(ubyte[] data) {
        if (!mOutput)
            ioerror("no write access");
        auto res = mOutput.write(data);
        //probably could happen if the Conduit is a UNIX pipe or a socket
        //how the shell should I know? fuck Tango.
        if (res == Conduit.Eof)
            assert(false);
        if (data.length && res == 0)
            assert(false);
        return res;
    }

    size_t readPartial(ubyte[] data) {
        auto res = mInput.read(data);
        //????????
        if (data.length && res == 0)
            assert(false);
        //allow me to fix those shitty semantics
        if (res == Conduit.Eof)
            res = 0;
        return res;
    }

    void close() {
        mInput.close();
        //if mOutput is set, it is the same as mInput (no close needed)
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
