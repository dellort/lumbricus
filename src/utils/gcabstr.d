module utils.gcabstr;

import tango.core.Memory;

static if (!is(tango.core.Memory.GCStats)) {
    struct GCStats
    {
        size_t poolsize;        // total size of pool
        size_t usedsize;        // bytes allocated
        size_t freeblocks;      // number of blocks marked FREE
        size_t freelistsize;    // total of memory on free lists
        size_t pageblocks;      // number of blocks marked PAGE
    }

    extern (C) GCStats gc_stats();

    GCStats getStats() {
        return gc_stats();
    }
} else {
    public alias GC.GCStats GCStats;

    GCStats getStats() {
        return GC.stats();
    }
}
