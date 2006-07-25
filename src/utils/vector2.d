module utils.vector2;

import std.string;

public struct Vector2(T) {
    T x1;
    T x2;

    alias x1 x;
    alias x2 y;

    public static Vector2 opCall(T x1, T x2) {
        Vector2 ret;
        ret.x1 = x1;
        ret.x2 = x2;
        return ret;
    }

    public Vector2 opAdd(Vector2 v) {
        return Vector2(x1+v.x1, x2+v.x2);
    }

    public Vector2 opSub(Vector2 v) {
        return Vector2(x1-v.x1, x2-v.x2);
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
    
    public Vector2 opNeg() {
        return Vector2(-x1, -x2);
    }

    public char[] toString() {
        return "("~std.string.toString(x1)~", "~std.string.toString(x2)~")";
    }
}

public alias Vector2!(int) Vector2i;
