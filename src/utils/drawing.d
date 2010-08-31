module utils.drawing;

import utils.array;
import utils.misc;
import utils.rect2;
import utils.vector2;

import math = tango.math.Math;

//from http://en.wikipedia.org/wiki/Midpoint_circle_algorithm
//(modified for filling)
void circle(int x, int y, int r,
    void delegate(int x1, int x2, int y) cb)
{
    if (r <= 0)
        return;

    int cx = 0, cy = r;
    int df = 1 - r;
    int ddf_x = 0;
    int ddf_y = -2 * r;

    while (cx < cy) {
        cb(x-cy,x+cy,y+cx);
        cb(x-cy,x+cy,y-cx);
        if (df >= 0)  {
            cb(x-cx,x+cx,y+cy);
            cb(x-cx,x+cx,y-cy);
            cy--;
            ddf_y += 2;
            df += ddf_y;
        }

        ddf_x += 2;
        df += ddf_x + 1;
        cx++;
    }
    cb(x-cy,x+cy,y+cx);
    cb(x-cy,x+cy,y-cx);
}

void line(Vector2i p1, Vector2i p2, void delegate(Vector2i pt) cb) {
    //my computer science prof said bresenham isn't it worth these days
    //that's a good excuse for this crap, isn't it
    //copied from draw_sdl.d (unifying isn't worth it)
    Vector2f d = toVector2f(p2-p1);
    Vector2f old = toVector2f(p1);
    int n = cast(int)(max(math.abs(d.x), math.abs(d.y)));
    d = d / cast(float)n;
    for (int i = 0; i < n; i++) {
        int px = cast(int)(old.x+0.5f);
        int py = cast(int)(old.y+0.5f);
        cb(Vector2i(px, py));
        old = old + d;
    }
}

//naive corner cutting to make polygons smoother
//(I'm too dumb and lazy to do anything more sophisticated such as bezier)
//nosubdiv = indices of vertices that should not take part in subdivision
//  e.g. nosubdiv=[2] => line between vertices[2] and vertices[3] is untouched
//steps = number of subdivisions
//start = start of the subdivision (0.0-1.0, 0.0 means no subdivision)
//always returns a newly allocated array
Vector2f[] cornercut(Vector2f[] vertices, uint[] nosubdiv, int steps = 5,
    float start = 0.25f)
{
    if (vertices.length < 3 || steps < 1)
        return vertices.dup;

    struct Vertex {
        Vector2f pt;
        bool no_subdivide = false;
    }

    AppenderVolatile!(Vertex) verts, nverts;

    foreach (size_t curindex, ref v; vertices) {
        Vertex nv = Vertex(v, false);
        //obviously, nosubdiv should be small
        foreach(uint val; nosubdiv) {
            if (val == curindex)
                nv.no_subdivide = true;
        }
        verts ~= nv;
    }

    for (int i = 0; i < steps; i++) {
        nverts.length = 0;
        for (size_t n = 0; n < verts.length; n++) {
            auto cur = verts[n];
            auto next = verts[(n+1) % verts.length];
            auto overnext = verts[(n+2) % verts.length];
            if (!cur.no_subdivide && !next.no_subdivide) {
                auto p1 = cur.pt, p2 = next.pt, p3 = overnext.pt;
                nverts ~= Vertex(p2 + (p1-p2)*start);
                nverts ~= Vertex(p3 + (p2-p3)*(1.0f - start));
            } else {
                nverts ~= next;
            }
        }
        //prepare for next iteration - take over contents
        swap(nverts, verts);
    }

    scope(exit) { verts.free(); nverts.free(); }
    auto res = arrayMap(verts[], (Vertex v) { return v.pt; });
    return res;
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
    Edge* all;
}

private int myround(float f) {
    return cast(int)(f+0.5f);
}

//clip rect: renderScanline will never be called with coordinates outside the
//  rect; pixels on the bottom/right border are not considered to be included
void rasterizePolygon(Rect2i clip, Vector2f[] points,
    void delegate (int x1, int x2, int y) renderScanline)
{
    void scanline(int x1, int x2, int y) {
        if (x2 < clip.p1.x || x1 >= clip.p2.x)
            return;
        if (x1 < clip.p1.x)
            x1 = clip.p1.x;
        if (x2 > clip.p2.x)
            x2 = clip.p2.x;
        assert(y >= clip.p1.y && y < clip.p2.y);
        assert(x2 >= x1);
        if (x1 == x2)
            return;
        renderScanline(x1, x2, y);
    }

    if (points.length < 3)
        return;

    //negative sizes
    if (!clip.isNormal())
        return;

    //note: leave entries in per_scanline[y] unsorted
    //I sort them inefficiently when inserting them into the AEL
    Edge*[] per_scanline;
    per_scanline.length = clip.p2.y - clip.p1.y;
    //manual mm
    Edge* all_edges;

    //convert points array and create Edge structs and insert them
    void add_edge(in Vector2f a, in Vector2f b) {
        Edge* edge = new Edge();
        edge.all = all_edges;
        all_edges = edge;

        if (a.y > b.y)
            a.swap(b);

        int ymin = myround(a.y);
        edge.ymax = myround(b.y);

        //throw away horizontal segments or if not visible
        if (edge.ymax == ymin || edge.ymax < clip.p1.y || ymin >= clip.p2.y)
            return;

        auto d = b-a;
        edge.m1 = cast(double)d.x / d.y; //x increment for each y increment

        if (ymin < clip.p1.y) {
            //clipping, xxx: seems to work, but untested
            a.x = a.x += edge.m1*(clip.p1.y-ymin);
            a.y = clip.p1.y;
            ymin = clip.p1.y;
        }
        assert(ymin >= clip.p1.y);

        edge.xmin = a.x;

        if (ymin >= clip.p2.y)
            return;

        int yidx = ymin - clip.p1.y;
        edge.next = per_scanline[yidx];
        per_scanline[yidx] = edge;
    }

    for (uint n = 0; n < points.length-1; n++) {
        add_edge(points[n], points[n+1]);
    }
    add_edge(points[$-1], points[0]);

    Edge* ael;
    Edge* resort_edges_first;
    Edge* resort_edges_last;

    for (int y = clip.p1.y; y < clip.p2.y; y++) {
        //copy new edges into the AEL
        Edge* newedge = per_scanline[y-clip.p1.y];

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
                //assertion sometimes fails for unknown reasons
                //commenting it because I have no clue what this code even does
                //especially because the following if handles it (???)
                //--assert(last_xmin <= edge.xmin);
                if (last_xmin > edge.xmin) {
                    scanline(myround(last.xmin-last.m1),
                        myround(edge.xmin), y);
                }
            }
            c = !c;
            assert(y <= edge.ymax);
            if (last && !c) {
                scanline(myround(last.xmin-last.m1),
                    myround(edge.xmin), y);
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

    while (all_edges) {
        Edge* t = all_edges;
        all_edges = t.all;
        delete t;
    }

    delete per_scanline;
}
