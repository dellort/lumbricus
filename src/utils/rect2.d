module utils.rect2;
import utils.vector2;
import utils.misc : min, max;
import std.string : format;

//T is the most underlying type, i.e. float or int
//NOTE: most member functions expect the rect to be in "normal" form
//      (see normalize() for definition)
public struct Rect2(T) {
    alias Vector2!(T) Point;
    Point p1, p2;

    public static Rect2 opCall(Point p1, Point p2) {
        Rect2 r;
        r.p1 = p1;
        r.p2 = p2;
        return r;
    }
    public static Rect2 opCall(T x1, T y1, T x2, T y2) {
        return Rect2(Point(x1, y1), Point(x2, y2));
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

    Point size() {
        return p2 - p1;
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

    //Rect must be normal
    bool isInside(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2 && p.x1 < p2.x1 && p.x2 < p2.x2);
    }
    bool isInsideB(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2
            && p.x1 <= p2.x1 && p.x2 <= p2.x2);
    }

    //returns if any point of other is inside "this"
    bool contains(in Rect2 other) {
        return isInside(other.p1) || isInside(other.p2);
    }

    bool intersects(in Rect2 other) {
        return contains(other) ||other.contains(*this);
    }

    //clip pt to this rect; isInsideB(clip(pt)) will always return true
    //(isInside() won't; also NaNs may mess it all up when using floats)
    Point clip(in Point pt)
    out(r) {assert(isInsideB(r));}
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
        return format("[%s - %s]", p1, p2);
    }
}

alias Rect2!(int) Rect2i;
