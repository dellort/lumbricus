module utils.random;

public import utils.rndkiss;

private Random rngShared;

uint rand() {
    return rngShared.next();
}

void rand_seed(uint s) {
    rngShared.seed(s);
}

/* generates a random number on [0,1]-real-interval */
double genrand_real1()
{
    return rngShared.nextDouble();
}
/* generates a random number on [0,1)-real-interval */
double genrand_real2()
{
    return rngShared.nextDouble2();
}

//[0.0f, 1.0f]
float random() {
    return rngShared.nextDouble();
}

//-1.0f..1.0f
float random2() {
    return rngShared.nextDouble3();
}

//[from, to)
int random(int from, int to) {
    return rngShared.next(from, to);
}

T randRange(T)(T min, T max) {
    return rngShared.nextRange(min, max);
}

static this() {
    rngShared = new Random();
}
