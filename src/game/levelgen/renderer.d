module game.levelgen.renderer;

//This module only renders auto-generated levels.
//It smoothes and draws the polygons generated by genrandom.d and also
//texturizes them.
//Also handles collision and in-game modification of the landscape.

import game.levelgen.landscape;
import framework.framework;
import utils.vector2;
import utils.time;
import utils.list2;
import utils.log;
import utils.misc;
import utils.array : BigArray;
import drawing = utils.drawing;
import math = tango.math.Math;
import digest = tango.io.digest.Digest;
import md5 = tango.io.digest.Md5;
import utils.reflection;

debug import utils.perf;

public alias Vector2f Point;

//don't know where to put this, moved it out of blastHole() because this thing
//affects the bitmap modification bounding box
const int cBlastBorder = 4;

class LandscapeBitmap {
    private int mWidth, mHeight;
    private Surface mImage;
    private Lexel[] mLevelData;
    private static LogStruct!("levelrenderer") mLog;

    static assert(Lexel.sizeof == 1);

    //blastHole: Distance from explosion outer circle to inner (free) circle
    private const int cBlastCenterDist = 25;

    private int[][] mCircles; //getCircle()

    //because I'm stupid, I'll store all points into a linked lists to be able
    //to do naive corner cutting by subdividing the curve recursively
    private struct Vertex {
        ObjListNode!(Vertex*) listnode;
        Point pt;
        bool no_subdivide = false;
    }
    private alias ObjectList!(Vertex*, "listnode") VertexList;

    private struct TexData {
        //also not good and nice
        uint pitch, w, h;
        Color.RGBA32* data;
        Vector2i offs;

        private Surface mSurface;

        static TexData opCall(Surface s, Vector2i offs,
            Color fallback = Color(0,0,0,0))
        {
            TexData ret;
            ret.mSurface = s;
            if (s !is null) {
                s.lockPixelsRGBA32(ret.data, ret.pitch);
                ret.w = s.size.x;
                ret.h = s.size.y;
            } else {
                //simulate an image consisting of a single transparent pixel
                Color.RGBA32* data = new Color.RGBA32;
                *data = fallback.toRGBA32();
                ret.data = data;
                ret.w = ret.h = 1;
                ret.pitch = 1;
            }
            ret.offs = offs;
            return ret;
        }

        void release() {
            if (mSurface !is null)
                mSurface.unlockPixels(Rect2i.init);
        }
    }


    //steps = number of subdivisions
    //start = start of the subdivision
    private static void cornercut(VertexList verts, int steps, float start) {
        for (int i = 0; i < 5; i++) {
            if (!verts.hasAtLeast(3))
                return;
            Vertex* cur = verts.head;
            Point pt = cur.pt;
            do {
                Vertex* next = verts.ring_next(cur);
                Vertex* overnext = verts.ring_next(next);
                if (!cur.no_subdivide && !next.no_subdivide) {
                    Vertex* newv = new Vertex();
                    verts.insert_after(newv, cur);
                    Point p2 = next.pt, p3 = overnext.pt;
                    newv.pt = pt + (p2-pt)*(1.0f - start);
                    pt = p2;
                    p2 = p2 + (p3-p2)*start;
                    next.pt = p2;
                } else {
                    pt = next.pt;
                }
                cur = next;
            } while (cur !is verts.head);
        }
    }

