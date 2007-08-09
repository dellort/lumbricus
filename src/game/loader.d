module game.loader;

alias bool delegate() LoadChunkDg;

class Loader {
    private LoadChunkDg[] mChunks;
    private int mCurChunk;
    private bool mFullyLoaded;
    void delegate(Loader sender) onFinish;
    void delegate(Loader sender) onUnload;

    void registerChunk(LoadChunkDg chunkLoader) {
        mChunks ~= chunkLoader;
    }

    int chunkCount() {
        return mChunks.length;
    }

    int currentChunk() {
        return mCurChunk;
    }

    //overridden method is supposed to call this atfer unloading done
    //NOTE: you can't reload it again using this Loader instance
    void unload() {
        if (onUnload) {
            onUnload(this);
        }
    }

    //call until fullyLoaded() returns true
    void loadStep() {
        if (fullyLoaded())
            return;
        if (doLoad(mCurChunk)) {
            mCurChunk++;
        }
        if (mCurChunk >= mChunks.length) {
            doFinish();
        }
    }

    bool fullyLoaded() {
        return mFullyLoaded;
    }

    private bool doLoad(int chunkId) {
        assert(chunkId >= 0 && chunkId < mChunks.length);
        bool ret = mChunks[chunkId]();
        return ret;
    }

    private void doFinish() {
        if (onFinish)
            onFinish(this);
        mFullyLoaded = true;
    }
}
