module stdx.math;

version (Tango) {
    public import tango.math.Math;
    public import tango.math.IEEE;

    public alias isNaN isnan;

    real fmax(real x, real y) { return x > y ? x : y; }
    real fmin(real x, real y) { return x < y ? x : y; }
} else {
    public import std.math;
}
