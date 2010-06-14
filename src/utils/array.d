module utils.array;
import utils.misc;
import cstdlib = tango.stdc.stdlib;
import array = tango.core.Array;

//aaIfIn(a,b) works like a[b], but if !(a in b), return null
public V aaIfIn(K, V)(V[K] aa, K key) {
    V* pv = key in aa;
    return pv ? *pv : null;
}

//duplicate an AA (why doesn't D provide this?)
public V[K] aaDup(K, V)(V[K] aa) {
    V[K] res;
    foreach (K k, V v; aa) {
        res[k] = v;
    }
    return res;
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
        throw new CustomException("arrayRemoveUnordered: element not in array");
    }
    if (arr.length >= 1) {
        arr[index] = arr[$-1];
    }
    arr = arr[0..$-1];
}

///insert count entries at index
/// old_array = new_array[0..index] ~ new_array[index+count..$]
///the new entries new_array[index..index+count] are uninitialized
void arrayInsertN(T)(inout T[] arr, uint index, uint count = 1) {
    assert(index <= arr.length);
    arr.length = arr.length + count;
    for (uint n = arr.length; n > index + count; n--) {
        arr[n-1] = arr[n-count-1];
    }
}

unittest {
    int[] a = [1,2,3,6,7,8];
    arrayInsertN(a, 3, 2);
    a[3] = 4;
    a[4] = 5;
    assert(a == [1,2,3,4,5,6,7,8]);
    a.length = 0;
    arrayInsertN(a, 0, 1);
    assert(a.length == 1);
}

///new_arr = old_arr[0..index] ~ old_arr[index+count..$]
void arrayRemoveN(T)(inout T[] arr, uint index, uint count = 1) {
    assert(index <= arr.length);
    assert(index + count <= arr.length);
    for (uint n = index; n < arr.length - count; n++) {
        arr[n] = arr[n+count];
    }
    arr.length = arr.length - count;
}

unittest {
    int[] a = [1,2,3,4,5,6,7,8];
    arrayRemoveN(a, 3, 2);
    assert(a == [1,2,3,6,7,8]);
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
    }

    void setArray(T[] arr) {
        mArray = arr;
        mLength = mArray.length;
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
        if (mLength > mArray.length) {
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

    //so that mLength <= capacity; don't initialize new items
    private void do_grow() {
        if (mLength <= mArray.length)
            return;
        //make larger exponantially
        auto capacity = max(16, mArray.length);
        while (capacity < mLength)
            capacity *= 2;
        //xxx: maybe free previous array if the runtime reallocated it?
        mArray.length = capacity;
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
//         plus slices/pointers into the array get invalid when length changes
final class BigArray(T) {
    private {
        T[] mData;
    }

    this(size_t initial_length = 0) {
        length = initial_length;
    }

    //keep in mind that this invalidates all slices (and pointers) to the array
    //setting length to 0 is guaranteed to free everything
    void length(size_t newlen) {
        if (newlen == mData.length)
            return;
        //xxx: overflow check for newlen*T.sizeof would be nice
        size_t sz = newlen*T.sizeof;
        assert(!(sz == 0 && mData.ptr is null)); //weird realloc special case
        void* res = cstdlib.realloc(mData.ptr, sz);
        if (!res && newlen != 0) {
            //reallocation failed; realloc() leaves memory untouched
            //xxx: throw out OutOfMemoryException instead?
            throw new Exception(myformat("Out of memory when allocating {} "
                "bytes.", sz));
        }
        auto oldlen = mData.length;
        mData = (cast(T*)res)[0..newlen];
        //init memory like native D arrays are initialized
        if (newlen > oldlen) {
            T[] ndata = mData[oldlen..newlen];
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
    T[] opSlice(uint low, uint high) {
        return mData[low..high];
    }
    void opSliceAssign(T v) {
        T[] slice = opSlice();
        slice[] = v;
    }
    T* ptr() {
        return mData.ptr;
    }
}

//source: http://people.cs.ubc.ca/~harrison/Java/MergeSortAlgorithm.java.html
//modified to make it a stable sorting algorithm
void mergeSort(T, Pred2E = array.IsLess!(T))(T[] a, Pred2E pred = Pred2E.init) {
    if (a.length < 2) {
        return;
    }
    int mid = (a.length-1) / 2;

    /*
     *  Partition the list into two lists and sort them recursively
     */
    mergeSort(a[0..mid+1], pred);
    mergeSort(a[mid+1..$], pred);

    /*
     *  Merge the two sorted lists
     */
    int lo = 0;
    int end_lo = mid;
    int start_hi = mid + 1;
    while ((lo <= end_lo) && (start_hi < a.length)) {
        if (pred(a[start_hi], a[lo])) {
            /*
             *  a[lo] >= a[start_hi]
             *  The next element comes from the second list,
             *  move the a[start_hi] element into the next
             *  position and shuffle all the other elements up.
             */
            T item = a[start_hi];
            for (int k = start_hi - 1; k >= lo; k--) {
                a[k+1] = a[k];
            }
            a[lo] = item;
            end_lo++;
            start_hi++;
        }
        lo++;
    }
}

unittest {
    int[] t = [2, 6, 3, 5, 7, 7, 4];
    t.mergeSort();
    assert(t == [2, 3, 4, 5, 6, 7, 7]);
    float[] t2 = [1.2f, 2.3f, 2.1f, 0.6f, 1.8f, 1.7f];
    mergeSort(t2, (float a, float b){ return (cast(int)a) < (cast(int)b); });
    assert(t2 == [0.6f, 1.2f, 1.8f, 1.7f, 2.3f, 2.1f]);
}