    //draw a polygon; it's closed by the line points[$-1] - points[0]
    //"marker" is the value that should be written into the Level.mData array,
    //if a pixel is coverered by this polygon
    //subdiv: if subdivision should be done
    //"visible" is true if the polygon should appear in the image surface
    //nosubdiv: indices for points that start lines which shouldn't be
    //  "interpolated" (they won't be changed)
    //"texture" is used to fill the new polygon, if it is null, make all pixels
    //  covered by the polygon transparent
    //historical note: points was changed from Vector2f
    public void addPolygon(Vector2i[] points, bool visible,
        Vector2i texture_offset, Surface texture, Lexel marker,
        bool subdiv, uint[] nosubdiv, int subdivSteps, float subdivStart)
    {
        if (!visible)
            return;
        //if no image available, just set the mLevelData[]
        bool textured = !!mImage;

        VertexList vertices = new VertexList();

        uint curindex = 0;
        foreach(Vector2i p; points) {
            Vertex* v = new Vertex();
            v.pt = toVector2f(p);
            //obviously, nosubdiv should be small
            foreach(uint index; nosubdiv) {
                if (index == curindex)
                    v.no_subdivide = true;
            }
            vertices.insert_tail(v);
            curindex++;
        }

        if (subdiv) {
            debug {
                auto counter = new PerfTimer(true);
                counter.start();
            }

            cornercut(vertices, subdivSteps, subdivStart);

            debug {
                counter.stop();
                mLog("render.d: cornercut in {}", counter.time);
            }
        }

        Point[] urgs;
        urgs.length = vertices.count;
        int n;
        foreach(Vertex* v; vertices) {
            urgs[n++] = v.pt;
        }

        Color.RGBA32* dstptr; uint dstpitch;
        TexData tex;

        if (textured) {
            tex = TexData(texture, texture_offset);

            mImage.lockPixelsRGBA32(dstptr, dstpitch);
        }

        void drawScanline(int x1, int x2, int y) {
            assert(x1 <= x2);
            assert(y >= 0 && y < mHeight);
            //clipping (maybe rasterizePolygon should do that)
            if (x2 < 0 || x1 >= mWidth)
                return;
            if (x1 < 0)
                x1 = 0;
            if (x2 > mWidth)
                x2 = mWidth;
            if (visible && textured) {
                uint ty = (y + tex.offs.y) % tex.h;
                Color.RGBA32* dst = dstptr +  y*dstpitch + x1;
                Color.RGBA32* texptr = tex.data + ty*tex.pitch;
                for (uint x = x1; x < x2; x++) {
                    auto texel = texptr + (x + tex.offs.x) % tex.w;
                    *dst = *texel;
                    dst++;
                }
            }
            int ly = y*mWidth;
            mLevelData[ly+x1..ly+x2] = marker;
        }

        debug {
            auto counter = new PerfTimer(true);
            counter.start();
        }

        drawing.rasterizePolygon(mWidth, mHeight, urgs, false, &drawScanline);

        debug {
            counter.stop();
            mLog("render.d: polygon rendered in {}", counter.time);
        }

        if (textured) {
            mImage.unlockPixels(Rect2i(Vector2i(0), mImage.size));
            tex.release();
        }

        delete urgs;
        foreach (Vertex* v; vertices) {
            vertices.remove(v);
            delete v;
        }
    }

    //create a level image from the Lexel[] by applying textures
    //overrides image if already created
    //arrays are indexed by Lexel
    void texturizeData(Surface[] textures, Vector2i[] texOffsets) {
        //prepare image
        if (!mImage) {
            //xxx colorkey
            mImage = gFramework.createSurface(size, Transparency.Colorkey);
        }
        assert(mLevelData.length == mImage.size.x*mImage.size.y);

        //prepare textures (one for each marker)
        TexData[Lexel.Max+1] texData;
        for (int idx = 0; idx <= Lexel.Max; idx++) {
            Surface t;
            if (idx < textures.length)
                t = textures[idx];
            if (idx < texOffsets.length)
                texData[idx] = TexData(t, texOffsets[idx]);
            else
                //no texOffset was given for this index
                texData[idx] = TexData(t, Vector2i(0));
        }

        Color.RGBA32* dstptr; uint dstpitch;
        mImage.lockPixelsRGBA32(dstptr, dstpitch);

        Color.RGBA32*[Lexel.Max+1] texptr;

        for (int y = 0; y < size.y; y++) {
            //for each texture, get pointer to current texture line
            for (int i = 0; i < texptr.length; i++) {
                int ty = (y + texData[i].offs.y) % texData[i].h;
                texptr[i] = texData[i].data + ty*texData[i].pitch;
            }
            //current line in data array
            Lexel* src = mLevelData.ptr + y*size.x;
            //destination pixel
            Color.RGBA32* dst = dstptr +  y*dstpitch;
            for (int x = 0; x < size.x; x++) {
                Lexel l = *src;
                if (l >= texData.length)
                    l = Lexel.init;
                Color.RGBA32* texel = texptr[l]
                    + (x + texData[l].offs.x) % texData[l].w;
                *dst = *texel;
                dst++;
                src++;
            }
        }

        mImage.unlockPixels(Rect2i(Vector2i(0), mImage.size));
        foreach (ref TexData t; texData) {
            t.release();
        }
    }

