//according to WWP LZ77 compression.txt
//also see http://en.wikipedia.org/wiki/LZ77_and_LZ78

module wwpdata.decompression;

//decompressed_length must be >= length of the stream in data
ubyte[] decompress_wlz77(ubyte[] data, size_t decompressed_length) {
    size_t cur, dest = 0;
    ubyte[] res = new ubyte[decompressed_length];
    while (cur < data.length) {
        ubyte b = data[cur++];
        if (!(b & 0b1000_0000)) {
            //uncompressed
            res[dest++] = b;
        } else {
            uint count, offset;
            offset = b & 0b111;
            ubyte b2 = data[cur++];
            offset = (offset << 8) | b2;
            if (!(b & 0b0111_1000)) {
                if (!offset)
                    break;
                //long repeat
                count = data[cur++] + 18;
            } else {
                //short repeat
                offset += 1;
                count = ((b >> 3) & 0b1111) + 2;
            }
            //insert from stream... no block copy possible because this is
            //an LZ77 algorithm
            while (count--) {
                res[dest] = res[dest-offset];
                dest++;
            }
        }
    }
    return res[0 .. dest];
}
