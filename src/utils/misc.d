module utils.misc;

import str = std.string;
import utf = std.utf;

T min(T)(T v1, T v2) {
    return v1<v2?v1:v2;
}

T max(T)(T v1, T v2) {
    return v1<v2?v2:v1;
}

void swap(T)(inout T a, inout T b) {
    T t = a;
    a = b;
    b = t;
}

//execute code count-times
void times(int count, void delegate() code) {
    while (count--)
        code();
}

//clamp to closed range, i.e. val is adjusted so that it fits into [low, high]
T clampRangeC(T)(T val, T low, T high) {
    if (val < low) {
        return low;
    } else if (val > high) {
        return high;
    } else {
        return val;
    }
}

//clamp to open range, [low, high), makes sense for integers only
T clampRangeO(T)(T val, T low, T high) {
    if (val > high)
        val = high - 1;
    return (val < low) ? low : val;
}

/// Cast object in t to type T, and throw exception if not possible.
/// Only return null if t was already null.
T castStrict(T : Object)(Object t) {
    T res = cast(T)t;
    if (t && !res) {
        throw new Exception("could not cast");
    }
    return res;
}

/// convert a function-ptr to a delegate (thanks to downs, it's his code)
R delegate(T) toDelegate(R, T...)(R function(T) fn) {
    struct holder {
        typeof(fn) _fn;
        R call(T t) {
            static if (is(R==void))
                _fn(t);
            else
                return _fn(t);
        }
    }
    auto res = new holder;
    res._fn = fn;
    return &res.call;
}
