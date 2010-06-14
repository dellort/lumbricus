module framework.imgwrite;

import framework.surface;
import utils.color;
import utils.gzip : GZWriter, ZLibCrc32;
import utils.misc;
import utils.rect2;
import utils.stream;
import net.marshal : Marshaller;

//import tango.io.digest.Crc32 : Crc32;

//fmt is one of the formats registered in gImageFormats
//NOTE: stream must be seekable (used to back-patch the length), but the
//      functions still start writing at the preset seek position, and end
//      writing at the end of the written image
void saveImage(Surface img, Stream stream, char[] fmt = "png") {
    if (fmt == "png") {
        writePNG(img, stream);
    } else {
        throwError("Writing image format not supported: {}", fmt);
    }
}

//libpng sucks, all is done manually
private void writePNG(Surface img, Stream stream) {
    auto chunk_crc = new ZLibCrc32(); //Crc32();
    bool chunk_writing;
    ulong chunk_start;

    void marshw_raw(ubyte[] data) {
        stream.writeExact(data);
    }
    void endChunk() {
        assert (chunk_writing);
        ulong end = stream.position;
        assert (end >= chunk_start + 8);
        stream.position = chunk_start;
        uint len = end - chunk_start - 8;
        Marshaller(&marshw_raw).write(len);
        stream.position = end;
        //NOTE: this call also resets the crc stored in the chunk_crc
        uint crc = chunk_crc.crc32Digest();
        Marshaller(&marshw_raw).write(crc);
        chunk_writing = false;
    }
    void chunkData(ubyte[] d) {
        assert (chunk_writing);
        chunk_crc.update(d);
        stream.writeExact(d);
    }
    void startChunk(char[] name) {
        if (chunk_writing)
            endChunk();
        assert(name.length == 4);
        chunk_writing = true;
        //length field will be patched in endChuck() to allow streaming
        chunk_start = stream.position;
        ubyte[4] len;
        stream.writeExact(len);
        //the chunk type... it's not really part of the chunk data, but is CRCed
        chunkData(cast(ubyte[])name);
    }
    void marshw(ubyte[] data) {
        chunkData(data);
    }

    static ubyte[] sig = [137, 80, 78, 71, 13, 10, 26, 10];
    stream.writeExact(sig);

    startChunk("IHDR");

    struct PNG_IHDR {
        uint width, height;
        ubyte depth = 8;
        ubyte colour_type;
        ubyte compression_method = 0;
        ubyte filter_method = 0;
        ubyte interlace_method = 0;
    }

    bool write_alpha = false;

    PNG_IHDR ihdr;
    ihdr.width = img.size.x;
    ihdr.height = img.size.y;

    switch (img.transparency) {
        case Transparency.None, Transparency.Colorkey:
            ihdr.colour_type = 2; //"Truecolour"
            break;
        case Transparency.Alpha:
            ihdr.colour_type = 6; //"Truecolour with alpha"
            write_alpha = true;
            break;
        default:
            throwError("writing png: unknown transparency type");
    }

    Marshaller(&marshw).write(ihdr);

    if (img.transparency == Transparency.Colorkey) {
        //tRNS chunk defines (in this case) the "transparent colour"

        struct PNG_tRNS {
            ushort r, g, b;
        }

        startChunk("tRNS");
        auto cc = img.colorkey().toRGBA32();
        Marshaller(&marshw).write(PNG_tRNS(cc.r, cc.g, cc.b));
    }

    //put in the image data
    startChunk("IDAT");
    void img_write(ubyte[] data) {
        chunkData(data);
    }
    GZWriter zwriter = new GZWriter(&img_write, false);

    void filterType() {
        ubyte filter_type = 0;
        zwriter.write((&filter_type)[0..1]);
    }

    Color.RGBA32* data;
    uint pitch;
    img.lockPixelsRGBA32(data, pitch);

    try {
        if (write_alpha) {
            //our format is compatible with PNG's, just dump the scanlines
            for (int y = 0; y < img.size.y; y++) {
                filterType();
                zwriter.write(cast(ubyte[])(data[0..img.size.x]));
                data += pitch;
            }
        } else {
            //write only 3 color components; have to convert scanlines
            bool conv_cc = img.transparency == Transparency.Colorkey;
            uint sx = img.size.x;
            Color.RGBA32[] cckey = conv_cc ? new Color.RGBA32[sx] : null;
            ubyte[] converted = new ubyte[sx*3];
            for (uint y = 0; y < img.size.y; y++) {
                filterType();
                Color.RGBA32* data2 = data;
                if (conv_cc) {
                    //replace transparent by colorkey
                    data2 = cckey.ptr;
                    blitWithColorkey(img.colorkey.toRGBA32,
                        data[0..sx], data2[0..sx]);
                }
                ubyte* pconv = converted.ptr;
                for (uint x = 0; x < sx; x++) {
                    pconv[0] = data2.r;
                    pconv[1] = data2.g;
                    pconv[2] = data2.b;
                    pconv += 3;
                    data2++;
                }
                zwriter.write(converted);
                data += pitch;
            }
            delete converted;
            delete cckey;
        }
    } finally {
        img.unlockPixels(Rect2i.init);
    }

    zwriter.finish();

    startChunk("IEND");
    endChunk();
}
