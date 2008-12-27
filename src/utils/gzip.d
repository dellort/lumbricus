module utils.gzip;

import zlib = std.zlib;

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

import std.stdio;

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
