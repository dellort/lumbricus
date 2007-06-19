module utils.queue;

//a little funny Queue class, because Phobos doesn't have one (argh)
class Queue(T) {
    private T[] mItems;

    void push(T item) {
        mItems ~= item;
    }

    //throws exception if empty
    T pop() {
        if (empty)
            throw new Exception("Queue.pop: Queue is empty!");
        T res = mItems[0];
        mItems = mItems[1..$];
        return res;
    }

    bool empty() {
        return mItems.length == 0;
    }

    void clear() {
        mItems = null;
    }
}

