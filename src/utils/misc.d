module utils.misc;

import cmath = std.c.math;
import math = std.math;
import str = std.string;
import intr = std.intrinsic;
import utf = std.utf;

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

/// Return the index of the character following the character at "index"
int charNext(char[] s, int index) {
    assert(index >= 0 && index <= s.length);
    if (index == s.length)
        return s.length;
    return index + utf.stride(s, index);
}
/// Return the index of the character prepending the character at "index"
int charPrev(char[] s, int index) {
    assert(index >= 0 && index <= s.length);
    debug if (index < s.length) {
        //assert valid UTF-8 character (stride will throw an exception)
        utf.stride(s, index);
    }
    //you just had to find the first char starting with 0b0... or 0b11...
    //but this was most simple
    foreach_reverse(int byteindex, dchar c; s[0..index]) {
        return byteindex;
    }
    return 0;
}

//aaIfIn(a,b) works like a[b], but if !(a in b), return null
public V aaIfIn(K, V)(V[K] aa, K key) {
    V* pv = key in aa;
    return pv ? *pv : null;
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

//cf. arrayFindNextPred()()
//iterate(arr, w): find the element following w in arr
T arrayFindFollowingPred(T)(T[] arr, T w, T function(T[] arr, T w) iterate,
    bool delegate(T t) pred)
{
    T first = iterate(arr, w);
    if (!first)
        return null;
    auto c = first;
    do {
        if (pred(c))
            return c;
        if (c is w)
            break;
        c = iterate(arr, c);
    } while (c !is first);
    return null;
}

//searches for next element with pred(element)==true, wraps around, if w is null
//start search with first element, if no element found, return null
//if w is the only valid element, return w
T arrayFindNextPred(T)(T[] arr, T w, bool delegate(T t) pred) {
    return arrayFindFollowingPred(arr, w, &arrayFindNext!(T), pred);
}
//for the preceeding element
T arrayFindPrevPred(T)(T[] arr, T w, bool delegate(T t) pred) {
    return arrayFindFollowingPred(arr, w, &arrayFindPrev!(T), pred);
}

int arraySearch(T)(T[] arr, T value, int def = -1) {
    foreach (int i, T item; arr) {
        if (item == value)
            return i;
    }
    return def;
}

//remove first occurence of value from arr; the order is not changed
//(thus not O(1), but stuff is simply copied)
void arrayRemove(T)(inout T[] arr, T value) {
    for (int n = 0; n < arr.length; n++) {
        if (arr[n] is value) {
            //array slice assigment disallows overlapping copy, so don't use it
            for (int i = n; i < arr.length-1; i++) {
                arr[i] = arr[i+1];
            }
            arr = arr[0..$-1];
            return;
        }
    }
    assert(false, "element not in array!");
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
