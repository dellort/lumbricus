module utils.vector2;

import str = std.string;
import math = std.math;

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

    public T quad_length() {
        return x*x + y*y;
    }
    
    public T length() {
        return cast(T)math.sqrt(cast(real)(x*x + y*y));
    }
    
    public Vector2 normal() {
        T len = length();
        return Vector2(cast(T)(x/len), cast(T)(y/len));
    }
    
    public Vector2 orthogonal() {
        return Vector2(y, -x);
    }
    
    public void length(T new_length) {
        //xxx might be numerically stupid
        *this = normal*new_length;
    }
    
    public void add_length(T add)
    {
        *this = normal*(length+add);
    }
    
    public Vector2 rotated(T angle_rads) {
        T mat11 = cast(T)math.cos(angle_rads);
        T mat12 = cast(T)math.sin(angle_rads);
        T mat21 = -mat12;
        T mat22 = mat11;
        
        return Vector2(mat11*x + mat12*y, mat21*x + mat22*y);
    }

    public char[] toString() {
        return "("~str.toString(x1)~", "~str.toString(x2)~")";
    }
}

public alias Vector2!(int) Vector2i;
