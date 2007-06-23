module levelgen.renderer;

//This module only renders auto-generated levels.
//It smoothes and draws the polygons generated by genrandom.d and also
//texturizes them.

import levelgen.level;
import framework.framework;
import utils.vector2;
import utils.time;
import utils.mylist;
import utils.log;
import utils.misc;
import drawing = utils.drawing;
import math = std.math;

import std.stdio;

debug import std.perf;

public alias Vector2f Point;

package class LevelBitmap {
    private uint mWidth, mHeight;
    private Surface mImage;
    private Surface mBackImage;
    private Lexel[] mLevelData;
    private Color mBorderColor;
    private Log mLog;

    private int[][int] mCircles; //getCircle()

    //because I'm stupid, I'll store all points into a linked lists to be able
    //to do naive corner cutting by subdividing the curve recursively
    private struct Vertex {
        Point pt;
        bool no_subdivide = false;
        mixin ListNodeMixin;
    }
    private alias List!(Vertex*) VertexList;

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
    //"visible" is true if the polygon should appear in the image surface, and
    //"color" is the color of the drawed filled polygon (alpha value ignored)
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

        VertexList vertices = new VertexList(Vertex.getListNodeOffset());

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
            cornercut(vertices, subdivSteps, subdivStart);
        }

        Point[] urgs;
        urgs.length = vertices.count;
        urgs.length = 0;
        foreach(Vertex* v; vertices) {
            urgs ~= v.pt;
        }

        delete vertices;

        //also not good and nice
        uint tex_pitch, tex_w, tex_h;
        void* tex_data;
        uint plain_evil;

        if (texture !is null) {
            texture.lockPixelsRGBA32(tex_data, tex_pitch);
            tex_w = texture.size.x;
            tex_h = texture.size.y;
        } else {
            //simulate an image consisting of a single transparent pixel
            plain_evil = colorToRGBA32(mImage.colorkey);
            tex_data = &plain_evil;
            tex_w = tex_h = 1;
            tex_pitch = 4;
        }

        int tex_offset_x = texture_offset.x;
        int tex_offset_y = texture_offset.y;

        void* dstptr; uint dstpitch;
        mImage.lockPixelsRGBA32(dstptr, dstpitch);

        void drawScanline(int y, int x1, int x2) {
            assert(x1 <= x2);
            assert(y >= 0 && y < mHeight);
            //clipping (maybe rasterizePolygon should do that)
            if (x2 < 0 || x1 >= mWidth)
                return;
            if (x1 < 0)
                x1 = 0;
            if (x2 > mWidth)
                x2 = mWidth;
            uint ty = (y + tex_offset_y) % tex_h;
            uint* dst = cast(uint*)(dstptr +  y*dstpitch + x1*uint.sizeof);
            uint* texptr = cast(uint*)(tex_data + ty*tex_pitch);
            Lexel* markerptr = &mLevelData[y*mWidth+x1];
            for (uint x = x1; x < x2; x++) {
                if (visible) {
                    uint* texel = texptr + (x + tex_offset_x) % tex_w;
                    *dst = *texel;
                }

                *markerptr = marker;

                dst++;
                markerptr++;
            }
        }

        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }

        rasterizePolygon(mWidth, mHeight, urgs, false, &drawScanline);

        debug {
            counter.stop();
            mLog("render.d: polygon rendered in %s",
                timeMusecs(cast(int)counter.microseconds));
        }

        mImage.unlockPixels();
        if (texture !is null) {
            texture.unlockPixels();
        }
    }

    //for RGBA32 format, check if pixel is considered to be transparent
    //hopefully inlined
    private bool is_not_transparent(uint c) {
        return !!(c & 0xff000000);
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
            void* tex_data;
            texture.lockPixelsRGBA32(tex_data, tex_pitch);
            uint tex_w = texture.size.x;
            uint tex_h = texture.size.y;
            uint* texptr = cast(uint*)tex_data;

            uint dsttransparent = colorToRGBA32(mImage.colorkey);

            void* dstptr; uint dstpitch;
            mImage.lockPixelsRGBA32(dstptr, dstpitch);

            //the algorithm was more or less ripped from Matthias' code
            ubyte[] pline = new ubyte[mWidth]; //initialized to 0
            int start = up ? mHeight-1 : 0;
            for (int y = start; y >= 0 && y <= mHeight-1; y += dir) {
                uint* scanline = cast(uint*)(dstptr + y*dstpitch);
                for (int x = 0; x < mWidth; x++) {
                    int cur = y*mWidth+x;

                    if (mLevelData[cur] == a) {
                        if (pline[x] == 0xFF)
                            pline[x] = tex_h+1;
                        if (pline[x] > 0)
                            pline[x] -= 1;
                    } else if (mLevelData[cur] == b) {
                        pline[x] = 0xFF;
                    } else {
                        pline[x] = 0;
                    }

                    //set the pixel accordingly
                    //comparison with tmpData ensures that up and down texture
                    //use the same part of the available space
                    if (pline[x] > 0 && pline[x] < 0xFF &&
                        pline[x] > tmpData[y*mWidth+x])
                    {
                        uint* texel = texptr + x%tex_w;
                        uint texy = (tex_h-pline[x])%tex_h;
                        texel = cast(uint*)(cast(void*)texel + texy*tex_pitch);
                        if (is_not_transparent(*texel))
                            *scanline = *texel;
                        else {
                            //XXX assumption: parts of the texture that should
                            //render transparent only take half of the y space
                            if (texy < tex_h/2) {
                                //set current pixel transparent
                                *scanline = dsttransparent;
                                mLevelData[cur] = Lexel.Null;
                            }
                        }
                    }

                    scanline++;
                }
                //save current pline for next pass in other direction
                tmpData[y*mWidth..(y+1)*mWidth] = pline;
            }

            mImage.unlockPixels();
            texture.unlockPixels();
        }

        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }

        //stores temporary data between up and down pass
        ubyte[] tmp = new ubyte[mWidth*mHeight];

        if (do_down)
            drawBorderInt(a, b, false, tex_down, tmp);
        if (do_up)
            drawBorderInt(a, b, true, tex_up, tmp);

        delete tmp;

        debug {
            counter.stop();
            mLog("render.d: border drawn in %s",
                timeMusecs(cast(int)counter.microseconds));
        }
    }

    //render a circle on the surface
    // w, h: source bitmap width and height
    // meta_mask, meta_cmp: actually copy pixel if (meta & mask) == cmp
    // meta_domask: after checking and copying the pixel, mask meta with this
    //I put it all into this to avoid code duplication
    //called in-game!
    private void circle_masked(Vector2i pos, int radius, void* dst,
        uint dst_pitch, void* src, uint src_pitch, uint w, uint h,
        ubyte meta_mask, ubyte meta_cmp, ubyte meta_domask = 255)
    {
        assert(radius >= 0);
        auto st = pos;
        int[] circle = getCircle(radius);

        //regarding clipping: could write a clipping- and a non-clipping version
        //(but is it worth? it already copies scanlines without needing clipping)

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
            uint* dstptr = cast(uint*)(dst+dst_pitch*ly);
            uint* srcptr = cast(uint*)(src+src_pitch*(ly % h));
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
                }
                //yes, unconditionally
                *meta &= meta_domask;
                dstptr++;
                meta++;
            }
        }
    }

    //destroy a part of the landscape
    //called in-game!
    public void blastHole(Vector2i pos, int radius) {
        const ubyte cAllMeta = Lexel.SolidSoft | Lexel.SolidHard;

        uint col;

        void* pixels; uint pitch;
        mImage.lockPixelsRGBA32(pixels, pitch);

        auto nradius = max(radius-20,0);

        void* srcpixels; uint srcpitch;
        int sx, sy;
        if (mBackImage) {
            mBackImage.lockPixelsRGBA32(srcpixels, srcpitch);
            sx = mBackImage.size.x; sy = mBackImage.size.y;
        } else {
            //plain evil etc.: if no bitmap available, copy transparent pixel
            col = colorToRGBA32(mImage.colorkey());
            srcpixels = &col;
            sx = 1; sy = 1;
        }

        //draw the background image into the area to be destroyed
        //actually, you can only see a ring of that background image; the center
        //of the destruction is free landscape (except for SolidHard pixels)
        //the center is cleared later to achieve this
        //in the same call, mask all pixels with SolidHard to remove any
        //SolidSoft pixels...
        circle_masked(pos, radius, pixels, pitch, srcpixels, srcpitch, sx, sy,
            cAllMeta, Lexel.SolidSoft, Lexel.SolidHard);

        if (mBackImage) {
            mBackImage.unlockPixels();
        }

        //draw that funny border; the border is still solid and also is drawn on
        //solid ground only (except for SolidHard pxiels: they stay unchanged)
        //because all SolidSoft pixels were cleared above, only the remaining
        //landscape around the destruction will be coloured with this border...
        col = colorToRGBA32(mBorderColor);
        circle_masked(pos, radius+4, pixels, pitch, &col, 0, 1, 1,
            cAllMeta, Lexel.SolidSoft);

        if (nradius > 0) {
            //clear the center of the destruction (to get rid of that background
            //texture)
            col = colorToRGBA32(mImage.colorkey());
            circle_masked(pos, nradius, pixels, pitch, &col, 0, 1, 1,
                cAllMeta, 0);
        }

        mImage.unlockPixels();
    }

    //calculate normal at that position
    //this is (very?) expensive
    //maybe replace it by other methods as used by other worms clones
    // circle = if true check a circle, else a quad, with sides (radius*2+1)^2
    // dir = not-notmalized diection which points to the outside of the level
    // count = number of colliding pixels
    public void checkAt(Vector2i pos, int radius, bool circle, out Vector2i dir,
        out int count)
    {
        assert(radius >= 0);
        //xxx: maybe add a non-clipping fast path, if it should be needed
        //also could do tricks to avoid clipping at all...!
        auto st = pos;
        int[] acircle = getCircle(radius);

        //dir and count are initialized with 0

        for (int y = -radius; y <= radius; y++) {
            int xoffs = radius;
            if (circle) {
                 xoffs -= acircle[y+radius];
            }
            for (int x = -xoffs; x <= xoffs; x++) {
                int lx = st.x + x;
                int ly = st.y + y;
                bool isset = false; //mIsCave;
                if (lx >= 0 && lx < mWidth && ly >= 0 && ly < mHeight) {
                    isset = (mLevelData[ly*mWidth + lx] != 0);
                }
                if (isset) {
                    dir += Vector2i(x, y);
                    count++;
                }
            }
        }

        dir = -dir;
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
        if (radius in mCircles)
            return mCircles[radius];

        assert(radius >= 0);

        int[] stuff = new int[radius*2+1];
        drawing.circle(radius, radius, radius,
            (int x1, int x2, int y) {
                stuff[y] = x1;
            });
        mCircles[radius] = stuff;
        return stuff;
    }

    //oh yeah, manual bitmap drawing code!
    private void doDrawBmp(int px, int py, void* data, uint pitch, int w, int h,
        Lexel before, Lexel after)
    {
        void* dstptr; uint dstpitch;
        mImage.lockPixelsRGBA32(dstptr, dstpitch);
        //clip
        int cx1 = max(px, 0);
        int cy1 = max(py, 0);
        int cx2 = min(cast(int)mWidth, px+w);  //exclusive
        int cy2 = min(cast(int)mHeight, py+h);
        assert(cx2-cx1 <= w);
        assert(cy2-cy1 <= h);
        for (int y = cy1; y < cy2; y++) {
            //offset to relevant start of source scanline
            uint* src = cast(uint*)(data + pitch*(y-py) + (cx1-px)*uint.sizeof);
            uint* dst = cast(uint*)(dstptr + dstpitch*y + cx1*uint.sizeof);
            Lexel* dst_meta = &mLevelData[mWidth*y+cx1];
            for (int x = cx1; x < cx2; x++) {
                if (is_not_transparent(*src) && *dst_meta == before) {
                    *dst_meta = after;
                    //actually copy pixel
                    *dst = *src;
                }
                src++; dst++; dst_meta++;
            }
        }
        mImage.unlockPixels();
    }

    //draw a bitmap, but also modify the level pixels
    //where "before" is, copy a pixel and set pixe-metadata to "after"
    //bitmap is only drawn where level bitmap is transparent
    public void drawBitmap(Vector2i p, Surface source, Vector2i size,
        Lexel before, Lexel after)
    {
        size.x = min(size.x, source.size.x);
        size.y = min(size.y, source.size.y);
        void* data; uint pitch;
        source.lockPixelsRGBA32(data, pitch);
        doDrawBmp(p.x, p.y, data, pitch, size.x, size.y, before, after);
        source.unlockPixels();
    }

    /+
    untested... unneeded?
    //same as above, but only draw a sub region of the source bitmap
    // p == uper right corner in destination
    // sp == upper right corner in source bitmap
    public void drawBitmap(Vector2i p, Surface source, Vector2i sp,
        Vector2i size, Lexel before, Lexel after)
    {
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

    public this(Vector2i size) {
        mWidth = size.x;
        mHeight = size.y;
        mLog = registerLog("levelrenderer");

        mImage = getFramework.createSurface(size, DisplayFormat.RGBA32,
            Transparency.Colorkey);

        mLevelData.length = mWidth*mHeight;

        auto c = mImage.startDraw();
        c.clear(mImage.colorkey);
        c.endDraw();
    }

    //copy the level bitmap, per-pixel-metadata, background image and damage-
    //bordercolor from level
    //xxx this is a hack worth to be killed
    public this(Level level) {
        mImage = level.image.clone();
        auto fmt = getFramework.findPixelFormat(DisplayFormat.RGBA32);
        mImage.forcePixelFormat(fmt);

        mWidth = mImage.size.x;
        mHeight = mImage.size.y;
        mLog = registerLog("levelrenderer");

        if (level.backImage) {
            mBackImage = level.backImage.clone();
        }

        mLevelData = level.data.dup;
        mBorderColor = level.borderColor;
    }

    public void free() {
        mImage.free();
        if (mBackImage) {
            mBackImage.free();
        }
    }

    //create using the bitmap and pixel data
    //  release_this = don't copy image and metadata, instead, leave them to
    //                 level and set own fields to null
    public void createLevel(Level level, bool release_this) {
        Surface img;
        Lexel[] data;
        if (release_this) {
            img = mImage;
            data = mLevelData;
            mImage = null;
            mLevelData = null;
        } else {
            img = mImage.clone();
            data = mLevelData.dup;
        }

        level.mSize = img.size;
        level.mImage = img;
        level.data = data;
    }

    public Surface releaseImage() {
        auto img = mImage;
        mImage = null;
        return img;
    }

    public Vector2i size() {
        return mImage.size;
    }

    public Lexel[] levelData() {
        return mLevelData;
    }
}


