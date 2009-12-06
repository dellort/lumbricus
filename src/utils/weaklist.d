module utils.weaklist;

import cstdlib = tango.stdc.stdlib;
import memory = tango.core.Memory;


struct FinalizeBlock {
private:
    //as long as the containing object is alive, this WeakProxyObject is alive
    //when it's dead, the pointer value basically is garbage
    WeakProxyObject reverse_weakref;
    //this is needed because reverse_weakref might refer to a free'd object,
    //  and the GC may reuse free'd memory addresses
    //0 means it was removed from the weaklist
    size_t weak_id;
}

private class WeakProxyObject : Object {
private:
    //WeakList is never free'd, so calling this from a dtor is ok
    WeakListGeneric list;
    size_t weak_id;

    this() {
    }

    ~this() {
        if (list) {
            list.removeFromGC(weak_id);
            list = null;
        }
    }
}

//(non-templated parts of WeakList(T))
class WeakListGeneric {
    private {
        //list of pointers; an AA would be better, but when adding or removing
        //an object, the D GC must not be called
        //must be located in non-GC'd memory!
        //xxx: doesn't matter anymore; for now this is only because I don't like
        //  the idea of allocating GC memory from a finalizer (although that may
        //  work)
        Node* mRoot;

        struct Node {
            Node* next;
            //if this is 0, the Node is scheduled for finalization
            //  (to be removed and returned in popFinalize())
            size_t weak_id;
            //index into mFreeData
            size_t freedata_key;
            //if WeakList should return it in popFinalizers()
            bool do_finalize = true;
        }

        //for all weak_id
        size_t mUniqueIdAlloc = 1;

        //unique key for mFreeData
        size_t mFreeDataKeyAlloc = 1;

        //sorry, this stuff doesn't work if WeakList is GC free'd
        //prevent that to prevent undefined behavior
        static WeakListGeneric[] gGraveyard;
    }

    this() {
        gGraveyard ~= this;
    }

    private Node* node_alloc() {
        Node* res = cast(Node*)cstdlib.calloc(1, Node.sizeof);
        assert(!!res, "out of memory");
        *res = Node.init;
        return res;
    }

    private void node_free(Node* n) {
        cstdlib.free(n);
    }

    //protected from calls from other threads and especially be safe for
    //.remove() calls called from GC finalizers (=> disable GC)
    private void sync(void delegate() m) {
        //xxx not sure if the GC.disable() stuff is still needed (probably not)
        //  the case it protects is quite rare => hard to test
        //actually, threads can manually trigger GC runs, even if the GC is
        //  "disabled", so it's pointless, and I commented it
        //memory.GC.disable();
        synchronized(this) {
            m();
        }
        //memory.GC.enable();
    }

    ///Remove a reference from the weak list; the "aref" is as in add().
    ///User can call this so that it won't be returned by popFinalize()
    ///queue_finalizer: if true, the finalizer object will be returned by
    /// popFinalizers(); if false, just remove it silently (basically, it's
    /// whether you're expecting the machinery to free the data on its own when
    /// doing remove(), e.g. "remove(..., false); manualfree();")
    ///queue_finalizer never should be false if you don't have a reference on
    /// the tracked object (you will get race conditions whether the object is
    /// put in the finalization queue or not)
    void remove(FinalizeBlock* aref, bool queue_finalizer) {
        doRemove(aref.weak_id, queue_finalizer);
        //leave aref.reverse_weakref
    }

    //usually, this will be called from the GC (except if the user manually
    //  delete[]s the proxy object, which he shouldn't)
    private void removeFromGC(size_t weak_id) {
        doRemove(weak_id, true);
    }

    private void doRemove(size_t weak_id, bool queue_finalizer) {
        //user called remove() on uninitialized FinalizeBlock; let it pass
        if (weak_id == 0)
            return;
        //NOTE: it's fine if nothing is found:
        //  - the stupid user may have called remove() in ~this() of his object,
        //    which is okayish (although unneeded); then the proxy object would
        //    call doRemove() a second time
        //  - the user removed the finalizer manually, but WeakProxyObject is
        //    going to be GC'ed anyway (ignoring it is the simplest thing to do)
        //  - user called removeAll() before (removeAll() can't remove the
        //    proxy; so you have to ignore its finalizer event)
        sync({
            Node* cur = mRoot;
            while (cur) {
                if (cur.weak_id == weak_id) {
                    cur.weak_id = 0;
                    cur.do_finalize = queue_finalizer;
                    break;
                }
                cur = cur.next;
            }
        });
    }

    ///remove all entries from the list
    ///queue_finalizer: if true, removed items will land in popFinalize()
    void removeAll(bool queue_finalizer) {
        sync({
            Node* cur = mRoot;
            while (cur) {
                if (cur.weak_id != 0) {
                    cur.weak_id = 0;
                    cur.do_finalize = queue_finalizer;
                }
                cur = cur.next;
            }
        });
    }

