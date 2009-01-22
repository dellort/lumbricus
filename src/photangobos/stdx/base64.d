module stdx.base64;

/+

version (Tango) {
    public import tango.io.encode.Base64;

    uint encodeLength(uint s) {
        return allocateEncodeSize(s);
    }

    ubyte[] decode(char[] data) {
        return decode(data, null);
    }
} else {
    import pb = std.base64;

    //fix Phobos bugs, butr respect Tango bugs
    char[] encode(ubyte[] str, char[] buf) {
        return pb.encode(cast(char[])str, buf);
    }
    char[] encode(ubyte[] data) {
        return pb.encode(cast(char[])data);
    }

    ubyte[] decode(char[] data, ubyte[] buf) {
        return cast(ubyte[])pb.decode(data, cast(char[])buff);
    }
    ubyte[] decode(char[] data) {
        return cast(ubyte[])pb.decode(data);
    }

    alias pb.encodeLength encodeLength;
}

+/