    //it's a strange design decision to do it _that_ way. sorry for that.
    //draw a border in "a", using that texture, where "a" forms a border to "b"
    //draws top and bottom borders with different textures (if do_xx is set,
    //tex_xx must be valid)
    //  "do_up":   draw bottom border with texture "tex_up"
    //  "do_down": draw top border with texture "tex_down"
    public void drawBorder(Lexel a, Lexel b, bool do_up, bool do_down,
        Surface tex_up, Surface tex_down)
    {
        assert(!!mImage, "No border drawing for data-only renderer");
        ubyte[] apline;

        //it always scans in the given direction; to draw both borders where "a"
        //is on top ob "b" and where "b" is on top of "a", you have to call this
        //twice (which isn't a problem, since you might want to use different
        //textures for this)
        //"up": false=scan up-to-down, true=scan down-to-up ("a" und "b" are
        // also checked in that order)
        //"texture" must not be null
        void drawBorderInt(Lexel a, Lexel b, bool up, Surface texture,
            ubyte[] tmpData)
        {
            int dir = up ? -1 : +1;

            uint tex_pitch;
            Color.RGBA32* texptr;
            texture.lockPixelsRGBA32(texptr, tex_pitch);
            uint tex_w = texture.size.x;
            uint tex_h = texture.size.y;

            auto dsttransparent = Color.Transparent.toRGBA32();

            Color.RGBA32* dstptr; uint dstpitch;
            mImage.lockPixelsRGBA32(dstptr, dstpitch);

            apline[] = 0; //initialize to 0
            int start = up ? mHeight-1 : 0;
            for (int y = start; y >= 0 && y <= mHeight-1; y += dir) {
                Color.RGBA32* scanline = dstptr + y*dstpitch;
                Lexel* meta_scanline = &mLevelData[y*mWidth];
                ubyte* poldline = &tmpData[y*mWidth];
                ubyte* ppline = &apline[0];
                for (int x = 0; x < mWidth; x++) {
                    //the data written into ppline is used by the next pass in
                    //the other direction
                    ubyte pline = *ppline;

                    if (*meta_scanline == a) {
                        if (pline == 0xFF)
                            pline = tex_h+1;
                        if (pline > 0)
                            pline -= 1;
                    } else if (*meta_scanline == b) {
                        pline = 0xFF;
                    } else {
                        pline = 0;
                    }

                    *ppline = pline;

                    //set the pixel accordingly
                    //comparison with *oldpline ensures that up and down texture
                    //use the same part of the available space
                    if (pline > 0 && pline < 0xFF && pline > *poldline) {
                        Color.RGBA32* texel = texptr + x%tex_w;
                        uint texy = (tex_h-pline)%tex_h;
                        texel = texel + texy*tex_pitch;
                        if (!texture.isTransparent(texel))
                            *scanline = *texel;
                        else {
                            //XXX assumption: parts of the texture that should
                            //render transparent only take half of the y space
                            if (texy < tex_h/2) {
                                //set current pixel transparent
                                *scanline = dsttransparent;
                                *meta_scanline = Lexel.Null;
                            }
                        }
                    }

                    scanline++;
                    meta_scanline++;
                    ppline++;
                    poldline++;
                }
                //save current pline for next pass in other direction
                tmpData[y*mWidth..(y+1)*mWidth] = apline;
            }

            mImage.unlockPixels(Rect2i(Vector2i(0), mImage.size));
            texture.unlockPixels(Rect2i.init);
        }

        debug {
            auto counter = new PerfTimer(true);
            counter.start();
        }

        //stores temporary data between up and down pass
        scope tmp_array = new BigArray!(ubyte)(mWidth*mHeight);
        ubyte[] tmp = tmp_array[];

        scope apline_array = new BigArray!(ubyte)(mWidth);
        apline = apline_array[];

        if (do_down)
            drawBorderInt(a, b, false, tex_down, tmp);
        if (do_up)
            drawBorderInt(a, b, true, tex_up, tmp);

        debug {
            counter.stop();
            mLog("render.d: border drawn in {}", counter.time());
        }
    }

