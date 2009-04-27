///md = multicast delegate
module utils.md;

//import utils.misc;
import arr = tango.core.Array;

//broadcast an event to all registered delegates
//earlier registered delegates are called first
struct MDelegate(T...) {
    alias void delegate(T) DelegateType;

    mixin DelegateCommon!(DelegateType, T);

    void call(T args) {
        foreach (cb; mDelegates) {
            cb(args);
        }
    }

    void opCall(T args) {
        call(args);
    }
}

//registered delegates return a bool, that indicates if the event was handled,
//and if the next event handlers should be called. return values:
// - false: event wasn't handled, call the next event handler (delegate)
// - true: event was handled, call() returns, other event handlers are ignored
//earlier registered delegates have higher priority and are called first
//(xxx: optionally provide reverse behaviour?)
struct ChainDelegate(T...) {
    alias bool delegate(T) DelegateType;

    mixin DelegateCommon!(DelegateType, T);

    bool call(T args) {
        foreach (cb; mDelegates) {
            if (cb(args))
                return true;
        }
        return false;
    }

    bool opCall(T args) {
        return call(args);
    }
}

//to avoid code duplication in MDelegate and ChainDelegate
//even though I hate mixins, I hate code duplication even more!
template DelegateCommon(DT, Args...) {
    alias Args DelegateArgs;

    private {
        DT[] mDelegates;
    }

    void add(DT callback) {
        assert(!!callback);
        remove(callback); //avoid duplicates
        mDelegates ~= callback;
    }

    //callback doesn't need to be added before
    void remove(DT callback) {
        arr.remove(mDelegates, callback);
    }

    void clear() {
        mDelegates = null;
    }

    //tooth-decaying syntactic sugar for C++ minions
    void opCatAssign(DT callback) {
        add(callback);
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
