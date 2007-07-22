module utils.misc;

import cmath = std.c.math;
import math = std.math;
import str = std.string;
import intr = std.intrinsic;
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

/// Cast object in t to type T, and throw exception if not possible.
/// Only return null if t was already null.
T castStrict(T : Object)(Object t) {
    T res = cast(T)t;
    if (t && !res) {
        throw new Exception("could not cast");
    }
    return res;
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

///Ensure leading slash, replace '\' by '/', remove trailing '/' and
///remove double '/'
///An empty path will be left untouched
char[] fixRelativePath(char[] p) {
    //replace '\' by '/'
    p = str.replace(p,"\\","/");
    //add leading /
    if (p.length > 0 && p[0] != '/')
        p = "/" ~ p;
    //remove trailing /
    if (p.length > 0 && p[$-1] == '/')
        p = p[0..$-1];
    //kill double /
    //XXX todo: kill multiple /
    p = str.replace(p,"//","/");
    return p;
}

char[] getFilePath(char[] fullname)
    out (result)
    {
        assert(result.length <= fullname.length);
    }
    body
    {
        uint i;

        for (i = fullname.length; i > 0; i--)
        {
            if (fullname[i - 1] == '\\')
                break;
            if (fullname[i - 1] == '/')
                break;
        }
        return fullname[0 .. i];
    }
