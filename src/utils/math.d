module utils.math;

public import utils.vector2;// : Vector2f;
import utils.rect2;
import math = tango.math.Math;
public import utils.misc : realmod;

/// Intersect two lines given (p1+dir_1*t1, p2+dir_2*t2), and return the tX
/// values, where these lines intersect; returns true if the point is "within".
/// out_t1 and out_t2 are changed even when the function returns false
/// tolerance is an absolute value which makes the intersection check weaker
//or should this be a generic function
public bool lineIntersect(Vector2f p1, Vector2f dir_1, Vector2f p2,
    Vector2f dir_2, out float out_t1, out float out_t2, float tolerance = 0.0f)
{
    //Set the formulas for both lines equal and resolve the linear equation
    //system by inverting the matrix...
    //(numerically, this isn't good, so change it if you don't like it)
    float det = 1.0f / (dir_1.y*dir_2.x - dir_1.x*dir_2.y);
    /+
     +   [t1]  =  [mat11, mat21]   .   [b1]
     +   [t2]  =  [mat21, mat22]   .   [b2]
     +/
    float mat11 = -dir_2.y*det;
    float mat21 = -dir_1.y*det;
    float mat12 = dir_2.x*det;
    float mat22 = dir_1.x*det;

    float b1 = p2.x - p1.x;
    float b2 = p2.y - p1.y;

    out_t1 = mat11*b1 + mat12*b2;
    out_t2 = mat21*b1 + mat22*b2;

    ////this also should work if the lines are parallel, since inf > 1.0f
    //return (out_t1 >= 0.0 && out_t1 <= 1.0 && out_t2 >= 0.0 && out_t2 <= 1.0);

    double tx1 = tolerance / dir_1.length();
    double tx2 = tolerance / dir_2.length();
    return (out_t1 >= -tx1 && out_t1 <= 1.0f + tx1
        && out_t2 >= -tx2 && out_t2 <= 1.0f + tx2);
}

//return distance of two angles in radians
float angleDistance(float a, float b) {
    auto r = realmod(a - b, cast(float)math.PI*2);
    if (r > math.PI) {
        r = math.PI*2 - r;
    }
    return r;
}

//return the side the angle is facing
// if the angle is in between, return left when it points to y+, else right
T angleLeftRight(T)(float angle, T left, T right) {
    return (realmod(angle+math.PI/2, math.PI*2) < math.PI) ? right : left;
}

//ewww whatever
//rotation is a full angle (0..PI) and side_angle selects an angle on the left
//or right side (-PI/2..+PI/2) wherever rotation looks at -> return real angle
//maybe doesn't really belong here
float fullAngleFromSideAngle(float rotation, float side_angle) {
    float w = angleLeftRight(rotation, -1.0f, +1.0f);
    return (1-w)*math.PI/2 - w*side_angle;
}

//...and because it's really this what's usually needed...:
Vector2f dirFromSideAngle(float rotation, float side_angle) {
    return Vector2f.fromPolar(1.0f,
        fullAngleFromSideAngle(rotation, side_angle));
}

//return the index of the angle in "angles" which is closest to "angle"
//all units in degrees, return values is always an index into angles
uint pickNearestAngle(int[] angles, int iangle) {
    //pick best angle (what's nearer)
    uint closest;
    float angle = iangle/180.0f*math.PI;
    float cur = float.max;
    foreach (int i, int x; angles) {
        auto d = angleDistance(angle,x/180.0f*math.PI);
        if (d < cur) {
            cur = d;
            closest = i;
        }
    }
    return closest;
}

///place nrc relative to prc (trivial, but has to be somewhere)
///  nrc = rectangle of the object to be placed
///  g = the direction and distance (exactly one component of this should be 0)
///  g_align = alignment of the placement line (in the direction orthogonal to
///     g); 0.0 = left/top aligned, 1.0 = right/bottom, 0.5 is centered
///  g_align2 = alignment of nrc along the placement line, similar to g_align
///  returns the offset to the new position
Vector2i placeRelative(Rect2i nrc, Rect2i prc, Vector2i g, float g_align = 0.5f,
    float g_align2 = 0.5f)
{
    Vector2i b1, b2;
    b1.x = g.x > 0 ? prc.p2.x : prc.p1.x;
    b2.x = g.x > 0 ? prc.p1.x : prc.p2.x;
    b1.y = g.y > 0 ? prc.p2.y : prc.p1.y;
    b2.y = g.y > 0 ? prc.p1.y : prc.p2.y;
    Vector2i pdist = g;
    if (g.x < 0) pdist -= nrc.size.X;
    if (g.y < 0) pdist -= nrc.size.Y;
    if (g.x > 0) pdist += prc.size.X;
    if (g.y > 0) pdist += prc.size.Y;
    Vector2i al = toVector2i(toVector2f(prc.size)*g_align
        - toVector2f(nrc.size)*g_align2);
    if (g.x == 0) al.y = 0;
    if (g.y == 0) al.x = 0;
    pdist += al;
    return pdist;
}
