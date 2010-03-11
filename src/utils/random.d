module utils.random;

public import utils.rndkiss;

public Random rngShared;

static this() {
    rngShared = new Random();
}