    //render a circle on the surface
    // w, h: source bitmap width and height
    // meta_mask, meta_cmp: actually copy pixel if (meta & mask) == cmp
    // meta_domask: after checking and copying the pixel, mask meta with this
    //I put it all into this to avoid code duplication
    //called in-game!
    private int circle_masked(Vector2i pos, int radius, Color.RGBA32* dst,
        uint dst_pitch, Color.RGBA32* src, uint src_pitch, uint w, uint h,
        ubyte meta_mask, ubyte meta_cmp, ubyte meta_domask = 255)
    {
        assert(radius >= 0);
        auto st = pos;
        int[] circle = getCircle(radius);
        int count;

        for (int y = -radius; y <= radius; y++) {
            int ly = st.y + y;
            if (ly < 0 || ly >= mHeight)
                continue;
            int xoffs = radius - circle[y+radius];
            int x1 = st.x - xoffs;
            int x2 = st.x + xoffs + 1;
            //clipping
            x1 = x1 < 0 ? 0 : x1;
            x1 = x1 > mWidth ? mWidth : x1;
            x2 = x2 < 0 ? 0 : x2;
            x2 = x2 > mWidth ? mWidth : x2;
            Color.RGBA32* dstptr = dst+dst_pitch*ly;
            Color.RGBA32* srcptr = src+src_pitch*(ly % h);
            dstptr += x1;
            Lexel* meta = mLevelData.ptr + mWidth*ly + x1;
            for (int x = x1; x < x2; x++) {
                bool set = ((*meta & meta_mask) == meta_cmp);
                /+bool set = ((((*meta & Lexel.SolidSoft) == 0) ^ paintOnSolid)
                    & !(*meta & Lexel.SolidHard));+/
                /+ same code without if, hehe
                uint mask = cast(uint)set - 1;
                uint rcolor = *(srcptr+(x & swl));
                *dstptr = (*dstptr & mask) | (rcolor & ~mask);
                +/
                if (set) {
                    *dstptr = *(srcptr+(x % w));
                    count++;
                }
                //yes, unconditionally
                *meta &= meta_domask;
                dstptr++;
                meta++;
            }
        }
        return count;
    }

