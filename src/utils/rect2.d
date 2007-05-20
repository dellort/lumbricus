module utils.rect2;
import utils.vector2;
import utils.misc : min, max;

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

    //Rect must be normal
    bool isInside(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2 && p.x1 < p2.x1 && p.x2 < p2.x2);
    }
    bool isInsideB(Point p) {
        return (p.x1 >= p1.x1 && p.x2 >= p1.x2
            && p.x1 <= p2.x1 && p.x2 <= p2.x2);
    }
}

alias Rect2!(int) Rect2i;
