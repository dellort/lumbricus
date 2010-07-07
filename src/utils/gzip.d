module utils.gzip;

import utils.stream;

//hack for tango 0.99.9 <-> svn trunk change
import tango.core.Version;
static if (Tango.Major == 0 && Tango.Minor == 999) {
    import czlib = tango.io.compress.c.zlib;
} else {
    import czlib = tango.util.compress.c.zlib;
}

enum {
    MAX_WBITS = 15,  //from zconf.h
}

//adapted from Phobos' std.zlib, license was public domain
class ZlibException : Exception {
    this(int errnum) {
        char[] msg;

        switch (errnum)
        {
            case czlib.Z_STREAM_END:      msg = "stream end"; break;
            case czlib.Z_NEED_DICT:       msg = "need dict"; break;
            case czlib.Z_ERRNO:           msg = "errno"; break;
            case czlib.Z_STREAM_ERROR:    msg = "stream error"; break;
            case czlib.Z_DATA_ERROR:      msg = "data error"; break;
            case czlib.Z_MEM_ERROR:       msg = "mem error"; break;
            case czlib.Z_BUF_ERROR:       msg = "buf error"; break;
            case czlib.Z_VERSION_ERROR:   msg = "version error"; break;
            default:                      msg = "unknown error"; break;
        }
        super(msg);
    }
}

///pack passed array with zlib and add gzip header and footer
ubyte[] gzipData(ubyte[] data) {
    ArrayWriter a;
    auto writer = new GZWriter(&a.write);
    writer.write(data);
    writer.finish();
    return a.data();
}

class GZWriter {
    private {
        void delegate(ubyte[] data) onWrite;
        ubyte[] buffer;
        size_t buffer_pos;
        czlib.z_stream zs;
    }

    void delegate() close_fn;

    this(void delegate(ubyte[] data) a_onWrite, bool use_gzip = true,
        int level = czlib.Z_DEFAULT_COMPRESSION, size_t buffer_size = 64*1024)
    {
        assert (!!a_onWrite);
        assert ((level >= 0 && level <= 9)
            || (level == czlib.Z_DEFAULT_COMPRESSION));
        assert (buffer_size > 0);
        onWrite = a_onWrite;
        buffer.length = buffer_size;
        buffer_pos = 0;
        //16: gzip header, 15: window bits
        //9: "memLevel=9 uses maximum memory for optimal speed."
        //libpng uses memlevel=8 *shrug*
        int res = czlib.deflateInit2(&zs, level, czlib.Z_DEFLATED,
            (use_gzip ? 16 : 0) + 15, 8, czlib.Z_DEFAULT_STRATEGY);
        zerror(res);
    }

    static PipeOut Pipe(PipeOut writer) {
        auto w = new GZWriter(writer.do_write);
        w.close_fn = writer.do_close;
        return w.pipe();
    }

    private void zerror(int err) {
        if (err == czlib.Z_OK)
            return; //error: no error.
        throw new ZlibException(err);
    }

    private void buffer_flush(bool force = false) {
        if (buffer_pos >= buffer.length || force) {
            onWrite(buffer[0..buffer_pos]);
            buffer_pos = 0;
        }
    }

    void write(ubyte[] data) {
        assert (!!buffer.ptr);
        while (data.length) {
            buffer_flush();
            zs.next_out = &buffer[buffer_pos];
            zs.avail_out = buffer.length - buffer_pos;
            int was_avail = zs.avail_out;
            zs.next_in = data.ptr;
            zs.avail_in = data.length;
            int res = czlib.deflate(&zs, czlib.Z_NO_FLUSH);
            zerror(res);
            buffer_pos += was_avail - zs.avail_out;
            data = data[$ - zs.avail_in .. $];
        }
        assert (zs.avail_in == 0);
    }

    //also frees any zlib stream state etc.
    void finish() {
        assert (!!buffer.ptr);
        for (;;) {
            buffer_flush();
            zs.next_out = &buffer[buffer_pos];
            zs.avail_out = buffer.length - buffer_pos;
            int was_avail = zs.avail_out;
            zs.next_in = null;
            zs.avail_in = 0;
            int res = czlib.deflate(&zs, czlib.Z_FINISH);
            bool end = (res == czlib.Z_STREAM_END);
            if (!end) {
                zerror(res);
            }
            buffer_pos += was_avail - zs.avail_out;
            if (end)
                break;
        }
        buffer_flush(true);
        czlib.deflateEnd(&zs);
        delete buffer; //why do I need a buffer anyway?
        buffer = null;
        if (close_fn) {
            close_fn();
            close_fn = null;
        }
    }