    //destroy a part of the landscape
    //called in-game!
    //  pos = center of the damage
    //  radius = radius of the circle around pos making up the now free area
    //  blast_border = added to radius for the area of the solid but modified
    //     area (on the border, the image is changed, but not the metadata) is
    //     pixels outside the circle (radius+blast_border) aren't touched)
    //  theme = bitmaps to use as background etc. (can be null)
    public int blastHole(Vector2i pos, int radius, int blast_border,
        LandscapeTheme theme = null)
    {
        assert(!!mImage, "Not for data-only renderer");
        const ubyte cAllMeta = Lexel.SolidSoft | Lexel.SolidHard;

        assert(radius >= 0);
        assert(blast_border >= 0);

        uint col;
        int count;

        Color.RGBA32* pixels; uint pitch;
        mImage.lockPixelsRGBA32(pixels, pitch);

        auto nradius = max(radius - cBlastCenterDist,0);

        //call circle_masked(), with either the Surface s or the Color c
        //if s !is null, only the surface is used, else use the color
        int doCircle(int radius, Surface s, Color c, ubyte meta_mask,
            ubyte meta_cmp, ubyte meta_domask = 255)
        {
            Color.RGBA32* srcpixels; uint srcpitch;
            int sx, sy;
            int count;
            if (s) {
                s.lockPixelsRGBA32(srcpixels, srcpitch);
                sx = s.size.x; sy = s.size.y;
            } else {
                //plain evil etc.: simulate a 1x1 bitmap with the color in it
                Color.RGBA32 col = c.toRGBA32();
                srcpixels = &col;
                srcpitch = 1;
                sx = 1; sy = 1;
            }
            count = circle_masked(pos, radius, pixels, pitch, srcpixels,
                srcpitch, sx, sy, meta_mask, meta_cmp, meta_domask);
            if (s) {
                s.unlockPixels(Rect2i.init);
            }
            return count;
        }

        //draw the background image into the area to be destroyed
        //actually, you can only see a ring of that background image; the center
        //of the destruction is free landscape (except for SolidHard pixels)
        //the center is cleared later to achieve this
        //in the same call, mask all pixels with SolidHard to remove any
        //SolidSoft pixels...
        count = doCircle(radius, theme ? theme.backImage : null,
            theme ? theme.backColor : Color.Transparent,
            cAllMeta, Lexel.SolidSoft, Lexel.SolidHard);

        int blast_radius = radius + blast_border;

        //draw that funny border; the border is still solid and also is drawn on
        //solid ground only (except for SolidHard pxiels: they stay unchanged)
        //because all SolidSoft pixels were cleared above, only the remaining
        //landscape around the destruction will be coloured with this border...
        if (theme) {
            doCircle(blast_radius, theme.borderImage, theme.borderColor,
                cAllMeta, Lexel.SolidSoft);
        }

        if (nradius > 0) {
            //clear the center of the destruction (to get rid of that background
            //texture)
            doCircle(nradius, null, Color.Transparent, cAllMeta, 0);
        }

        Rect2i bb;
        bb.p1 = pos - Vector2i(blast_radius);
        bb.p2 = pos + Vector2i(blast_radius);
        mImage.unlockPixels(bb);

        return count;
    }

    //calculate normal at that position
    //this is (very?) expensive
    //maybe replace it by other methods as used by other worms clones
    // circle = if true check a circle, else a quad, with sides (radius*2+1)^2
    // dir = not-notmalized diection which points to the outside of the level
    // count = number of colliding pixels
    // bits = lexel bits of all collided landscape pixels or'ed together
    public void checkAt(Vector2i pos, int radius, bool circle,
        out Vector2i out_dir, out int out_count, out uint out_bits)
    {
        assert(radius >= 0);
        //xxx: I "optimized" this, the old version is still in r451
        //     further "optimized" (== obfuscated for no gain) after r635

        auto st = pos;
        int[] acircle = circle ? getCircle(radius) : null;
        int count;
        uint bits;
        int d_x, d_y;

        //dir and count are initialized with 0

        int ly1 = max(st.y - radius, 0);
        int ly2 = min(st.y + radius + 1, mHeight);
        for (int y = ly1; y < ly2; y++) {
            int xoffs = radius;
            if (circle) {
                xoffs -= acircle[y-st.y+radius];
            }
            int lx1 = max(st.x - xoffs, 0);
            int lx2 = min(st.x + xoffs + 1, mWidth);
            if (!(lx1 < lx2))
                continue;
            int pl = y*mWidth + lx1;
            Lexel* data = &mLevelData[pl];
            int o_y = y - pos.y;
            for (int x = lx1; x < lx2; x++) {
                auto d = *data;
                if (d != 0) {
                    bits |= d;
                    d_x += x - pos.x;
                    d_y += o_y;
                    count++;
                }
                data++;
            }
        }

        out_dir = -Vector2i(d_x, d_y);
        out_count = count;
        out_bits = bits;
    }

    /*
     * Return an array, which contains in for each Y-value the X-value of the
     * first point of a filled circle... The Y-value is the index into the
     * array.
     * The circle has the diameter 1+radius*2
     * No real reason for that, but the code above becomes simpler if circle is
     * precalculated (and it also becomes slower...).
     */
    private int[] getCircle(int radius) {
        assert(radius >= 0);

        if (radius >= mCircles.length) {
            //xxx clamp to a maximum for more robustness
            mCircles.length = radius+1;
        }

        auto c = mCircles[radius];
        if (c.length)
            return c;

        int[] stuff = new int[radius*2+1];
        drawing.circle(radius, radius, radius,
            (int x1, int x2, int y) {
                stuff[y] = x1;
            });
        mCircles[radius] = stuff;
        return stuff;
    }

