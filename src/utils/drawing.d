module utils.drawing;

import utils.vector2;

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

void rasterizePolygon(uint width, uint height, Vector2f[] points,
    bool invert, void delegate (int x1, int x2, int y) renderScanline)
{
    if (points.length < 3)
        return;

    //note: leave entries in per_scanline[y] unsorted
    //I sort them inefficiently when inserting them into the AEL
    Edge*[] per_scanline;
    per_scanline.length = height;
    //manual mm
    Edge* all_edges;

    //convert points array and create Edge structs and insert them
    void add_edge(in Vector2f a, in Vector2f b) {
        Edge* edge = new Edge();
        edge.all = all_edges;
        all_edges = edge;

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
                    renderScanline(myround(last.xmin-last.m1),
                        myround(edge.xmin), y);
                }
            }
            c = !c;
            assert(y <= edge.ymax);
            if (last && !c) {
                renderScanline(myround(last.xmin-last.m1),
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
