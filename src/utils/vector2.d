module utils.vector2;

import str = std.string;
import math = std.math;

public struct Vector2(T) {
    T x1 = 0;
    T x2 = 0;

    alias x1 x;
    alias x2 y;

    public static Vector2 opCall(T x1, T x2) {
        Vector2 ret;
        ret.x1 = x1;
        ret.x2 = x2;
        return ret;
    }
    public static Vector2 opCall(T both) {
        return Vector2(both, both);
    }

    public Vector2 X() {
        return Vector2(x1,0);
    }
    public Vector2 Y() {
        return Vector2(0,x2);
    }

    public Vector2 opAdd(Vector2 v) {
        return Vector2(x1+v.x1, x2+v.x2);
    }
    public void opAddAssign(Vector2 v) {
        x1 += v.x1;
        x2 += v.x2;
    }

    public Vector2 opSub(Vector2 v) {
        return Vector2(x1-v.x1, x2-v.x2);
    }
    public void opSubAssign(Vector2 v) {
        x1 -= v.x1;
        x2 -= v.x2;
    }

    public T opMul(Vector2 v) {
        return x1*v.x1 + x2*v.x2;
    }

    public Vector2 opMul(T scalar) {
        return Vector2(x1*scalar, x2*scalar);
    }
    public Vector2 opMul_r(T scalar) {
        return opMul(scalar);
    }
    public void opMulAssign(T scalar) {
        x1 *= scalar;
        x2 *= scalar;
    }

    public Vector2 mulEntries(Vector2 v) {
        return Vector2(x1*v.x1, x2*v.x2);
    }

    public Vector2 opDiv(T scalar) {
        return Vector2(x1/scalar, x2/scalar);
    }

    public Vector2 opNeg() {
        return Vector2(-x1, -x2);
    }

    public T quad_length() {
        return x*x + y*y;
    }

    public T length() {
        return cast(T)math.sqrt(cast(real)(x*x + y*y));
    }

    //doesn't make any sense with T==int
    public Vector2 normal() {
        T len = length();
        return Vector2(cast(T)(x/len), cast(T)(y/len));
    }

    public Vector2 orthogonal() {
        return Vector2(y, -x);
    }

    public void length(T new_length) {
        //xxx might be numerically stupid (especially with integers...)
        *this = normal*new_length;
    }

    public void add_length(T add) {
        *this = normal*(length+add);
    }

    //given a line by start+t*dir, return a point that's on the line and that's
    //nearest to this (the projection of this on the line)
    public Vector2 project_on(Vector2 start, Vector2 dir) {
        Vector2 n = dir.orthogonal.normal;
        T t = (start - *this) * n;
        return *this+n*t;
    }

    //get distance of this to the (infinite) line, see project_on
    public T distance_from(Vector2 start, Vector2 dir) {
        return (*this - project_on(start, dir)).length;
    }

    //if point is inside the rect formed by pos and size
    //the border of that rect is exclusive
    public bool isInside(Vector2 pos, Vector2 size) {
        return x >= pos.x && y >= pos.y
            && x < pos.x + size.x && y < pos.y + size.y;
    }

    public Vector2 rotated(T angle_rads) {
        T mat11 = cast(T)math.cos(angle_rads);
        T mat12 = cast(T)math.sin(angle_rads);
        T mat21 = -mat12;
        T mat22 = mat11;

        return Vector2(mat11*x + mat12*y, mat21*x + mat22*y);
    }

    public void swap(inout Vector2 other) {
        Vector2 tmp = other;
        other = *this;
        *this = tmp;
    }

    public char[] toString() {
        return "("~str.toString(x1)~", "~str.toString(x2)~")";
    }
}

public alias Vector2!(int) Vector2i;
public alias Vector2!(float) Vector2f;

public Vector2f toVector2f(Vector2i v) {
    Vector2f res;
    res.x1 = v.x1;
    res.x2 = v.x2;
    return res;
}

public Vector2i toVector2i(Vector2f v) {
    Vector2i res;
    res.x1 = cast(int)(v.x1+0.5f);
    res.x2 = cast(int)(v.x2+0.5f);
    return res;
}