    //oh yeah, manual bitmap drawing code!
    private void doDrawBmp(int px, int py, Surface source, int w, int h,
        ubyte meta_mask, ubyte meta_cmp, Lexel after)
    {
        //clip
        w = min(w, source.size.x);
        h = min(h, source.size.y);
        int cx1 = max(px, 0);
        int cy1 = max(py, 0);
        int cx2 = min(mWidth, px+w);  //exclusive
        int cy2 = min(mHeight, py+h);
        assert(cx2-cx1 <= w);
        assert(cy2-cy1 <= h);
        if (cx1 >= cx2 || cy1 >= cy2)
            return;

        Color.RGBA32* data; uint pitch;
        source.lockPixelsRGBA32(data, pitch);
        Color.RGBA32* dstptr; uint dstpitch;
        mImage.lockPixelsRGBA32(dstptr, dstpitch);

        for (int y = cy1; y < cy2; y++) {
            //offset to relevant start of source scanline
            Color.RGBA32* src = data + pitch*(y-py) + (cx1-px);
            Color.RGBA32* dst = dstptr + dstpitch*y + cx1;
            Lexel* dst_meta = &mLevelData[mWidth*y+cx1];
            for (int x = cx1; x < cx2; x++) {
                if (!source.isTransparent(src)
                    && ((*dst_meta & meta_mask) == meta_cmp))
                {
                    *dst_meta = after;
                    //actually copy pixel
                    *dst = *src;
                }
                src++; dst++; dst_meta++;
            }
        }

        mImage.unlockPixels(Rect2i(cx1, cy1, cx2, cy2));
        source.unlockPixels(Rect2i.init);
    }

    //draw a bitmap, but also modify the level pixels
    //where (metadata & meta_mask) == meta_cmp, copy a pixel and set
    //pixel-metadata to "after"
    public void drawBitmap(Vector2i p, Surface source, Vector2i size,
        ubyte meta_mask, ubyte meta_cmp, Lexel after)
    {
        assert(!!mImage, "Not for data-only renderer");
        //ewww what has this become
        doDrawBmp(p.x, p.y, source, size.x, size.y, meta_mask, meta_cmp, after);
    }

    /+
    untested... unneeded?
    //same as above, but only draw a sub region of the source bitmap
    // p == uper right corner in destination
    // sp == upper right corner in source bitmap
    public void drawBitmap(Vector2i p, Surface source, Vector2i sp,
        Vector2i size, Lexel before, Lexel after)
    {
        assert(!!mImage, "Not for data-only renderer");
        size.x = min(size.x + sp.x, source.size.x) - sp.x;
        size.y = min(size.y + sp.y, source.size.y) - sp.y;
        void* data, uint pitch;
        source.lockPixelsRGBA32(data, pitch);
        //xxx: hm, more clipping to make it robust?
        void* ndata = data + sp.y*pitch + sp.x*uint.sizeof;
        doDrawBmp(p.x, p.y, ndata, pitch, size.x, size.y, before, after);
        source.unlockPixels();
    }
    +/

    //under no cirumstances change pixelformat or size of this
    public Surface image() {
        return mImage;
    }

    LandscapeBitmap copy(bool dataOnly = false) {
        if (!mImage || dataOnly)
            return new LandscapeBitmap(size, true, mLevelData.dup);
        else
            return new LandscapeBitmap(mImage, mLevelData);
    }

