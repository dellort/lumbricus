module renderer;

//This module only renders auto-generated levels.
//It smoothes and draws the polygons generated by genrandom.d and also
//texturizes them.

import level.level;
import framework.framework;
import utils.vector2;
import utils.mylist;
import math = std.math;

import std.stdio;

//define "cairo_test" to use the Cairo library to test the polygon rasterizer
//currently, there are slight differences (sub pixel/rounding stuff?), but
//apart from that, the output of rasterizePolygon() looks ok
//cf. drawScanline()
//we didn't want to use Cairo itsself for drawing, because of the additional
//library dependencies
//for the current input data, our implementation seems to be faster than Cairo
//anyway (most time, for our input data)
//if "cairo_test" is not defined, Cairo isn't used at all

//version = cairo_test;

version (cairo_test) {
    import cairo.cairo;
}

debug import std.perf;

private alias Vector2f Point;

package class LevelRenderer {
    private uint mWidth, mHeight;
    private Color mColorKey;
    private uint mTranslatedColorKey;
    private uint[] mImageData;
    private Lexel[] mLevelData;
    
    private PixelFormat fmt;
    
    version (cairo_test) {
        private cairo_t* mCr;
    }
    
    //because I'm stupid, I'll store all points into a linked lists to be able
    //to do naive corner cutting by subdividing the curve recursively
    private struct Vertex {
        Point pt;
        bool no_subdivide = false;
        mixin ListNodeMixin;
    }
    private alias List!(Vertex*) VertexList;
    
    private static void cornercut(VertexList verts) {
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
                    newv.pt = pt + (p2-pt)/4.0f*3.0f;
                    pt = p2;
                    p2 = p2 + (p3-p2)/4.0f;
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
    //"visible" is true if the polygon should appear in the image surface, and
    //"color" is the color of the drawed filled polygon (alpha value ignored)
    //nosubdiv: indices for points that start lines which shouldn't be
    //  "interpolated" (they won't be changed)
    //"texture" is used to fill the new polygon, if it is null, make all pixels
    //  covered by the polygon transparent
    public void addPolygon(Point[] points, uint[] nosubdiv, bool visible,
        Point texture_offset, Surface texture, Lexel marker)
    {
        if (!visible)
            return;
        
        //also not good and nice
        uint tex_pitch, tex_w, tex_h;
        void* tex_data;
        uint plain_evil;
        
        if (texture !is null) {
            texture.convertToData(fmt, tex_pitch, tex_data);
            tex_w = texture.size.x;
            tex_h = texture.size.y;
        } else {
            plain_evil = mTranslatedColorKey;
            tex_data = &plain_evil;
            tex_w = tex_h = 1;
            tex_pitch = 4;
        }
        
        int tex_offset_x = cast(int)(texture_offset.x);
        int tex_offset_y = cast(int)(texture_offset.y);
        
        VertexList vertices = new VertexList(Vertex.getListNodeOffset());
        
        uint curindex = 0;
        foreach(Point p; points) {
            Vertex* v = new Vertex();
            v.pt = p;
            //obviously, nosubdiv should be small
            foreach(uint index; nosubdiv) {
                if (index == curindex)
                    v.no_subdivide = true;
            }
            vertices.insert_tail(v);
            curindex++;
        }
        
        cornercut(vertices);
        
        Point[] urgs;
        urgs.length = vertices.count;
        urgs.length = 0;
        foreach(Vertex* v; vertices) {
            urgs ~= v.pt;
        }
        
        version (cairo_test) {
            renderCairo(urgs);
        }

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
            uint* foo = &mImageData[y*mWidth+x1];
            uint* texptr = cast(uint*)(tex_data + ty*tex_pitch);
            Lexel* markerptr = &mLevelData[y*mWidth+x1];
            for (uint x = x1; x < x2; x++) {
                uint* texel = texptr + (x + tex_offset_x) % tex_w;
                
                if (visible) {
                    version (cairo_test) {
                        if (*foo == 0xffff0000) { //cairo+our algo set a pixel
                            *foo = translated_color;
                        } else if (*foo == 0) { //only we set a pixel
                            *foo = 0x00ff00;
                        } else { //whatever
                            *foo = 0xff;
                        }
                    } else {
                        *foo = *texel;
                    }
                }
                
                *markerptr = marker;
                
                foo++;
                markerptr++;
            }
        }
        
        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }
        
        //rasterizePolygon(cast(uint*)ptr, mWidth, mHeight, mWidth*4, 0xffffff, urgs);
        rasterizePolygon(mWidth, mHeight, urgs, false, &drawScanline);
        
        debug {
            counter.stop();
            writefln("render.d: polygon rendered in %s us",
                counter.microseconds);
        }
    }
    
    //it's a strange design decision to do it _that_ way. sorry for that.
    //draw a border in "a", using that texture, where "a" forms a border to "b"
    //it always scans in the given direction; to draw both borders where "a" is
    //on top ob "b" and where "b" is on top of "a", you have to call this twice
    //(which isn't a problem, since you might want to use different textures
    //for this)
    //"up": false=scan up-to-down, true=scan down-to-up ("a" und "b" are also
    //  checked in that order)
    //"texture" must not be null
    public void drawBorder(Lexel a, Lexel b, bool up, Surface texture) {
        int dir = up ? -1 : +1;
        
        uint tex_pitch;
        void* tex_data;
        texture.convertToData(fmt, tex_pitch, tex_data);
        uint tex_w = texture.size.x;
        uint tex_h = texture.size.y;
        uint* texptr = cast(uint*)tex_data;
        
        //the algorithm was more or less ripped from Matthias' code
        ubyte[] pline = new ubyte[mWidth]; //initialized to 0
        int start = up ? mHeight-1 : 0;
        for (int y = start; y >= 0 && y <= mHeight-1; y += dir) {
            uint* scanline = mImageData.ptr + y*mWidth;
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
                if (pline[x] > 0 && pline[x] < 0xFF) {
                    uint* texel = texptr + x%tex_w;
                    texel = cast(uint*)(cast(void*)texel + ((tex_h-pline[x])%tex_h)*tex_pitch);
                    *scanline = *texel;
                }
                
                scanline++;
            }
        }
    }
    
    public this(uint width, uint height, Color transparency) {
        mWidth = width;
        mHeight = height;
        mColorKey = transparency;
        
        //xxx this isn't good and nice; needs rework anyway
        fmt.depth = 32; //SDL doesn't like depth=24 (maybe it takes 3 bytes pp)
        fmt.bytes = 4;
        fmt.mask_r = 0xff0000;
        fmt.mask_g = 0x00ff00;
        fmt.mask_b = 0x0000ff;
        fmt.mask_a = 0xff000000;
        
        ubyte r = cast(ubyte)(mColorKey.r*255);
        ubyte g = cast(ubyte)(mColorKey.g*255);
        ubyte b = cast(ubyte)(mColorKey.b*255);
        ubyte a = cast(ubyte)(mColorKey.a*255);
        
        mTranslatedColorKey = a << 24 | r << 16 | g << 8 | b;

        mImageData.length = mWidth*mHeight;
        mLevelData.length = mWidth*mHeight;
        
        //(initialize all items with that value)
        mImageData[] = mTranslatedColorKey;

        version (cairo_test) {
            initCairo();
        }
    }
    
    public Level render() {
        auto mImage = getFramework.createImage(mWidth, mHeight, mWidth*4, fmt,
            mImageData.ptr);
        mImage.colorkey = mColorKey;
        Level level = new Level(mWidth, mHeight, mImage);
        level.data[] = mLevelData; //?
        
        version (cairo_test) {
            destroyCairo(); //better now than later
        }
        
        return level;
    }
    
    //just for debugging
    version (cairo_test) {
        private void renderCairo(Point[] points) {
            //add points to the current Cairo path
            void pathify(bool arrow) {
                if (points.length < 2)
                    return;
                
                Point prev = points[$-1];
                cairo_move_to(mCr, prev.x, prev.y);

                foreach(Point p; points) {
                    cairo_line_to(mCr, p.x, p.y);
                    if (arrow) {
                        Point d = p-prev;
                        d.length = d.length-5.0f;
                        Point s = prev+d;
                        d = d.orthogonal;
                        d.length = 5.0f;
                        Point a = s+d;
                        Point b = s-d;
                        cairo_line_to(mCr, a.x, a.y);
                        cairo_move_to(mCr, b.x, b.y);
                        cairo_line_to(mCr, p.x, p.y);
                    }
                    prev = p;
                }
            }
            
            cairo_new_path(mCr);
            pathify(false);
            cairo_close_path(mCr);
            cairo_set_source_rgb(mCr, 1.0f, 0, 0);
            
            debug {
                auto counter = new PerformanceCounter();
                counter.start();
            }
            
            cairo_fill(mCr);
            
            debug {
                counter.stop();
                writefln("render.d: cairo rendered in   %s us",
                    counter.microseconds);
            }
        }
        
        private void initCairo() {
            cairo_load();

            cairo_surface_t* surface = cairo_image_surface_create_for_data(
                cast(ubyte*)mImageData.ptr, cairo_format_t.CAIRO_FORMAT_RGB24,
                mWidth, mHeight, mWidth*4);
            assert(cairo_surface_status(surface)
                == cairo_status_t.CAIRO_STATUS_SUCCESS);
            mCr = cairo_create(surface);
            assert(cairo_status(mCr) == cairo_status_t.CAIRO_STATUS_SUCCESS);
            cairo_set_antialias(mCr, cairo_antialias_t.CAIRO_ANTIALIAS_NONE);
            cairo_set_fill_rule(mCr,
                cairo_fill_rule_t.CAIRO_FILL_RULE_WINDING);
            cairo_set_line_width(mCr, 1.0f);
        }
        
        private void destroyCairo() {
            if (mCr !is null) {
                cairo_destroy(mCr);
                mCr = null;
            }
        }
    } //version(cairo_test)
}


