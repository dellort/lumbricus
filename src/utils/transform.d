module utils.transform;

import math = tango.math.Math;
import utils.vector2;

//2x2 matrix + translation vector
//(cheaper and saner than a 3x3 matrix with 3rd row for translation)
struct Transform2f {
    //2D matrix
    //  | a11 a12 |
    //  | a21 a22 |
    float a11 = 1.0f, a12 = 0.0f;
    float a21 = 0.0f, a22 = 1.0f;
    //translation part
    Vector2f t;

    //2D rotation+scale matrix
    static Transform2f RotateScale(float rotate, Vector2f scale) {
        Transform2f ret;
        //from utils.vector2.Vector2.rotated()
        ret.a11 = math.cos(rotate);
        ret.a21 = math.sin(rotate);
        ret.a12 = -ret.a21;
        ret.a22 = ret.a11;
        ret.a11 *= scale.x;
        ret.a21 *= scale.y;
        ret.a12 *= scale.x;
        ret.a22 *= scale.y;
        return ret;
    }

    void translate(T)(Vector2!(T) tr) {
        t.x += a11 * tr.x + a12 * tr.y;
        t.y += a21 * tr.x + a22 * tr.y;
    }

    void translateX(float tr_x) {
        t.x += a11 * tr_x;// + a12 * 0;
        t.y += a21 * tr_x;// + a22 * 0;
    }

    void mirror(bool x, bool y) {
        if (x) {
            a11 = -a11;
            a21 = -a21;
        }
        if (y) {
            a12 = -a12;
            a22 = -a22;
        }
    }

    Vector2f transform(Vector2f p) {
        Vector2f r;
        r.x = a11*p.x + a12*p.y + t.x;
        r.y = a21*p.x + a22*p.y + t.y;
        return r;
    }
}
