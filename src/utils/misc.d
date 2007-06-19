module utils.misc;

import cmath = std.c.math;
import math = std.math;
import str = std.string;
import intr = std.intrinsic;

public T min(T)(T v1, T v2) {
    return v1<v2?v1:v2;
}

public T max(T)(T v1, T v2) {
    return v1<v2?v2:v1;
}

public void swap(T)(inout T a, inout T b) {
    T t = a;
    a = b;
    b = t;
}

float realmod(float a, float b) {
    return cmath.fmodf(cmath.fmodf(a, b) + b, b);
}

uint log2(uint value)
out (res) {
    assert(value >= (1<<res));
    assert(value < (1<<(res+1)));
}
body {
    return intr.bsr(value);
}

//return next after w, wraps around, if w==null, return first element, if any
//returns always w if arr == [T]
T arrayFindNext(T)(T[] arr, T w) {
    if (!arr)
        return null;

    int found = -1;
    foreach (int i, T c; arr) {
        if (w is c) {
            found = i;
            break;
        }
    }
    found = (found + 1) % arr.length;
    return arr[found];
}

//like arrayFindPrev, but backwards
//untested
T arrayFindPrev(T)(T[] arr, T w) {
    if (!arr)
        return null;

    int found = 0;
    foreach_reverse (int i, T c; arr) {
        if (w is c) {
            found = i;
            break;
        }
    }
    if (found == 0) {
        found = arr.length;
    }
    return arr[found - 1];
}

//searches for next element with pred(element)==true, wraps around, if w is null
//start search with first element, if no element found, return null
//if w is the only valid element, return w
T arrayFindNextPred(T)(T[] arr, T w, bool delegate(T t) pred) {
    T first = arrayFindNext(arr, w);
    if (!first)
        return null;
    auto c = first;
    do {
        if (pred(c))
            return c;
        if (c is w)
            break;
        c = arrayFindNext(arr, c);
    } while (c !is first);
    return null;
}

int arraySearch(T)(T[] arr, T value, int def = -1) {
    foreach (int i, T item; arr) {
        if (item == value)
            return i;
    }
    return def;
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
