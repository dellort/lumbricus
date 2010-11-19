//according to WWP LZ77 compression.txt
//also see http://en.wikipedia.org/wiki/LZ77_and_LZ78

module wwpdata.decompression;

import utils.misc;

//buffer.length must be >= length of the stream in data
//returns buffer[0..actuallydecompressed]
//xxx missing bounds checking in release mode (buffer overflows with bad data)
ubyte[] decompress_wlz77(ubyte[] data, ubyte[] buffer) {
    size_t cur, dest = 0;
    while (cur < data.length) {
        ubyte b = data[cur++];
        if (!(b & 0b1000_0000)) {
            //uncompressed
            buffer[dest++] = b;
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
                buffer[dest] = buffer[dest-offset];
                dest++;
            }
        }
    }
    return buffer[0 .. dest];
}
