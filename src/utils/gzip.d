module utils.gzip;

import utils.output;
import zlib = std.zlib;
import std.stream;

enum {
    MAX_WBITS = 15,  //from zconf.h
}

struct GZHdr {
    align(1):
    ubyte magic1 = 0x1f;
    ubyte magic2 = 0x8b;
    ubyte method = 8;     //deflate
    ubyte flags = 0;      //no extra fields after header
    uint unixTime = 0;    //timestamp unknown
    ubyte extraFlags = 0;
    ubyte os = 0xff;      //os unknown

    bool check() {
        //only deflate supported
        return (magic1 == 0x1f && magic2 == 0x8b && method == 8);
    }
}

///pack passed array with zlib and add gzip header and footer
ubyte[] gzipData(ubyte[] data) {
    ubyte[] ret = new ubyte[GZHdr.sizeof];
    //set default header
    *(cast(GZHdr*)ret.ptr) = GZHdr.init;

    uint crc = zlib.crc32(0, data);
    uint len = data.length;

    //xxx can't set window bits (stupid phobos)
    ubyte[] ndata = cast(ubyte[])zlib.compress(data, 9);
    //lolhack: remove zlib wrapper
    ret ~= ndata[2..$-4];

    //append crc and original length
    ubyte[4] tmp;
    *cast(uint*)tmp.ptr = crc; ret ~= tmp;
    *cast(uint*)tmp.ptr = len; ret ~= tmp;

    return ret;
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

import czlib = etc.c.zlib;

class GZWriter {
    private {
        void delegate(ubyte[] data) onWrite;
        ubyte[] buffer;
        size_t buffer_pos;
        czlib.z_stream zs;
    }

    this(void delegate(ubyte[] data) a_onWrite, int level = 9,
        size_t buffer_size = 64*1024)
    {
        assert (!!a_onWrite);
        assert (level >= 0 && level <= 9);
        assert (buffer_size > 0);
        onWrite = a_onWrite;
        buffer.length = buffer_size;
        buffer_pos = 0;
        //16: gzip header, 15: window bits
        //9: "memLevel=9 uses maximum memory for optimal speed."
        int res = czlib.deflateInit2(&zs, level, czlib.Z_DEFLATED, 16 + 15, 9,
            czlib.Z_DEFAULT_STRATEGY);
        zerror(res);
    }

    private void zerror(int err) {
        if (err == czlib.Z_OK)
            return; //error: no error.
        throw new zlib.ZlibException(err);
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

///try uncompressing passed array as gzip file
///returns orignal array if not compressed
///   Trows ZlibException if decompression failed although file was gzipped
ubyte[] tryUnGzip(ubyte[] cmpData) {
    if (cmpData.length < GZHdr.sizeof+8+1)
        //data is too short
        return cmpData;
    GZHdr* hdr = cast(GZHdr*)cmpData.ptr;
    if (!hdr.check())
        //header check failed, assume not compressed
        return cmpData;

    //-MAX_WBITS for no zlib header
    //Note: decompression may fail and will throw ZlibException
    //xxx original length unused
    ubyte[] decomp = cast(ubyte[])zlib.uncompress(
        cmpData[GZHdr.sizeof..$-8], 0, -MAX_WBITS);
    //xxx crc checking
    return decomp;
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
        int res = czlib.inflateInit2(&zs, 16 + 15);
        zerror(res);
    }

    private void zerror(int err) {
        if (err == czlib.Z_OK)
            return; //error: no error.
        throw new zlib.ZlibException(err);
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

    //also frees any zlib stream state etc.
    //return how much of the buffer was unused, if any data was left!
    size_t finish() {
        assert (!!onRead);
        czlib.inflateEnd(&zs);
        onRead = null;
        return buffer.length;
    }
}
