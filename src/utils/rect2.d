module utils.rect2;
import utils.vector2;
import utils.misc : min, max, myformat;

//T is the most underlying type, i.e. float or int
//NOTE: most member functions expect the rect to be in "normal" form
//      (see normalize() for definition)
public struct Rect2(T) {
    alias Vector2!(T) Point;
    Point p1, p2;

    /+
     +  p1   pA
     +  pB   p2
     +/
    Point pA() {
        return Point(p2.x, p1.y);
    }
    Point pB() {
        return Point(p1.x, p2.y);
    }

    public static Rect2 opCall(Point p1, Point p2) {
        Rect2 r;
        r.p1 = p1;
        r.p2 = p2;
        return r;
    }
    public static Rect2 opCall(T x1, T y1, T x2, T y2) {
        return Rect2(Point(x1, y1), Point(x2, y2));
    }
    // opCall(Vector2i(0,0), b)
    public static Rect2 opCall(Point b) {
        Rect2 r;
        r.p2 = b;
        return r;
    }

    //rect at point p with that size
    public static Rect2 Span(Point p, Point size) {
        return Rect2(p, p + size);
    }
    public static Rect2 Span(T x, T y, T sx, T sy) {
        return Rect2(x, y, x+sx, y+sy);
    }

    //return a rectangle that could be considered to be "empty"
    // .isNormal() will return false, and the first .extend() will make the
    // rectangle to exactly the extended point, and also makes isNormal()==true
    public static Rect2 Empty() {
        Rect2 r;
        r.p1 = Point(T.max);
        r.p2 = Point(T.min);
        return r;
    }

    //translate rect by the vector r
    Rect2 opAdd(Point r) {
        Rect2 res = *this;
        res.p1 += r;
        res.p2 += r;
        return res;
    }
    Rect2 opSub(Point r) {
        return *this + (-r);
    }

    void opAddAssign(Point r) {
        p1 += r;
        p2 += r;
    }
    void opSubAssign(Point r) {
        p1 -= r;
        p2 -= r;
    }

    Point size() {
        return p2 - p1;
    }

    Point center() {
        return p1 + (p2-p1)/2;
    }

    bool isNormal() {
        return (p1.x1 <= p2.x1) && (p1.x2 <= p2.x2);
    }

    //normal means: (p1.x1 <= p2.x1) && (p1.x2 <= p2.x2) is true
    void normalize() {
        Rect2 n;
        n.p1.x1 = min(p1.x1, p2.x1);
        n.p1.x2 = min(p1.x2, p2.x2);
        n.p2.x1 = max(p1.x1, p2.x1);
        n.p2.x2 = max(p1.x2, p2.x2);
        *this = n;
    }

    //extend rectangle so that p is inside the rectangle
    //"this" must be "normal"
    //"border" sets so to say the size of the point, should be 1 or 0
    //(isInside(p) will return true)
    void extend(Point p, T border = 1) {
        if (p.x1 < p1.x1) p1.x1 = p.x1;
        if (p.x2 < p1.x2) p1.x2 = p.x2;
        if (p.x1 >= p2.x1) p2.x1 = p.x1+border;
        if (p.x2 >= p2.x2) p2.x2 = p.x2+border;
        if (border) {
            assert(isInside(p));
        } else {
            assert(isInsideB(p));
        }
    }
    //same as above for rectangles
    void extend(Rect2 r) {
        extend(r.p1, 0);
        extend(r.p2, 0);
    }

    //move all 4 borders by this value
    //xxx maybe should clip for too large negative values
    void extendBorder(Point value) {
        p1 -= value;
        p2 += value;
    }

