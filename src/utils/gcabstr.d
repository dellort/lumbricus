module utils.gcabstr;

//xxx big hack: for some reason tango developers don't want to expose this
version(Tango) {
    struct GCStats
    {
        size_t poolsize;        // total size of pool
        size_t usedsize;        // bytes allocated
        size_t freeblocks;      // number of blocks marked FREE
        size_t freelistsize;    // total of memory on free lists
        size_t pageblocks;      // number of blocks marked PAGE
    }

    extern (C) GCStats gc_stats();

    void getStats(out GCStats stats) {
        stats = gc_stats();
    }

    import tango.core.Memory;

    void gcEnable() {
        GC.enable();
    }
    void gcDisable() {
        GC.disable();
    }
    void gcFullCollect() {
        GC.collect();
    }
} else {
    import gc = std.gc;
    public import gcstats;

    void getStats(out GCStats stats) {
        gc.getStats(stats);
    }

    void gcEnable() {
        gc.enable();
    }
    void gcDisable() {
        gc.disable();
    }
    void gcFullCollect() {
        gc.fullCollect();
    }
}
