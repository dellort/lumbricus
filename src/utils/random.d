module utils.random;

public import utils.rndkiss;

//not thread safe
public Random rngShared;

//borrowed/adapted from
//http://dsource.org/projects/tango/browser/trunk/tango/math/random/Kiss.d#L104

version (Win32) {
    private extern(Windows) int QueryPerformanceCounter (ulong *);
    private uint os_timestamp() {
        ulong s;
        QueryPerformanceCounter (&s);
        return s;
    }
} else version (Posix) {
    private import tango.stdc.posix.sys.time;
    private uint os_timestamp() {
        //xxx: there's also tango.math.random.engines.URandom...?
        timeval tv;
        gettimeofday (&tv, null);
        return tv.tv_usec;
    }
} else {
    static assert(false, "add os_timestamp()");
}


uint generateRandomSeed() {
    uint some = os_timestamp();
    uint more = rngShared ? rngShared.next() : 0;
    return some ^ more;
}

static this() {
    rngShared = new Random(generateRandomSeed());
}
