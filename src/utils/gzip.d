module utils.gzip;

import utils.output;
import stdx.stream;

version (Tango) {
    import czlib = tango.io.compress.c.zlib;
} else {
    import czlib = etc.c.zlib;
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
    ubyte[] res;
    void onwrite(ubyte[] wdata) {
        res ~= wdata;
    }
    auto writer = new GZWriter(&onwrite);
    writer.write(data);
    writer.finish();
    return res;
}

class GZStreamOutput : OutputHelper {
    private {
        Stream output_stream;
        GZWriter writer;
    }

    this(Stream s) {
        assert (!!s);
        output_stream = s;
        writer = new GZWriter(&doWrite);
    }

    void finish() {
        assert (!!output_stream);
        writer.finish();
        output_stream = null;
        writer = null;
    }

    private void doWrite(ubyte[] s) {
        output_stream.writeExact(s.ptr, s.length);
    }

    override void writeString(char[] str) {
        writer.write(cast(ubyte[])str);
    }
}

class GZWriter {
    private {
        void delegate(ubyte[] data) onWrite;
        ubyte[] buffer;
        size_t buffer_pos;
        czlib.z_stream zs;
    }

    this(void delegate(ubyte[] data) a_onWrite, bool use_gzip = true,
        int level = 9, size_t buffer_size = 64*1024)
    {
        assert (!!a_onWrite);
        assert (level >= 0 && level <= 9);
        assert (buffer_size > 0);
        onWrite = a_onWrite;
        buffer.length = buffer_size;
        buffer_pos = 0;
        //16: gzip header, 15: window bits
        //9: "memLevel=9 uses maximum memory for optimal speed."
        int res = czlib.deflateInit2(&zs, level, czlib.Z_DEFLATED,
            (use_gzip ? 16 : 0) + 15, 9, czlib.Z_DEFAULT_STRATEGY);
        zerror(res);
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
        buffer = null;
    }
}

//gzipData^-1
ubyte[] gunzipData(ubyte[] cmpData) {
    bool did_read;
    ubyte[] onread() {
        if (!did_read)
            return cmpData;
        return null;
    }
    auto reader = new GZReader(&onread);
    return reader.read_all(cmpData.length);
}

class GZReader {
    private {
        ubyte[] delegate() onRead;
        ubyte[] buffer;
        czlib.z_stream zs;
    }

    //onRead() can return as much data as it wants
    //if onRead() doesn't know where the zlib stream ends, it might return more
    //data than needed, which ends up unused. the return value of finish() can
    //be used to see how much data was unused.
    this(ubyte[] delegate() a_onRead) {
        assert (!!a_onRead);
        onRead = a_onRead;
        buffer = null;
        //32: gzip/zlib header, 15: window bits
        int res = czlib.inflateInit2(&zs, 32 + 15);
        zerror(res);
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
                buffer = onRead();
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
        ubyte[] dest;
        size_t pos = 0;
        dest.length = compressed_size * 2;
        for (;;) {
            auto res = read(dest[pos..$]);
            pos += res.length;
            if (res.length == 0) {
                finish();
                dest.length = pos;
                return dest;
            }
            //enlarge buffer
            dest.length = dest.length*2;
        }
    }

    //also frees any zlib stream state etc.
    //return how much of the buffer was unused, if any data was left!
    size_t finish() {
        assert (!!onRead);
        czlib.inflateEnd(&zs);
        onRead = null;
        return buffer.length;
    }
}
