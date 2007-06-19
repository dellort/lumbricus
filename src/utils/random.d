module utils.random;
import rand = std.random;

//copyright: search for mt19937ar.c (BSD)
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

//[0.0f, 1.0f]
float random() {
    return genrand_real1();
}

//-1.0f..1.0f
float random2() {
    return (random()-0.5f)*2.0f;
}

//[from, to)
int random(int from, int to) {
    return rand.rand() % (to-from) + from;
}

T randRange(T)(T min, T max) {
    auto r = rand.rand();
    return cast(T)(min + (max-min+1)*genrand_real2());
}
