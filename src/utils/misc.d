module utils.misc;

import rand = std.random;
import cmath = std.c.math;
import math = std.math;

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

//return distance of two angles in radians
float angleDistance(float a, float b) {
    auto r = math.abs(realmod(a, math.PI*2) - realmod(b, math.PI*2));
    if (r > math.PI) {
        r = math.PI*2 - r;
    }
    return r;
}

/* generates a random number on [0,1]-real-interval */
double genrand_real1()
{
    return rand.rand()*(1.0/4294967295.0);
    /* divided by 2^32-1 */
}

/* generates a random number on [0,1)-real-interval */
double genrand_real2()
{
    return rand.rand()*(1.0/4294967296.0);
    /* divided by 2^32 */
}

T randRange(T)(T min, T max) {
    auto r = rand.rand();
    return cast(T)(min + (max-min+1)*genrand_real2());
}

uint log2(uint value)
out (res) {
    assert(value >= (1<<res));
    assert(value < (1<<(res+1)));
}
body {
    uint res = uint.max;
    uint tmp = value;
    while (tmp) {
            tmp >>= 1;
            res++;
    }
    return res;
}

//a little funny Queue class, because Phobos doesn't have one (argh)
class Queue(T) {
    private T[] mItems;

    void push(T item) {
        mItems ~= item;
    }

    //throws exception if empty
    T pop() {
        if (empty)
            throw new Exception("Queue.pop: Queue is empty!");
        T res = mItems[0];
        mItems = mItems[1..$];
        return res;
    }

    bool empty() {
        return mItems.length == 0;
    }

    void clear() {
        mItems = null;
    }
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

//a small factory template
//ConstructorArgs is a tuple which is passed as constructor arguments
class Factory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private constructorCallback[char[]] mConstructors;

    //can't be named register(), because... hm? DMD is just borken.
    void registerByDelegate(char[] name, constructorCallback create) {
        if (name in mConstructors) {
            throw new Exception("oh noes! class already exists: " ~ name);
        }
        mConstructors[name] = create;
    }

    //register by type
    //call it like: Factory!(YourInterface).register!(YourClass)("name")
    void register(X)(char[] name) {
        static assert( is (X : T));

        //argh, using a function literal here crashes DMD *g*
        T inst(ConstructorArgs x) {
            return new X(x);
        }

        registerByDelegate(name, &inst);
    }

    //register using the unqualified class name
    //named registerX() because overloading doesn't work
    void registerX(X)() {
        register!(X)(X.stringof);
    }

    T instantiate(char[] name, ConstructorArgs args) {
        auto del = name in mConstructors;
        if (!del) {
            throw new Exception("class '"~name~"' not found.");
        }
        return (*del)(args);
    }

    char[][] classes() {
        return mConstructors.keys;
    }
}

static class StaticFactory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private static constructorCallback[char[]] mConstructors;

    //can't be named register(), because... hm? DMD is just borken.
    static void registerByDelegate(char[] name, constructorCallback create) {
        if (name in mConstructors) {
            throw new Exception("oh noes! class already exists: " ~ name);
        }
        mConstructors[name] = create;
    }

    //register by type
    //call it like: Factory!(YourInterface).register!(YourClass)("name")
    static void register(X)(char[] name) {
        static assert( is (X : T));

        //argh, using a function literal here crashes DMD *g*
        T inst(ConstructorArgs x) {
            return new X(x);
        }

        registerByDelegate(name, &inst);
    }

    //register using the unqualified class name
    //named registerX() because overloading doesn't work
    static void registerX(X)() {
        register!(X)(X.stringof);
    }

    static T instantiate(char[] name, ConstructorArgs args) {
        auto del = name in mConstructors;
        if (!del) {
            throw new Exception("class '"~name~"' not found.");
        }
        return (*del)(args);
    }

    static char[][] classes() {
        return mConstructors.keys;
    }
}