    private Node* removeDeadEntries() {
        Node* kill;

        sync({
            //move all dead entries to kill list
            Node** pnext = &mRoot;
            while (*pnext) {
                Node* cur = *pnext;
                if (cur.weak_id == 0) {
                    //move from mRoot list to kill list
                    *pnext = cur.next;
                    cur.next = kill;
                    kill = cur;
                } else {
                    pnext = &cur.next;
                }
            }
        });

        return kill;
    }

    /// returns list.length (for statistics, actual length can change anytime)
    /// only count live references
    int countRefs() {
        int n;
        sync({
            auto cur = mRoot;
            while (cur) {
                if (cur.weak_id != 0)
                    n++;
                cur = cur.next;
            }
        });
        return n;
    }

    static int globalWeakObjectsCount() {
        int count;
        foreach (g; gGraveyard) {
            count += g.countRefs();
        }
        return count;
    }
}

///Simple support for weak pointers.
///This sucks so much, because neither Tango nor Phobos 1 or Phobos 2 support
/// weak pointers (as of now).
///The template parameter is the type of the finalizer data, which is always
/// managed by the GC; the finalizer data contains the stuff you actually want
/// to free if the weak pointer gets nullified.
///multithreading: don't do it; although the remove functions can be called from
/// anywhere (this is just because the GC can call from anywhere)
///
///NOTE: it is not possible to get a references to the actual tracked objects;
///      maybe you could, but I'm not sure if the current runtime allows to do
///      this in a race-condition free way (maybe not)
///
///T = type of the finalizer (NOT the class tracked by the weak pointer)
class WeakList(T = Object) : WeakListGeneric {
    private {
        //user data, which is needed to free stuff
        //this must live in real memory
        T[size_t] mFreeData;
    }

    /++
    How to use it:
        static gYourWeakList = new WeakList!(YourData);
        class YourData {
            void free() {
                //free resources
            }
        }
        class YourClass {
            FinalizeBlock bla;
            YourData data;

            this() {
                data = new YourData();
                gYourWeakList.add(&bla, data);
            }
        }
        //call this periodically
        void onFrame() {
            foreach (YourData d; gYourWeakList.popFinalizers()) {
                d.free();
            }
        }
    How it works:
        WeakList.add(&a, b) puts a hidden object into "a", which is used to
        keep track when the object containing "a" is collected (if the
        containing object, YourClass in the example, is collected, the hidden
        object is unreferenced and will be collected as well). The hidden object
        deals with the dirty weak pointers implementation, so that the user-
        code doesn't have to deal with it.
        If the object containing "a" is collected, "b" is queued for
        finalization. The next time the user calls popFinalizers(), "b" is
        returned (among other finalized objects). Which means you have to call
        popFinalizers() periodically to actually free stuff.
    If you don't call popFinalizers(), you have a memory leak.
    Must not be called from a finalizer.
    ++/
    void add(FinalizeBlock* aref, T freedata) {
        if (aref.reverse_weakref) {
            aref.reverse_weakref.list.remove(aref, false);
        } else {
            aref.reverse_weakref = new WeakProxyObject();
        }

        assert(!!aref.reverse_weakref);

        aref.weak_id = mUniqueIdAlloc++;
        aref.reverse_weakref.weak_id = aref.weak_id;
        aref.reverse_weakref.list = this;

        size_t key = mFreeDataKeyAlloc++;
        mFreeData[key] = freedata;

        Node* n = node_alloc();
        n.freedata_key = key;
        n.weak_id = aref.weak_id;

        sync({
            n.next = mRoot;
            mRoot = n;
        });
    }

    ///return the set of objects to finalize (e.g. the user uses the returned
    /// array items to actually call destructors on them)
    T[] popFinalizers() {
        Node* cur = removeDeadEntries();
        T[] items;

        while (cur) {
            assert(cur.weak_id == 0);

            if (cur.do_finalize) {
                items ~= mFreeData[cur.freedata_key];
            }

            mFreeData.remove(cur.freedata_key);

            Node* next = cur.next;
            node_free(cur);
            cur = next;
        }

        return items;
    }

    ///helper function, call popFinalizers() and run deinit on all objects
    /// returned by it
    void cleanup(void delegate(T data) deinit) {
        foreach (d; popFinalizers()) {
            deinit(d);
        }
    }

    ///list finalizers of all thought-to-be-alive objects
    ///(you can call popFinalizers() before this to exclude most dead objects,
    /// but asynchronity issues don't allow to exclude all dead objects; the GC
    /// could kick in at any moment)
    T[] list() {
        return mFreeData.values;
    }
}