    //fit this Rect2 into another Rect2 r
    //isInside will return true for r.p1 and r.p2
    void fitInside(Rect2 r) {
        if (p1.x < r.p1.x)
            p1.x = r.p1.x;
        if (p1.y < r.p1.y)
            p1.y = r.p1.y;
        if (p2.x >= r.p2.x)
            p2.x = r.p2.x-1;
        if (p2.y >= r.p2.y)
            p2.y = r.p2.y-1;
    }
    //same for isInsideB
    void fitInsideB(Rect2 r) {
        if (p1.x < r.p1.x)
            p1.x = r.p1.x;
        if (p1.y < r.p1.y)
            p1.y = r.p1.y;
        if (p2.x > r.p2.x)
            p2.x = r.p2.x;
        if (p2.y > r.p2.y)
            p2.y = r.p2.y;
    }

    bool isInside(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2 && p.x1 < p2.x1 && p.x2 < p2.x2);
    }
    bool isInsideB(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2
            && p.x1 <= p2.x1 && p.x2 <= p2.x2);
    }

    //border is exclusive
    bool intersects(in Rect2 rc) {
        return (rc.p2.x1 > p1.x1 && rc.p2.x2 > p1.x2
            && rc.p1.x1 < p2.x1 && rc.p1.x2 < p2.x2);
    }

    //return true if this contains rc completely
    bool contains(in Rect2 rc) {
        return (p1.x1 <= rc.p1.x1 && p2.x1 >= rc.p2.x1
            && p1.x2 <= rc.p1.x2 && p2.x2 >= rc.p2.x2);
    }

    //the common rectangle covered by both rectangles
    //result.isNormal() will return false if there's no intersection
    Rect2 intersection(in Rect2 rc) {
        Rect2 r;
        r.p1.x1 = max(p1.x1, rc.p1.x1);
        r.p1.x2 = max(p1.x2, rc.p1.x2);
        r.p2.x1 = min(p2.x1, rc.p2.x1);
        r.p2.x2 = min(p2.x2, rc.p2.x2);
        return r;
    }

    //substract the rectangles in list from this, and return what's left over
    //the rects in list may intersect, and the resulting rects won't intersect
    Rect2[] substractRects(Rect2[] list) {
        Rect2[] cur = [*this]; //cur = what's left over
        foreach (ref rem; list) {
            Rect2[] cur2;
            foreach (ref rc; cur) {
                //substract rem from rc, which either removes rc2, possibly
                //modifies it, or adds up to 3 additional rectangles
                if (!rc.intersects(rem)) {
                    cur2 ~= rc;
                    continue;
                } else if (rem.contains(rc)) {
                    //remove this one, so don't readd
                    continue;
                }
                //intersect in some irky way => up to 4 rects
                //top/bottom and the 4 corners
                if (rc.p1.y < rem.p1.y) {
                    cur2 ~= Rect2(rc.p1, Point(rc.p2.x, rem.p1.y));
                }
                if (rc.p2.y > rem.p2.y) {
                    cur2 ~= Rect2(Point(rc.p1.x, rem.p2.y), rc.p2);
                }
                //left/right
                T y1 = max(rem.p1.y, rc.p1.y);
                T y2 = min(rem.p2.y, rc.p2.y);
                if (rc.p1.x < rem.p1.x) {
                    cur2 ~= Rect2(Point(rc.p1.x, y1), Point(rem.p1.x, y2));
                }
                if (rc.p2.x > rem.p2.x) {
                    cur2 ~= Rect2(Point(rem.p2.x, y1), Point(rc.p2.x, y2));
                }
            }
            cur = cur2;
        }
        return cur;
    }

    //clip pt to this rect; isInsideB(clip(pt)) will always return true
    //(isInside() won't; also NaNs may mess it all up when using floats)
    Point clip(in Point pt)
    //removed because sometimes it's inconvenient out(r) {assert(isInsideB(r));}
    body {
        Point r = pt;
        if (r.x2 > p2.x2)
            r.x2 = p2.x2;
        if (r.x2 < p1.x2)
            r.x2 = p1.x2;
        if (r.x1 > p2.x1)
            r.x1 = p2.x1;
        if (r.x1 < p1.x1)
            r.x1 = p1.x1;
        return r;
    }

    char[] toString() {
        return myformat("[{} - {}]", p1, p2);
    }
}

alias Rect2!(int) Rect2i;
alias Rect2!(float) Rect2f;
