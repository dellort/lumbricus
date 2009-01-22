module utils.vector2;

import str = stdx.string;
import math = stdx.math;


public struct Vector2(T) {
    T x1 = 0;
    T x2 = 0;

    alias x1 x;
    alias x2 y;

    //unit vectors (not to confuse with .X and .Y properties)
    const Vector2 cX = {1,0};
    const Vector2 cY = {0,1};

    //can be used for static initialization, i.e. as Vector2!(float).nan
    static if (is(T == float) || is(T == double)) {
        const Vector2 nan = {T.nan, T.nan};
    }

    public static Vector2 opCall(T x1, T x2) {
        Vector2 ret;
        ret.x1 = x1;
        ret.x2 = x2;
        return ret;
    }
    public static Vector2 opCall(T both) {
        return Vector2(both, both);
    }
    public static Vector2 opCall() {
        Vector2 v;
        return v;
    }

    public static Vector2 fromPolar(T length, T angle) {
        return Vector2(cast(T)math.cos(angle*1.0), cast(T)math.sin(angle*1.0))*length;
    }

    public Vector2 X() {
        return Vector2(x1,0);
    }
    public Vector2 Y() {
        return Vector2(0,x2);
    }

    //for floats only
    public bool isNaN() {
         return x != x || y != y;
    }

    public T opIndex(uint index) {
        //is that kosher?
        return ((&x1)[0..2])[index];
    }
    public void opIndexAssign(T val, uint index) {
        ((&x1)[0..2])[index] = val;
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
    //the same thing
    public Vector2 opXor(Vector2 v) {
        return mulEntries(v);
    }

    public Vector2 opDiv(T scalar) {
        return Vector2(x1/scalar, x2/scalar);
    }

    //entry-wise division (like mulEntries)
    public Vector2 opDiv(Vector2 v) {
        return Vector2(x1/v.x1, x2/v.x2);
    }

    public Vector2 opMod(T scalar) {
        return Vector2(x1%scalar, x2%scalar);
    }

    //entry-wise modulo
    public Vector2 opMod(Vector2 v) {
        return Vector2(x1%v.x1, x2%v.x2);
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

    public Vector2 abs() {
        return Vector2(cast(T)math.abs(x), cast(T)math.abs(y));
    }

    public Vector2 clipAbsEntries(Vector2 clip) {
        return Vector2((math.abs(x) > clip.x)?cast(T)math.copysign(clip.x, x):x,
            (math.abs(y) > clip.y)?cast(T)math.copysign(clip.y, y):y);
    }

    //return vector with entry-wise maxima of this and other
    public Vector2 max(Vector2 other) {
        return Vector2(x>other.x ? x : other.x, y>other.y ? y : other.y);
    }
    public Vector2 min(Vector2 other) {
        return Vector2(x<other.x ? x : other.x, y<other.y ? y : other.y);
    }

    public void length(T new_length) {
        //xxx might be numerically stupid (especially with integers...)
        *this = normal*new_length;
    }

    //if "this" is a normal, return angle to X axis in radians
    //useful for T==float only
    public T toAngle() {
        return cast(T)math.atan2(y,x);
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

    //like project_on(), but given a line by start+t*dir, return the point
    //that's nearest to the line, but for which 0 <= t <= 1 is true
    public Vector2 project_on_clipped(Vector2 start, Vector2 dir) {
        auto pt = project_on(start, dir);
        //sorry, I'm stupid, do you know a better way?
        auto t = pt.get_line_index(start, dir);
        if (t < 0)
            t = 0;
        else if (t > 1)
            t = 1;
        return start+dir*t;
    }

    public T distance_from_clipped(Vector2 start, Vector2 dir) {
        return (*this - project_on_clipped(start, dir)).length;
    }

    //return t so that: start+t*dir = this
    T get_line_index(Vector2 start, Vector2 dir) {
        return ((*this - start) * dir) / dir.quad_length;
    }

    //return the projected component of this on the vector other
    Vector2 project_vector(Vector2 other) {
        T len = other.length;
        return (*this * other)/(len * len) * other;
    }

    //if point is inside the rect formed by pos and size
    //the border of that rect is exclusive
    public bool isInside(Vector2 pos, Vector2 size) {
        return x >= pos.x && y >= pos.y
            && x < pos.x + size.x && y < pos.y + size.y;
    }

    public Vector2 rotated(T angle_rads) {
        T mat11 = cast(T)math.cos(angle_rads*1.0);
        T mat12 = cast(T)math.sin(angle_rads*1.0);
        T mat21 = -mat12;
        T mat22 = mat11;

        return Vector2(mat11*x + mat12*y, mat21*x + mat22*y);
    }

    public void swap(inout Vector2 other) {
        Vector2 tmp = other;
        other = *this;
        *this = tmp;
    }

    //don't ask
    public T sum() {
        return x1 + x2;
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
    res.x1 = cast(int)(v.x1<0?v.x1-0.5f:v.x1+0.5f);
    res.x2 = cast(int)(v.x2<0?v.x2-0.5f:v.x2+0.5f);
    return res;
}
