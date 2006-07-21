import std.string;

public struct Vector2_Template(T) {
    T x1;
    T x2;

    alias x1 x;
    alias x2 y;

    public static Vector2_Template opCall(T x1, T x2) {
        Vector2_Template ret;
        ret.x1 = x1;
        ret.x2 = x2;
        return ret;
    }

    public Vector2_Template opAdd(Vector2_Template v) {
        return Vector2_Template(x1+v.x1, x2+v.x2);
    }

    public Vector2_Template opSub(Vector2_Template v) {
        return Vector2_Template(v.x1-x1, v.x2-x2);
    }

    public char[] toString() {
        return "("~std.string.toString(x1)~", "~std.string.toString(x2)~")";
    }
}

public alias Vector2_Template!(int) Vector2;
