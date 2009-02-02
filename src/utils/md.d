///md = multicast delegate
///or rather, some sick mixture of that and slots&signals
//xxx: maybe cleanup this mixed-up terminology
module utils.md;

import utils.array;
import utils.misc;

template MDCallbackType(DelegateArgs...) {
    alias void delegate(DelegateArgs) MDCallbackType;
}

/// Interface to the MulticastDelegate, which just includes the add()-method
/// By this, access to the MulticastDelegate is blocked except for registering
/// delegates or for removing them (through the MDSlot object).
interface MDSubscriber(DelegateArgs...) {
    MDSlot!(DelegateArgs) add(MDCallbackType!(DelegateArgs) dg);
}

class MDGenericSlot {
    abstract void disconnect();
    abstract void clear();
    abstract bool connected();
    abstract void connected(bool set);
}

/// Subscription to a MulticastDelegate (obtained by the add()-method), which
/// can be used to deregistrate the delegate.
class MDSlot(DelegateArgs...) : MDGenericSlot {
    alias MDCallbackType!(DelegateArgs) DelegateType;

    private {
        DelegateType mCallback;
        MulticastDelegate!(DelegateArgs) mMD;
        bool mConnected;
    }

    /// Can be used to create a slot (specific to a delegate), which can be
    /// connected to a MulticastDelegate later.
    this(DelegateType dg) {
        mCallback = dg;
    }

    /// Connect the delegate covered by this slot to the MulticastDelegate "to".
    void connect(MDSubscriber!(DelegateArgs) to) {
        disconnect();
        if (to) {
            //messy, could need cleanup, but who cares
            mMD = castStrict!(typeof(mMD))(cast(Object)to);
            mMD.connect(this);
        }
    }

    /// Disconnect the slot.
    /// Can be reconnected again by doing "this.connected = true;"
    void disconnect() {
        if (mMD && mConnected)
            mMD.disconnect(this);
        assert(!mConnected);
    }

    ///disconnect and set references to null (to allow GC to free memory)
    void clear() {
        disconnect();
        assert(!mConnected);
        mMD = null; mCallback = null;
    }

    ///if a delegate through this slot is registered
    bool connected() {
        return mConnected;
    }

    ///can be set freely if connect() was called once after initilization/clear
    ///i.e. can be used to temporarely disconnect it and reconnect it again
    void connected(bool set) {
        if (set == mConnected)
            return;
        if (set) {
            connect(mMD);
        } else {
            disconnect();
        }
    }
}

/// Multicasts function calls to several subscribers (like in signals & slots).
/// Takes argument types as tuple; return type is fixed to void.
/// This is a class because that's more convenient in order to avoid problems
///   with structs-as-properties (changes to a struct-property value are lost).
class MulticastDelegate(DelegateArgs...) : MDSubscriber!(DelegateArgs) {
    alias MDSubscriber!(DelegateArgs) Subscriber;
    alias MDSlot!(DelegateArgs) Slot;
    alias MDCallbackType!(DelegateArgs) DelegateType;

    private Slot[] mDelegates;

    void call(DelegateArgs a) {
        //xxx: maybe be a bit careful with the iteration, because calling the
        //  delegates could trigger this.add() calls
        foreach (d; mDelegates) {
            d.mCallback(a);
        }
    }

    void clear() {
        while (mDelegates.length) {
            disconnect(mDelegates[0]);
        }
    }

    void opCatAssign(DelegateType dg) {
        add(dg);
    }

    Slot add(DelegateType dg) {
        Slot s = new Slot(dg);
        connect(s);
        return s;
    }

    void connect(Slot s) {
        if (s) {
            s.disconnect();
            s.mMD = this;
            s.mConnected = true;
            mDelegates ~= s;
        }
    }

    //O(n) due to that stupid array
    void disconnect(Slot s) {
        if (s && s.connected) {
            arrayRemoveUnordered(mDelegates, s);
            s.mConnected = false;
        }
    }
}

//argh no unittest-import
debug import tango.io.Stdout;

unittest {
    //simple stupid base functionality
    bool b1, b2;
    void test1() { b1 = !b1; } //test callbacks
    void test2() { b2 = !b2; }
    auto simple = new MulticastDelegate!();
    //s1/s2 are equally connected to test1/2, just different methods are used
    auto s1 = simple.add(&test1);
    auto s2 = new simple.Slot(&test2);
    s2.connect(simple);
    assert(!(b1 | b2)); simple.call(); assert(b1 & b2);
    s1.disconnect();
    simple.call();
    assert(b1 && !b2);

    debug Stdout.formatln("md.d unittest: passed.");
}
