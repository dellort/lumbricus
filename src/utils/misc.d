module utils.misc;

import rand = std.random;

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

int randRange(int min, int max) {
    auto r = rand.rand();
    return cast(int)(min + (max-min+1)*genrand_real2());
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
