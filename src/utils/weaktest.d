//stupid test for utils.weaklist; don't compile it into the project
module utils.weaktest;
import std.thread;
import std.random;
import std.stdio;
import std.string;
import utils.weaklist;
import gc = std.gc;

int N() {
    static int n;
    int f;
    synchronized {
        f = n++;
    }
    return f;
}

class Test {
    uint[20] data;
    uint n;

    this() {
        n = N();
        foreach (int index, inout x; data) {
            x = n+index;
        }
        gList.add(this);
    }

    invariant() {
        foreach (int index, inout x; data) {
            assert(x is (n+index));
        }
    }

    ~this() {
        gList.remove(this, true);
    }

    char[] toString() {
        return format("t_%s", n);
    }
}

WeakList!(Test) gList;

int dotest(void* arg) {
    Test[10] arr;
    for (;;) {
        foreach (inout Test t; arr) {
            if (rand() % 2) {
                t = new Test();
            }
            if (t) {
                assert(t);
            }
        }
        //Thread.getThis.yield();
        gList.cleanup();
        if (!(rand() % 5))
            gc.fullCollect();
        if (!(rand() % 10000)) {
            auto x = gList.list;
            auto l = x.length;
            foreach (t; x) assert(t);
            delete x;
            x = null; //prevent "leak"
            writefln("%#x: %s", cast(void*)Thread.getThis(), l);
        }
    }
    return 0;
}

void main() {
    gList = new typeof(gList);
    for (int n = 0; n < 6; n++) {
        auto t = new Thread(&dotest, null);
        writefln("spawn %#x", cast(void*)t);
        t.start();
    }
    for (;;) {
        Thread.getThis.pause();
        //std.gc.fullCollect();
    }
}
