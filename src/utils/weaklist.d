module utils.weaklist;

version (Tango) {
    import tango.stdc.stdlib : malloc, free;
} else {
    import std.c.stdlib : malloc, free;
}

import utils.gcabstr;

///Simple support for weakpointers.
///T should be a pointer-like type (pointers, objects, interfaces)
///Data can be a type, used for data transported between remove() and cleanup()
///xxx: the list doesn't handle deinitialization yet, so you can have a memory
///     leak (of C malloc() memory) if an object is collected by the GC, even
///     if there are still list entries
struct Dummy {
    //as default parameter for Data, stupid dmd complains when using void
}
class WeakList(T, Data = Dummy) {
    private {
        //list of pointers; an AA would be better, but when adding or removing
        //an object, the D GC must not be called
        //must be located in non-GC'd memory!
        Node* mRoot;
        Node* mKillList;

        struct Node {
            Node* next;
            T realref;
            Data data;
        }
    }

    //protected from calls from other threads and especially be safe for
    //.remove() calls called from GC finalizers (=> disable GC)
    private void sync(void delegate() m) {
        gcDisable();
        synchronized(this) {
            m();
        }
        gcEnable();
    }

    /// Add a pointer to the list. The pointer isn't GC-tracked. The caller is
    /// responsible to keep the pointer valid (i.e. should use .remove() to
    /// remove the pointer if the memory block got collected by the GC).
    ///xxx could use Object.notifyRegister(), but IMHO that's too unstable yet
    void add(T aref) {
        Node* n = cast(Node*)malloc(Node.sizeof);
        n.realref = aref;
        sync({
            n.next = mRoot;
            mRoot = n;
        });
    }

    /// Remove a reference from the list; do nothing if it isn't on the list.
    /// Can be called from an object destructor (aka finalizer), in this case
    ///   fromFinalizer must be true.
    /// If called from anywhere else, it must be false.
    void remove(T aref, bool fromFinalizer, Data data = Data.init) {
        auto code = {
            Node** pcur = &mRoot;
            bool fnd;
            while (*pcur) {
                Node* n = *pcur;
                if (n.realref is aref) {
                    //remove from list, add to kill list
                    *pcur = n.next;
                    n.next = mKillList;
                    mKillList = n;
                    n.data = data;
                    //free(n); //causes deadlocks :(
                    fnd = true;
                    break;
                }
                pcur = &n.next;
            }
            /+if (!fnd) {
                char[] s = "not found\n";
                write(1, s.ptr, s.length);
            }+/
        };

        if (fromFinalizer) {
            //xxx earlier comment was wrong; this is a race condition
            code();
        } else {
            sync(code);
        }
    }

    /// Remove all references.
    void clear() {
        sync({
            while (mRoot) {
                auto tmp = mRoot.next;
                mRoot.next = mKillList;
                mKillList = mRoot;
                mRoot = tmp;
            }
        });
    }

    /// returns list.length (for statistics, actual length can change anytime)
    int countRefs() {
        int n;
        sync({
            auto cur = mRoot;
            while (cur) {
                n++;
                cur = cur.next;
            }
        });
        return n;
    }

    /// Obtain the list of all objects in a safe way. This is slow!
    T[] list() {
        //NOTE: while the GC is enabled, the references must be contained in
        //  GC memory, so the GC will not collect the objects
        version (GcAlloc) {
            //allocates during GC is disabled, not sure if that works
            //at least it could interfere with locking libc functions
            static assert(false);
            T[] refs;
            sync({
                auto cur = mRoot;
                int n;
                while (cur) {
                    n++;
                    cur = cur.next;
                }
                refs.length = n;
                cur = mRoot;
                foreach (inout r; refs) {
                    r = cur.realref;
                    cur = cur.next;
                }
            });
            return refs;
        } else {
            //version which doesn't allocate memory from the GC while it is disabled
            for (;;) {
                bool ok = true;
                //first count the objects
                int n = countRefs();
                //then allocate an array and attempt to stuff all refs into it
                //the lock must (should?) be released during that, because we want
                //allocate memory from the GC (to guarantee that the GC keeps the
                //returned references valid, even if someone calls remove() on them)
                T[] refs = new T[n];
                sync({
                    auto cur = mRoot;
                    n = 0;
                    while (cur) {
                        if (n >= refs.length) {
                            //object count changed; try again
                            ok = false;
                            break;
                        }
                        refs[n] = cur.realref;
                        cur = cur.next;
                        n++;
                    }
                });
                if (ok) {
                    return refs[0..n];
                }
            }
        }
    }

    /// Actually remove dead objects.
    /// Can call the passed delegate (use it with remove())
    /// not needed anymore as soon as Walter makes his GC code more robust
    void cleanup(void delegate(Data data) deinit = null) {
        Node* list;
        sync({
            list = mKillList;
            mKillList = null;
        });
        while (list) {
            auto tmp = list;
            list = list.next;
            if (deinit)
                deinit(tmp.data);
            free(tmp);
        }
    }
}
