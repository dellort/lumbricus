//This file is adapted from hybrid/BoxPacker.d, part of
//HybridGui by h3r3tic
//
//Web: http://code.google.com/p/h3r3tic/
//
//License: New BSD License
module utils.boxpacker;

import utils.vector2;

private {
    const float acceptableHeightRatio = 0.7f;
    const float heightExtraMult = 1.1f;

    static assert (1.f / heightExtraMult >= acceptableHeightRatio);
    static assert (heightExtraMult >= 1.f);


    int extendedHeight(int h) {
        if (0 == h) return 0;
        //(used to use std.math.rndtol() instead of the cast)
        int h2 = cast(int)(heightExtraMult * h);
        while (cast(float)h / h2 < acceptableHeightRatio) --h2;
        //writefln("making {} out of {}", h2, h);
        assert (h2 >= h);
        return h2;
    }
}


// TODO: garbage collection
class BoxPacker {
    Block* getBlock(Vector2i size) {
        //the extendedHeight thing is duplicated EVERYWHERE, blame h3
        auto esize = Vector2i(size.x, extendedHeight(size.y));
        if (esize.x > pageSize.x || esize.y > pageSize.y)
            return null;


        Block* res;

        float               bestRatio = 0.f;
        PackerLine* bestLine = null;

        // find the 'best' line
        foreach (inout page; pages) {
            foreach (inout line; page.lines) {
                if (line.size.y < size.y) continue;     // won't fit our request vertically ...
                if (line.size.x - line.xoffset < size.x) continue;      // ... horizontally

                float ratio = cast(float)size.y / line.size.y;
                if (ratio > bestRatio) {
                    // ok, this is better than our current 'best'.
                    bestRatio = ratio;
                    bestLine = &line;
                }
            }
        }

        if (bestLine !is null && bestRatio >= acceptableHeightRatio) {
            return bestLine.getBlock(size);
        } else {
            // we haven't found any line that would suit our needs, try to create a new one
            foreach (inout page; pages) {
                auto line = page.extendCache(Vector2i(size.x, extendedHeight(size.y)));
                if (line) return line.getBlock(size);
            }

            // there was not enough space in any page. we need a new cache.
            return extendCache(Vector2i(size.x, extendedHeight(size.y))).getBlock(size);
        }
    }


    PackerPage extendCache(Vector2i minSize) {
        //writefln(`BoxPacker: Creating a new cache page: {}`, pages.length);
        pages ~= new PackerPage(pageSizeContaining(minSize), cast(int)pages.length);
        return pages[$-1];
    }


    Vector2i pageSizeContaining(Vector2i minSize) {
        assert (minSize.x <= pageSize.x);
        assert (minSize.y <= pageSize.y);
        return pageSize;
    }


    Vector2i            pageSize = {x: 512, y: 512};
    PackerPage[]    pages;
}



class PackerPage {
    this (Vector2i size, int page) {
        this.size = size;
        this.page = page;
    }


    Block* getBlock(Vector2i size) {
        Block* res;

        foreach (inout line; lines) {
            if ((res = line.getBlock(size)) !is null) return res;
        }

        auto ext = extendCache(Vector2i(size.x, extendedHeight(size.y)));
        if (ext is null) return null;

        return ext.getBlock(size);
    }


    PackerLine* extendCache(Vector2i size) {
        if (this.size.y < size.y) return null;
        lines ~= PackerLine(Vector2i(0, this.size.y - size.y), Vector2i(this.size.x, size.y), page);
        this.size.y -= size.y;
        return &lines[$-1];
    }


    int             page;
    PackerLine[]    lines;
    Vector2i            size;
}



struct PackerLine {
    static PackerLine opCall(Vector2i origin, Vector2i size, int page) {
        PackerLine res;
        res.origin = origin;
        res.size = size;
        res.page = page;
        //debug Trace.formatln(`* creating a new cache line. origin: {}   size: {}   page: {}`, origin, size, page);
        return res;
    }


    Block* getBlock(Vector2i size) {
        if (this.size.x < size.x || this.size.y < size.y) return null;
        blocks ~= Block(this.origin + Vector2i(xoffset, 0), size, page);
        this.xoffset += size.x;
        return &blocks[$-1];
    }


    Vector2i    origin;
    Vector2i    size;
    int     xoffset;
    int     page;

    Block[] blocks;
}



struct Block {
    Vector2i    origin;
    Vector2i    size;
    int     page;

    static Block opCall(Vector2i origin, Vector2i size, int page) {
        Block res;
        res.origin = origin;
        res.size = size;
        res.page = page;
        return res;
    }
}
