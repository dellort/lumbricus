module utils.array;
import utils.misc;
import cstdlib = tango.stdc.stdlib;

//aaIfIn(a,b) works like a[b], but if !(a in b), return null
public V aaIfIn(K, V)(V[K] aa, K key) {
    V* pv = key in aa;
    return pv ? *pv : null;
}

public K aaReverseLookup(K, V)(V[K] aa, V value, K def) {
    foreach (K k, V v; aa) {
        if (v == value)
            return k;
    }
    return def;
}

//duplicate an AA (why doesn't D provide this?)
public V[K] aaDup(K, V)(V[K] aa) {
    V[K] res;
    foreach (K k, V v; aa) {
        res[k] = v;
    }
    return res;
}

//useful for class[] -> interface[] conversion!
T_to[] arrayCastCopyImplicit(T_to, T_from)(T_from[] arr) {
    return arrayMap(arr, (T_from x) { T_to f = x; return f; });
}

//as you know it from your Haskell lessons
T_to[] arrayMap(T_from, T_to)(T_from[] arr, T_to delegate(T_from x) del) {
    T_to[] res;
    res.length = arr.length;
    for (int n = 0; n < res.length; n++) {
        res[n] = del(arr[n]);
    }
    return res;
}

T[] arrayFilter(T)(T[] arr, bool delegate(T x) pred) {
    T[] res;
    foreach (i; arr) {
        if (pred(i))
            res ~= i;
    }
    return res;
}

//return next after w, wraps around, if w==null, return first element, if any
//returns always w if arr == [T]
//shall work like w==null if w not in array
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

//find numeric highest entry in the array; prefers higher index for equal values
//returns -1 if arr.length is 0
int arrayFindHighest(T)(T[] arr) {
    T win_val;
    int win_index = -1;
    foreach (i, v; arr) {
        if (win_index < 0 || v >= win_val) {
            win_index = i;
            win_val = v;
        }
    }
    return win_index;
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

//like arrayRemove(), but order of array elements isn't kept -> faster
void arrayRemoveUnordered(T)(inout T[] arr, T value, bool allowFail = false) {
    auto index = arraySearch(arr, value);
    if (index < 0) {
        if (allowFail) return;
        throw new Exception("arrayRemoveUnordered: element not in array");
    }
    if (arr.length >= 1) {
        arr[index] = arr[$-1];
    }
    arr = arr[0..$-1];
}

///insert count entries at index
/// old_array = new_array[0..index] ~ new_array[index+count..$]
void arrayInsertN(T)(inout T[] arr, uint index, uint count) {
    //xxx make more efficient
    T[] tmp = arr[index..$].dup;
    arr.length = arr.length + count;
    arr ~= tmp;
}

///new_arr = old_arr[0..index] ~ old_arr[index+count..$]
void arrayRemoveN(T)(inout T[] arr, uint index, uint count) {
    //xxx move trailing elements only instead of building a new array
    //    (which, btw., would be the whole point of this function)
    arr = arr[0..index] ~ arr[index+count..$];
}

//return true when b is contained completely in a
//both arrays must be sorted!
bool arraySortedIsContained(T)(T[] a, T[] b) {
    int ia;
    outer: for (int ib = 0; ib < b.length; ib++) {
        while (ia < a.length) {
            if (b[ib] == a[ia])
                continue outer;
            ia++;
        }
        //not found
        return false;
    }
    return true;
}

unittest {
    assert(arraySortedIsContained([0,1,2,3,5,7], [1,2,5]));
    assert(!arraySortedIsContained([1,2,5], [0,1,2,3,5,7]));
    assert(arraySortedIsContained([1,2,5], [1,2,5]));
    assert(arraySortedIsContained([1,2,5], cast(int[])[]));
    assert(!arraySortedIsContained(cast(int[])[], [1,2,5]));
}


//for array appending - because using builtin functionality is slow
//(at least so they say)
//NOTE: instead of Appender!(int) arr; foreach(x;arr) do foreach(x;arr[])
struct Appender(T) {
    private {
        T[] mArray;
        size_t mLength;
        size_t mCapacity;
    }

    T opIndex(size_t idx) {
        assert(idx < mLength);
        return mArray[idx];
    }
    void opIndexAssign(T value, size_t idx) {
        assert(idx < mLength);
        mArray[idx] = value;
    }
    void opCatAssign(T value) {
        mLength++;
        if (mLength > mCapacity) {
            do_grow();
        }
        mArray[mLength-1] = value;
    }
    void opCatAssign(T[] value) {
        mLength += value.length;
        do_grow();
        mArray[mLength-value.length .. mLength] = value;
    }
    T[] opSlice() {
        return mArray[0..mLength];
    }
    void opSliceAssign(T v) {
        T[] slice = opSlice();
        slice[] = v;
    }
    //if you're bored, add
    //opSlice(size_t a, size_t b)
    //opSliceAssign(T v, size_t a, size_t b)
    T[] dup() {
        return opSlice().dup;
    }

    size_t length() {
        return mLength;
    }
    void length(size_t nlen) {
        if (nlen <= mLength) {
            mLength = nlen;
        } else {
            size_t oldlen = mLength;
            size_t oldcap = mArray.length;
            mLength = nlen;
            do_grow();
            //init the stuff that wasn't already initialized by the GC
            mArray[oldlen .. oldcap] = T.init;
        }
    }

    //so that mLength <= mCapacity; don't initialize new items
    private void do_grow() {
        if (mLength <= mCapacity)
            return;
        //make larger exponantially
        mCapacity = max(16, mCapacity);
        while (mCapacity < mLength)
            mCapacity *= 2;
        mArray.length = mCapacity;
    }
}

unittest {
    Appender!(int) arr;
    arr ~= 1;
    arr ~= 2;
    assert(arr[] == [1,2]);
    arr.length = 1;
    assert(arr[] == [1]);
    arr.length = 3;
    assert(arr[] == [1,0,0]);
}


//arrays allocated with C's malloc/free
//because the D GC really really sucks with big arrays
//Warning: pointers/slices to the actual array are not GC tracked
final class BigArray(T) {
    private {
        T[] mData;
    }

    this(size_t initial_length) {
        length = initial_length;
    }

    //keep in mind that this invalidates all slices (and pointers) to the array
    void length(size_t newlen) {
        //xxx: overflow check for newlen*T.sizeof would be nice
        size_t sz = newlen*T.sizeof;
        void* res = cstdlib.realloc(mData.ptr, sz);
        if (!res && newlen != 0) {
            //reallocation failed; realloc() leaves memory untouched
            //xxx: throw out of memroy exception instead?
            assert(false, "out of memory");
        }
        mData = (cast(T*)res)[0..newlen];
        //init memory like native D arrays are initialized
        if (newlen > mData.length) {
            T[] ndata = mData[mData.length..newlen];
            ndata[] = T.init;
        }
    }
    size_t length() {
        return mData.length;
    }

    void free() {
        length = 0;
    }

    ~this() {
        free();
        assert(mData is null);
    }

    T opIndex(size_t idx) {
        return mData[idx];
    }
    void opIndexAssign(T value, size_t idx) {
        mData[idx] = value;
    }
    T[] opSlice() {
        return mData;
    }
    void opSliceAssign(T v) {
        T[] slice = opSlice();
        slice[] = v;
    }
}