//rasterizePolygon(): mostly naive Y-X polygon rasterization algorithm
//the polygon is defined by the items of "points", it's implicitely closed with
//the edge (points[$-1], points[0])
//no edges must intersect with each other
//the algorithm also could handle several polygons (as long as they don't
//intersect), but I didn't need that functionality

//NOTE: The even-odd filling rule is used; and somehow the usual corner-cases
//  don't (seem to) happen (because the edges are removed from the active edge
//  list before the edges join each other, so to say). Maybe there's also input
//  data for which the current implementation outputs garbage...

//currently, there are two versions
//delete the one that's slow or doesn't work or which sucks
version = ael_list;
//version = ael_array;

private struct Edge {
    int ymax;
    double xmin;
    double xmax; //xxx
    double m1;
    Edge* next; //next in scanline or AEL
}

private int myround(float f) {
    return cast(int)(f+0.5f);
}

version (ael_array) {
    import cstdlib = std.c.stdlib;

    extern (C) private int ael_compare(void* a, void* b) {
        Edge** pa = cast(Edge**)a, pb = cast(Edge**)b;
        if (*pa is null)
            return 1;
        if (*pb is null)
            return -1;
        if ((*pa).xmin > (*pb).xmin)
            return 1;
        else
            return -1;
    }
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
        if (edge.ymax == ymin || edge.ymax < 0 || ymin >= height) {
            return;
        }
        
        auto d = b-a;
        edge.m1 = cast(double)d.x / d.y; //x increment for each y increment
        
        if (ymin < 0) {
            //clipping, xxx: untested
            a.x = a.x += edge.m1*(-ymin);
            a.y = 0;
            ymin = 0;
        }
        assert(ymin >= 0);
        
        edge.xmin = a.x;
        edge.xmax = b.x;
        
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
    
version(ael_array) {
    //worst case: all edges in ael
    Edge*[] ael;
    ael.length = points.length+1;
    uint ael_length = 0;
    float last_xmin;
    for (uint y = 0; y < height; y++) {
        Edge* newedge = per_scanline[y];
        while (newedge) {
            ael[ael_length] = newedge;
            ael_length++;
            newedge = newedge.next;
        }
        //delete old ones
        for (uint i = 0; i < ael_length; i++) {
            if (y >= ael[i].ymax)
                ael[i] = null;
        }
        cstdlib.qsort(ael.ptr, ael_length, (Edge*).sizeof, &ael_compare);
        //draw and get rid of old items
        bool c = false;
        for (uint i = 0; i < ael_length; i++) {
            Edge* cur = ael[i];
            if (cur is null) {
                ael_length = i;
                break;
            }
            c = !c;
            if (i > 0) {
                assert(last_xmin <= cur.xmin);
            }
            if (i > 0 && !c) {
                renderScanline(y, myround(last_xmin), myround(cur.xmin));
            }
            last_xmin = cur.xmin;
            cur.xmin += cur.m1;
        }
    }
}
version(ael_list) {
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
            //xxx all my approaches to keep the AEL sorted failed
            //  so resort the AEL as soon as the sorting condition is violated
            Edge** ptr = &ael;
            while (*ptr && (*ptr).xmin < newedge.xmin) {
            //while (*ptr && (*ptr).xmin + (*ptr).m1 < newedge.xmin + newedge.m1) {
            //while (*ptr && (*ptr).xmin + (*ptr).xmax < newedge.xmin + newedge.xmax) {
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
                if (last_xmin > edge.xmin)
                    renderScanline(y, myround(last.xmin-last.m1), myround(edge.xmin));
            }
            c = !c;
            assert(y <= edge.ymax);
            if (last && !c) {
                renderScanline(y, myround(last.xmin-last.m1), myround(edge.xmin));
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
        //need_resort = true;
        if (need_resort) {
            resort_edges_first = ael;
            resort_edges_last = last;
            ael = null;
        }
    }
} //version(ael_list)
}