//rasterizePolygon(): completely naive Y-X polygon rasterization algorithm
//the polygon is defined by the items of "points", it's implicitely closed with
//the edge (points[$-1], points[0])
//no edges must intersect with each other
//the algorithm also could handle several polygons (as long as they don't
//intersect), but I didn't need that functionality

//NOTE: The even-odd filling rule is used; and somehow the usual corner-cases
//  don't (seem to) happen (because the edges are removed from the active edge
//  list before the edges join each other, so to say). Maybe there's also input
//  data for which the current implementation outputs garbage...

private struct Edge {
    int ymax;
    double xmin;
    double m1;
    Edge* next; //next in scanline or AEL
}

private int myround(float f) {
    return cast(int)(f+0.5f);
}

private void rasterizePolygon(uint width, uint height, Vector2f[] points,
    bool invert, void delegate (int y, int x1, int x2) renderScanline)
{
    if (points.length < 3)
        return;

    //note: leave entries in per_scanline[y] unsorted
    //I sort them inefficiently when inserting them into the AEL
    Edge*[] per_scanline;
    per_scanline.length = height;

    //convert points array and create Edge structs and insert them
    void add_edge(in Vector2f a, in Vector2f b) {
        Edge* edge = new Edge();

        bool invert = false;
        if (a.y > b.y) {
            a.swap(b);
            invert = true;
        }

        int ymin = myround(a.y);
        edge.ymax = myround(b.y);

        //throw away horizontal segments or if not visible
        if (edge.ymax == ymin || edge.ymax < 0 || ymin >= cast(int)height) {
            return;
        }

        auto d = b-a;
        edge.m1 = cast(double)d.x / d.y; //x increment for each y increment

        if (ymin < 0) {
            //clipping, xxx: seems to work, but untested
            a.x = a.x += edge.m1*(-ymin);
            a.y = 0;
            ymin = 0;
        }
        assert(ymin >= 0);

        edge.xmin = a.x;

        if (ymin >= height)
            return;

        edge.next = per_scanline[ymin];
        per_scanline[ymin] = edge;
    }

    for (uint n = 0; n < points.length-1; n++) {
        add_edge(points[n], points[n+1]);
    }
    add_edge(points[$-1], points[0]);

    //umm, I wonder if this trick always works
    if (invert) {
        add_edge(Vector2f(0, 0), Vector2f(0, height));
        add_edge(Vector2f(width, 0), Vector2f(width, height));
    }

    Edge* ael;
    Edge* resort_edges_first;
    Edge* resort_edges_last;

    for (uint y = 0; y < height; y++) {
        //copy new edges into the AEL
        Edge* newedge = per_scanline[y];

        //somewhat hacky way to resort something
        if (resort_edges_last) {
            resort_edges_last.next = newedge;
            newedge = resort_edges_first;
            resort_edges_first = resort_edges_last = null;
        }

        while (newedge) {
            Edge* next = newedge.next;
            newedge.next = null;

            //AEL must be sorted, so that e1.xmin <= e2.xmin etc.
            //since edges that are inserted can have the same starting-
            //point, use the increased value
            //all my approaches to keep the AEL sorted failed (numeric problems)
            //  so resort the AEL as soon as the sorting condition is violated
            Edge** ptr = &ael;
            while (*ptr && (*ptr).xmin < newedge.xmin) {
                ptr = &(*ptr).next;
            }
            newedge.next = *ptr;
            *ptr = newedge;

            newedge = next;
        }

        //delete old edges
        Edge** cur = &ael;
        while (*cur) {
            if (y >= (*cur).ymax) {
                *cur = (*cur).next;
            } else {
                cur = &(*cur).next;
            }
        }

        if (ael is null)
            continue;

        //draw and advance
        Edge* edge = ael;
        uint r = 0;
        bool c = false;
        Edge* last;
        float last_xmin;
        bool need_resort = false;
        while (edge) {
            if (last) {
                assert(last_xmin <= edge.xmin);
                if (last_xmin > edge.xmin) {
                    renderScanline(y, myround(last.xmin-last.m1),
                        myround(edge.xmin));
                }
            }
            c = !c;
            assert(y <= edge.ymax);
            if (last && !c) {
                renderScanline(y, myround(last.xmin-last.m1),
                    myround(edge.xmin));
            }
            //advance
            last_xmin = edge.xmin;
            edge.xmin += edge.m1;
            if (last && last.xmin > edge.xmin)
                need_resort = true;
            last = edge;
            edge = edge.next;
            r++;
        }
        if (need_resort) {
            resort_edges_first = ael;
            resort_edges_last = last;
            ael = null;
        }
    }
}