    PipeOut pipe() {
        return PipeOut(&write, &finish);
    }
}

//gzipData^-1
ubyte[] gunzipData(ubyte[] cmpData) {
    ArrayReader x;
    x.data = cmpData;
    auto reader = new GZReader(&x.read);
    return reader.read_all(cmpData.length);
}

class GZReader {
    private {
        ubyte[] delegate(ubyte[]) onRead;
        ubyte[] real_buffer;
        ubyte[] buffer;
        czlib.z_stream zs;
    }

    void delegate() close_fn;

    //onRead() can return as much data as it wants
    //if onRead() doesn't know where the zlib stream ends, it might return more
    //data than needed, which ends up unused. the return value of finish() can
    //be used to see how much data was unused.
    this(ubyte[] delegate(ubyte[]) a_onRead, size_t buffer_sz = 64*1024) {
        assert (!!a_onRead);
        onRead = a_onRead;
        buffer = null;
        real_buffer.length = buffer_sz;
        //32: gzip/zlib header, 15: window bits
        int res = czlib.inflateInit2(&zs, 32 + 15);
        zerror(res);
    }

    static PipeIn Pipe(PipeIn writer) {
        auto r = new GZReader(writer.do_read);
        r.close_fn = writer.do_close;
        return r.pipe();
    }

    private void zerror(int err) {
        if (err == czlib.Z_OK)
            return; //error: no error.
        throw new ZlibException(err);
    }

    //return the slice data[0..data_read]
    //unless the end of the stream was reached, data_read is always data.length
    ubyte[] read(ubyte[] data) {
        assert (!!onRead);
        size_t data_read = 0;
        while (data_read < data.length) {
            if (buffer.length == 0) {
                buffer = onRead(real_buffer);
            }
            zs.next_in = buffer.ptr;
            zs.avail_in = buffer.length;
            zs.next_out = &data[data_read];
            zs.avail_out = data.length - data_read;
            int was_avail = zs.avail_out;
            int res = czlib.inflate(&zs, czlib.Z_NO_FLUSH);
            bool end = (res == czlib.Z_STREAM_END);
            if (!end) {
                zerror(res);
            }
            buffer = buffer[$ - zs.avail_in .. $];
            data_read += was_avail - zs.avail_out;
            if (end) {
                assert (zs.avail_in == 0);
                break;
            }
        }
        return data[0..data_read];
    }

    //read everything what was left in the buffer
    //if the zlib leaves data in the source buffer (same as when finish()
    //returns not 0), this is silently ignored
    //compressed_size is used to calculate the dest-buffer size, can be 0
    ubyte[] read_all(size_t compressed_size = 0) {
        return pipe.readAll(compressed_size*2);
    }

    //also frees any zlib stream state etc.
    //return how much of the buffer was unused, if any data was left!
    size_t finish() {
        assert (!!onRead);
        czlib.inflateEnd(&zs);
        onRead = null;
        delete real_buffer;
        real_buffer = null;
        if (close_fn) {
            close_fn();
            close_fn = null;
        }
        return buffer.length;
    }
    //blergh just for those 2 delegates
    void finish2() {
        finish();
    }

    PipeIn pipe() {
        return PipeIn(&read, &finish2);
    }
}


//replacement for Tango's tango.io.digest.Crc32
//the Tango one is just too slow
//should be source compatible for our uses

import tango.util.digest.Digest;

final class ZLibCrc32 : Digest {
    uint crc;

    this() {
        //reset
        crc32Digest();
    }
    override ZLibCrc32 update(void[] input) {
        crc = czlib.crc32(crc, cast(ubyte*)input.ptr, input.length);
        return this; //why, oh god why, Tango team?
    }
    override uint digestSize() {
        return 4;
    }
    override ubyte[] binaryDigest(ubyte[] buf = null) {
        //copy & pasted from Tango
        if (buf.length < 4)
            buf.length = 4;
        uint v = crc32Digest();
        buf[3] = cast(ubyte) (v >> 24);
        buf[2] = cast(ubyte) (v >> 16);
        buf[1] = cast(ubyte) (v >> 8);
        buf[0] = cast(ubyte) (v);
        return buf;
    }
    uint crc32Digest() {
        auto res = crc;
        crc = czlib.crc32(0, null, 0);
        return res;
    }
}
