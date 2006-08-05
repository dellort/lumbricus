module utils.math;
public import utils.vector2;// : Vector2f;

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