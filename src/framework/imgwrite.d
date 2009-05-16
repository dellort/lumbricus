module framework.imgwrite;

import framework.framework;
import utils.misc;
import utils.gzip : GZWriter;
import net.marshal : Marshaller;

import tango.io.digest.Crc32 : Crc32;

import stdx.stream;

//COLLECTION OF HACKS LOL
static this() {
    gImageFormats["png"] = toDelegate(&writePNG);
    gImageFormats["tga"] = toDelegate(&writeTGA);
    gImageFormats["raw"] = toDelegate(&writeRAW);
}

//libpng sucks, all is done manually
private void writePNG(Surface img, Stream stream) {
    auto chunk_crc = new Crc32();
    bool chunk_writing;
    ulong chunk_start;

    void marshw_raw(ubyte[] data) {
        stream.writeExact(data.ptr, data.length);
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
    void chunkData(void* ptr, size_t s) {
        assert (chunk_writing);
        chunk_crc.update(ptr[0..s]);
        stream.writeExact(ptr, s);
    }
    void startChunk(char[] name) {
        if (chunk_writing)
            endChunk();
        assert(name.length == 4);
        chunk_writing = true;
        //length field will be patched in endChuck() to allow streaming
        chunk_start = stream.position;
        uint len;
        stream.write(len);
        //the chunk type... it's not really part of the chunk data, but is CRCed
        chunkData(name.ptr, name.length);
    }
    void marshw(ubyte[] data) {
        chunkData(data.ptr, data.length);
    }

    static ubyte[] sig = [137, 80, 78, 71, 13, 10, 26, 10];
    stream.writeExact(sig.ptr, sig.length);

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
        case Transparency.None:
            ihdr.colour_type = 2; //"Truecolour"
            break;
        case Transparency.Alpha, Transparency.Colorkey:
            ihdr.colour_type = 6; //"Truecolour with alpha"
            write_alpha = true;
            break;
        default:
            throw new Exception("writing png: unknown transparency type");
    }

    Marshaller(&marshw).write(ihdr);

/+  xxx removed for simplicity
    if (img.transparency == Transparency.Colorkey) {
        //tRNS chunk defines (in this case) the "transparent colour"

        struct PNG_tRNS {
            ushort r, g, b;
        }

        startChunk("tRNS");
        auto cc = img.colorkey().toRGBA32();
        Marshaller(&marshw).write(PNG_tRNS(cc.r, cc.g, cc.b));
    }
+/

    //put in the image data
    startChunk("IDAT");
    void img_write(ubyte[] data) {
        chunkData(data.ptr, data.length);
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
            uint sx = img.size.x;
            ubyte[] converted = new ubyte[sx*3];
            for (uint y = 0; y < img.size.y; y++) {
                filterType();
                Color.RGBA32* data2 = data;
                ubyte* pconv = &converted[0];
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
        }
    } finally {
        img.unlockPixels(Rect2i.init);
    }

    zwriter.finish();

    startChunk("IEND");
    endChunk();
}

//dirty hacky lib to dump a surface to a file
//as far as I've seen we're not linked to any library which can write images
private void writeTGA(Surface img, Stream stream) {
    scope to = new MemoryStream();
    try {
        Color.RGBA32* pvdata;
        uint pitch;
        img.lockPixelsRGBA32(pvdata, pitch);
        ubyte b;
        b = 0;
        to.write(b); //image id, whatever
        to.write(b); //no palette
        b = 2;
        to.write(b); //uncompressed 24 bit RGB
        short sh;
        sh = 0;
        to.write(sh); //skip plalette
        to.write(sh);
        b = 0;
        to.write(b);
        to.write(sh); //x/y coordinates
        to.write(sh);
        sh = img.size.x; to.write(sh); //w/h
        sh = img.size.y; to.write(sh);
        bool alpha = img.transparency == Transparency.Alpha;
        if (alpha)
            b = 32;
        else
            b = 24;
        to.write(b);
        b = 8;
        to.write(b); //??
        //dump picture data as 24 bbp, 32 bpp with alpha
        //TGA seems to be upside down
        for (int y = img.size.y-1; y >= 0; y--) {
            Color.RGBA32* data = pvdata+pitch*y;
            for (int x = 0; x < img.size.x; x++) {
                //wee, colorkeyed surfaces are written as not-transparent
                to.write(data.b);
                to.write(data.g);
                to.write(data.r);
                if (alpha) {
                    to.write(data.a);
                }
                data++;
            }
        }
    } finally {
        img.unlockPixels(Rect2i.init);
    }
    stream.copyFrom(to);
}

//memory dump of the Surface
//writes a x byte large header, then 4 bytes per pixel
private void writeRAW(Surface img, Stream stream) {
    try {
        Color.RGBA32* pvdata;
        uint pitch;
        img.lockPixelsRGBA32(pvdata, pitch);
        //header: x, y as uints
        stream.write(img.size.x);
        stream.write(img.size.y);
        //header: colorkey as r-g-b-a byte array
        auto ck = img.getColorkey().toRGBA32();
        stream.writeExact(&ck, ck.sizeof);
        //header: transparency mode as uint
        auto tr = cast(uint)img.transparency();
        //image data
        for (int y = 0; y < img.size.y; y++) {
            stream.writeExact(pvdata, 4*img.size.x);
            pvdata += pitch;
        }
    } finally {
        img.unlockPixels(Rect2i.init);
    }
}
