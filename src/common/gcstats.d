module common.gcstats;

public import std.gc;

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
}
