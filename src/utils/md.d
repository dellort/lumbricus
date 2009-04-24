///md = multicast delegate
module utils.md;

//import utils.misc;
import arr = tango.core.Array;

struct MDelegate(T...) {
    alias T DelegateArgs;
    alias void delegate(DelegateArgs) DelegateType;

    private {
        DelegateType[] mDelegates;
    }

    void add(DelegateType callback) {
        assert(!!callback);
        remove(callback); //avoid duplicates
        mDelegates ~= callback;
    }

    //callback doesn't need to be added before
    void remove(DelegateType callback) {
        arr.remove(mDelegates, callback);
    }

    void clear() {
        mDelegates = null;
    }

    void call(DelegateArgs args) {
        foreach (cb; mDelegates) {
            cb(args);
        }
    }

    //tooth-decaying syntactic sugar for C++ minions
    void opCatAssign(DelegateType callback) {
        add(callback);
    }
    void opCall(DelegateArgs args) {
        call(args);
    }
}

/+
idea for code that needs to mass-add/mass-remove callbacks to different
multicast delegates:

struct MassRemoval {
    void delegate() [] stuff;
    void add(T...)(ref MDelegate!(T) dest, MDelegate!(T).DelegateType cb) {
        -- D 1 doesn't support real closures, this won't work this way
        stuff ~= () { dest.remove(cb); }
        dest.add(cb);
    }
    void removeAll() {
        foreach (x; stuff) { x(); }
    }
}

with this, removing the callbacks wouldn't be as annoying.
+/