    //create a new Landscape which contains a copy of a subrectangle of this
    LandscapeBitmap cutOutRect(Rect2i rc) {
        rc.fitInsideB(Rect2i(mImage.size()));
        //copy out the subrect from the metadata
        if (!rc.isNormal())
            return null; //negative sizes duh
        Lexel[] ndata;
        ndata.length = rc.size.x * rc.size.y;
        uint sx = rc.size.x;
        int o1 = 0;
        int o2 = rc.p1.y*mWidth + rc.p1.x;
        for (int y = 0; y < rc.size.y; y++) {
            ndata[o1 .. o1 + sx] = mLevelData[o2 .. o2 + sx];
            o1 += sx;
            o2 += mWidth;
        }
        return new LandscapeBitmap(mImage.subrect(rc), ndata, false);
    }

    this(ReflectCtor c) {
    }

    //create an empty Landscape of passed size
    //  dataOnly: false will also generate a textured Landscape bitmap,
    //            true only creates a Lexel[] (this.image will return null)
    //  data: set to copy Lexel data, null to start empty
    public this(Vector2i size, bool dataOnly = false, Lexel[] data = null) {
        mWidth = size.x;
        mHeight = size.y;
        if (data.length > 0)
            mLevelData = data;
        else
            mLevelData.length = mWidth*mHeight;
        assert(mLevelData.length == mWidth*mHeight);

        if (!dataOnly) {
            mImage = gFramework.createSurface(size, Transparency.Colorkey);
            mImage.fill(Rect2i(mImage.size), Color.Transparent);
        }
    }

    //copy the level bitmap and per-pixel-metadata
    //make sure Surface size and data size match
    public this(Surface bmp, Lexel[] a_data, bool copy = true) {
        this(bmp.size, true, a_data.dup);
        mImage = copy ? bmp.clone() : bmp;
    }

    //create from a bitmap; also used as common constructor
    //bmp = the landscape-bitmap, must not be null
    //import_bmp = create the metadata from the image's transparency information
    //      if false, initialize metadata with Lexel.init
    //memory managment: you shall not touch the Surface instance in bmp anymore
    public this(Surface bmp, bool import_bmp = true) {
        this(bmp.size, true);
        mImage = bmp;

        //create mask

        if (!import_bmp)
            return;

        Color.RGBA32* ptr; uint pitch;
        mImage.lockPixelsRGBA32(ptr, pitch);

        for (int y = 0; y < mHeight; y++) {
            Color.RGBA32* pixel = ptr + y*pitch;
            Lexel* meta = &mLevelData[y*mWidth];
            for (int x = 0; x < mWidth; x++) {
                *meta = mImage.isTransparent(pixel) ? Lexel.SolidSoft
                    : Lexel.Null;
                meta++;
                pixel++;
            }
        }

        mImage.unlockPixels(Rect2i.init);
    }

    public void free() {
        assert(!!mImage, "Not for data-only renderer");
        mImage.free();
        delete mLevelData;
    }

    public Surface releaseImage() {
        assert(!!mImage, "Not for data-only renderer");
        auto img = mImage;
        mImage = null;
        return img;
    }

    public Vector2i size() {
        return Vector2i(mWidth, mHeight);
    }

    public Lexel[] levelData() {
        return mLevelData;
    }

    //copy everything from "from" to this
    //sizes of the landscape must match
    public void copyFrom(LandscapeBitmap from) {
        assert(size == from.size);
        mLevelData[] = from.levelData();
        //xxx transparency mode and colorkey??? (that damn crap!)
        mImage.copyFrom(from.image, Vector2i(0), Vector2i(0), size);
    }

    //the checksum includes the image and the data
    //xxx evil bug: the SDL renderer sets transparent pixels to colorkey, which
    //              changes the checksum... (damn colorkey crap artrgghgfgd!!1)
    char[] checksum() {
        digest.Digest hash = new md5.Md5();

        hash.update(cast(void[])mLevelData);

        Color.RGBA32* ptr; uint pitch;
        mImage.lockPixelsRGBA32(ptr, pitch);
        for (int y = 0; y < mImage.size.y; y++) {
            Color.RGBA32* pixel = ptr + y*pitch;
            hash.update(cast(void[])(pixel[0..mImage.size.x]));
        }
        mImage.unlockPixels(Rect2i.init);

        return hash.hexDigest();
    }
}


