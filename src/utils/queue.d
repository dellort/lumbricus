module utils.queue;

import utils.array;

//a little funny Queue class, because Phobos doesn't have one (argh)
class Queue(T) {
    private T[] mItems;

    this () {
    }

    void push(T item) {
        mItems ~= item;
    }

    T pop() {
        assert(!empty);
        T res = mItems[0];
        arrayRemoveN(mItems, 0);
        return res;
    }

    //item that would be returned by pop
    T top() {
        assert(!empty);
        return mItems[0];
    }

    bool empty() {
        return mItems.length == 0;
    }

    void clear() {
        mItems.length = 0;
    }
}

