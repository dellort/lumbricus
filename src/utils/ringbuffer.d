module utils.ringbuffer;

import utils.misc;

//a circular buffer with a fixed size, using an array
//supports "scrolling" by setting an offset for iteration
class RingBuffer(T) {
    private {
        T[] mBuffer;
        //index into buffer pointing to next empty entry
        int mIndex;
        //number of valid entries
        int mLength;
        //iteration offset
        int mOffset;
    }

    this(uint bufferSize) {
        assert(bufferSize > 0);
        mBuffer.length = bufferSize;
    }

    //add an entry; if the buffer is full, overwrites the oldest element
    void put(ref T value) {
        T* ne = put();
        *ne = value;
    }

    //like above, but returns a pointer to the new entry (to fill with data)
    //the entry is not cleared and may contain old data
    T* put() {
        T* ret = &mBuffer[mIndex];
        mIndex = (mIndex + 1) % mBuffer.length;
        mLength++;
        if (mLength > mBuffer.length)
            mLength = mBuffer.length;
        return ret;
    }

    void clear() {
        mIndex = 0;
        mLength = 0;
        mOffset = 0;
        mBuffer[] = T.init;
    }

    //set iteration offset: skip offset elements at the start of the iteration
    //returns the actual offset that was set
    int setOffset(int offset) {
        if (!mLength) {
            return 0;
        }
        mOffset = clampRangeC(offset, 0, cast(int)mLength-1);
        return mOffset;
    }
    void addOffset(int delta) {
        setOffset(mOffset + delta);
    }

    //start at oldest element, iterate to newest
    int opApply(scope int delegate(ref T value) del) {
        int result;
        if (!mLength) {
            //empty buffer
            return 0;
        }
        int idx = (mIndex - mLength + mOffset + mBuffer.length)
            % mBuffer.length;
        do {
            result = del(mBuffer[idx]);
            if (result)
                break;
            idx = (idx + 1) % mBuffer.length;
        } while (idx != mIndex);
        return result;
    }

    //start at newest element, iterate to oldest
    int opApplyReverse(scope int delegate(ref T value) del) {
        int result;
        if (!mLength) {
            //empty buffer
            return 0;
        }
        int idx = mIndex - 1 - mOffset;
        //index of the last valid entry (== mBackLogIdx if buffer full)
        int lastValid = (mIndex - mLength + mBuffer.length)
            % mBuffer.length;
        do {
            if (idx < 0)
                idx += mBuffer.length;
            result = del(mBuffer[idx]);
            if (result || idx == lastValid)
                break;
            idx--;
        } while (true);
        return result;
    }
}
