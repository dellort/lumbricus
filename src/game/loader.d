module game.loader;

alias bool delegate() LoadChunkDg;

class Loader {
    private LoadChunkDg[] mChunks;
    bool fullyLoaded;
    void delegate(Loader sender) onFinish;

    protected void registerChunk(LoadChunkDg chunkLoader) {
        mChunks ~= chunkLoader;
    }

    int chunkCount() {
        return mChunks.length;
    }

    bool load(int chunkId) {
        fullyLoaded = false;
        assert(chunkId >= 0 && chunkId < mChunks.length);
        bool ret = mChunks[chunkId]();
        return ret;
    }

    void finished() {
        if (onFinish)
            onFinish(this);
        fullyLoaded = true;
    }
}
