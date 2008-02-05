module utils.math;

public import utils.vector2;// : Vector2f;
import intr = std.intrinsic;
import math = std.math;

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

T realmod(T)(T a, T m) {
    T res = a % m;
    if (res < 0)
        res += m;
    return res;
}

uint log2(uint value)
out (res) {
    assert(value >= (1<<res));
    assert(value < (1<<(res+1)));
}
body {
    return intr.bsr(value);
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
