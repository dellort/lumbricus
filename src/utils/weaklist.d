module utils.weaklist;

import tango.core.WeakRef : WeakRef;

///
///requires Tango patch: http://paste.dprogramming.com/dpfirs6q
class WeakList(Finalizer, T = Object) {
    private {
        static class Entry : WeakRef {
            this(Object r) { super(r); }
            bool do_finalize;
            Finalizer finalize;
            Entry next;

            //work around tango bug (fixed in tango trunk)
            bool cleared;
            Object myget() {
                if (cleared)
                    return null;
                return get();
            }
        }
        Entry mRoot;
    }

    this() {
    }

    void add(T obj, Finalizer freedata) {
        auto entry = new Entry(obj);
        entry.finalize = freedata;
        //insert into list
        entry.next = mRoot;
        mRoot = entry;
    }

    ///Remove a reference from the weak list; the "aref" is as in add().
    ///User can call this so that it won't be passed in cleanup()
    void remove(T aref) {
        if (!aref)
            return;
        Entry cur = mRoot;
        while (cur) {
            if (cur.myget() is aref) {
                cur.clear();
                cur.cleared = true;
                cur.do_finalize = false;
                break;
            }
            cur = cur.next;
        }
    }

    ///remove all entries from the list, and hand them to cleanup()
    void finalizeAll() {
        Entry cur = mRoot;
        while (cur) {
            if (cur.myget()) {
                cur.clear();
                cur.cleared = true;
                cur.do_finalize = true;
            }
            cur = cur.next;
        }
    }

    private Entry removeDeadEntries() {
        Entry kill;

        //move all dead entries to kill list
        Entry* pnext = &mRoot;
        while (*pnext) {
            Entry cur = *pnext;
            if (!cur.myget()) {
                //move from mRoot list to kill list
                *pnext = cur.next;
                cur.next = kill;
                kill = cur;
            } else {
                pnext = &cur.next;
            }
        }

        return kill;
    }

    /// returns list.length (for statistics, actual length can change anytime)
    /// only count live references
    int countRefs() {
        int n;
        auto cur = mRoot;
        while (cur) {
            if (cur.myget())
                n++;
            cur = cur.next;
        }
        return n;
    }

    /+
    static int globalWeakObjectsCount() {
        int count;
        foreach (g; gGraveyard) {
            count += g.countRefs();
        }
        return count;
    }
    +/

    ///call for each object to finalize
    void cleanup(void delegate(Finalizer data) deinit) {
        Entry cur = removeDeadEntries();
        while (cur) {
            assert (!cur.myget());
            if (cur.do_finalize) {
                deinit(cur.finalize);
            }
            Entry next = cur.next;
            delete cur;
            cur = next;
        }
    }

    void listAlive(void delegate(T d) cb) {
        Entry cur = mRoot;
        while (cur) {
            T r = cast(T)(cur.myget());
            if (r)
                cb(r);
            cur = cur.next;
        }
    }
}
