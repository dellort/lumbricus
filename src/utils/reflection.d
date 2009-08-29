//doing all those things which D/Phobos should provide us
//Reflection? More like BLOATflection!
module utils.reflection;

public import utils.reflect.arraytype;
public import utils.reflect.classdef;
public import utils.reflect.dgtype;
public import utils.reflect.safeptr;
public import utils.reflect.structtype;
public import utils.reflect.type;
public import utils.reflect.types;
public import utils.reflect.refctor;

import utils.misc;

/++++
Documentation lol for creating reflectionable classes:

The class must have this ctor:
    class Foo {
        this(ReflectCtor c) {
        }
    }
This will be called to create a dummy object and for reflection-based creation
of "empty" classes (used by serialization mechanism when deserializing). The
dummy object is used by the serialization mechanism to read the init values of
members and to call special methods (see Methods!()).

All non-static non-const member variables (including private ones) will be
exposed to reflection, using tupleof.

Methods must be declared manually:
    class Foo {
        ...
        mixin Methods!("method1", "method2");
        void method1() {}
        int method2(char[] a, int b) {}
    }
You need this only if you want to actually expose the methods to reflection.
Serialization needs this to serialize delegates pointing to a method.
There can be only one Methods-mixin. It creates a hidden method; the existance
of this method is checked with is(), and if it exists, it's called when the
dummy object is created.

- transient members
- on deserialization



++++/

//use this like this:
//  class SomeClass { mixin Methods!("method1", "method2", "method3"); }
//this will generate a static method named _register_methods(), which will be
//automagically called when the method is registered with serialization
//
//NOTE about overloaded methods: it seems dmd picks a random method (the first?)
//  when doing &functionname. I don't think we can automatically get all
//  functions (D2 has __traits, which probably allows this), but you can do
//  this: mixin("cast(" ~ sig ~ ")&me." ~ X[i]);
//            (yes that cast really changes the address/function)
//  where sig is e.g. "void function(int)" (simply the signature of a delegate
//  to the method, just as function type)
//  one could add the sig to the parameter string of the mixin, and then CTFE-
//  parse it, so if you need it add it... (have fun.)
//  oh, and be warned that if the signature is wrong, dmd will pick the first
//  function again and reinterpret-cast it to that function type! bad.
template Methods(X...) {
    static assert(is(typeof(this) == class));

    static void _register_methods(typeof(this) me, Types t) {
        //NOTE: the loop is executed at compile time, and each element in the
        //  X tuple is expected to be a char[] and is interpreted as a method
        //  name
        foreach (int i, _; X) {
            auto fn = mixin("&me." ~ X[i]);
            static assert(is(typeof(fn) == delegate));
            t.registerMethod!(typeof(this), typeof(fn))(me, fn, X[i]);
        }
    }
}

//ok, here's the same, but with a single string as parameter, that is expected
//  to contain a | separated list of method names
//mixin Methods2!("method1|method2|method3");
template Methods2(char[] X) {

    static void _register_methods(typeof(this) me, Types t) {
        static class Foo { //namespace hack xD
            public import utils.string : ctfe_split;
            public import utils.misc : Repeat;
        }
        const arr = Foo.ctfe_split(X, '|');
        foreach (int i, _; Foo.Repeat!(arr.length)) {
            auto fn = mixin("&me." ~ arr[i]);
            static assert(is(typeof(fn) == delegate));
            t.registerMethod!(typeof(this), typeof(fn))(me, fn, arr[i]);
        }
    }

}

//might as well give up hating on mixins and add this...
//PS: doesn't work with sub classes, somehow
template Serializable() {
    this(ReflectCtor c) {
        static if (is(T S == super)) {
            static if (!is(S[0] == Object)) {
                //if this fails, "someone" forgot a Serializable in the super
                //class
                super(c);
            }
        }
    }
}

//-------
debug:

import utils.strparser;

/+ ??? gives conflicts, wtf dmd?
enum X {
    xa,
    xb,
}

struct S {
    Test1 a;
    int b = 2;
    Test2 c;
}

class Test1 {
    int a = 1;
    int b = 2;
    char c = 'p';
    short[] d = [3,4,5];
    X e;
    Test2 f;
    S g;

    void foo() {
    }

    public this() {
    }

    public this(ReflectCtor ct) {
    }
}

class Test2 {
    int a = 1;
    float b = 2.45;
    Test1[] c;

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

class Test3 : Test1 {
    ushort a = 1;
    char[] b = "hullo";
    float[3] c = [0.3, 0.5, 0.7];

    public this(ReflectCtor ct) {
    }

    public this() {
    }
}

void not_main() {
    Types t = new Types();
    Class c = t.registerClass!(Test1)();
    Test1 x = new Test1();
    x.g.c = new Test2();
    x.g.c.c ~= x;
    x.g.c.c ~= new Test3();
    t.registerClass!(Test3)();
    debugDumpTypeInfos(t);
    debugDumpClassGraph(t, x);
}
+/

void debugDumpTypeInfos(Types t) {
    foreach (Type type; t.allTypes()) {
        Trace.formatln("{}", type);
        if (auto rt = cast(StructuredType)type) {
            if (auto cl = rt.klass()) {
                Trace.formatln("  structured type '{}', known members:", cl.name());
                foreach (ClassElement e; cl.elements()) {
                    if (auto m = cast(ClassMember)e) {
                        Trace.formatln("  - {} @ {} : {}", m.name(), m.offset(),
                            m.type());
                    } else if (auto m = cast(ClassMethod)e) {
                        Trace.formatln("  - {}() @ {:x#} : {}", m.name(),
                            m.address(), m.type());
                    }
                }
            }
        }
    }
}

void debugDumpClassGraph(Types t, Object x) {
    char[][TypeInfo] unknown;
    SafePtr px = t.ptrOf(x);
    bool[void*] done;
    SafePtr[] items = [px];
    done[null] = true;
    assert (null in done);
    while (items.length) {
        SafePtr cur = items[0];
        assert (cur.ptr !is null);
        items = items[1..$];
        char[] sp2str(SafePtr sp) {
            char[] s = "?";
            auto b = sp.box();
            if (b.type() in gBoxUnParsers) {
                s = boxToString(b);
            } else if (auto r = cast(ReferenceType)sp.type) {
                s = "? " ~ myformat("0x{:x}", sp.realptr());
            } else {
                s = "? " ~ sp.type.toString();
            }
            return s;
        }
        void check(SafePtr pm) {
            if (cast(StructuredType)pm.type || cast(ArrayType)pm.type) {
                void* rptr = pm.realptr();
                if (!(rptr in done)) {
                    items ~= pm;
                    done[rptr] = true;
                }
            }
        }
        if (auto st = cast(StructuredType)cur.type) {
            void* tmp;
            TypeInfo orgtype = cur.type.typeInfo;
            assert (!!orgtype);
            if (cast(ReferenceType)cur.type)
                cur = cur.mostSpecificClass(&tmp, true);
            if (cur.type is null) {
                if (orgtype in unknown)
                    continue;
                char[] info = "unencountered";
                if (auto tic = cast(TypeInfo_Class)orgtype) {
                    if (cur.ptr) {
                        void** p = cast(void**)cur.ptr;
                        Object o = cast(Object)*p;
                        info ~= " [ci: " ~ o.classinfo.name ~ "]";
                    }
                }
                unknown[orgtype] = info;
                Trace.formatln("unknown class");
                continue;
            }
            Trace.formatln("{} {} {:x8#}:", cast(StructType)st ? "struct" : "class",
                cur.type, cur.ptr);
            Class xc = castStrict!(StructuredType)(cur.type).klass();
            if (!xc) {
                unknown[cur.type.typeInfo] = "no info";
                Trace.formatln("  no info");
                continue;
            }
            while (xc) {
                cur.type = xc.type(); //xxx unclean
                foreach (ClassElement e; xc.elements()) {
                    if (auto m = cast(ClassMember)e) {
                        SafePtr pm = m.get(cur);
                        Trace.formatln("  {} = ({:x8#}) '{}'", m.name(), pm.ptr, sp2str(pm));
                        check(pm);
                    }
                }
                xc = xc.superClass();
            }
        } else if (auto art = cast(ArrayType)cur.type) {
            Trace.formatln("array {} len={:d} {:x8#}:", cur.type, art.getArray(cur).length,
                cur.ptr);
            Trace.format("    [");
            ArrayType.Array arr = art.getArray(cur);
            for (int i = 0; i < arr.length; i++) {
                if (i != 0)
                    Trace.format(", ");
                Trace.format("{}", (sp2str(arr.get(i))));
                check(arr.get(i));
            }
            Trace.formatln("]");
        }
    }
    Trace.formatln("unknown types:");
    foreach (TypeInfo k, char[] v; unknown) {
        char[] more = v;
        if (auto tic = cast(TypeInfo_Class)k) {
            more ~= " (" ~ tic.info.name ~ ")";
        }
        Trace.formatln("'{}': {}", k, more);
    }
    Trace.formatln("done.");
}

/+
This is what I call "dmd tupleof-enum bug":

Source:

import tango.io.Stdout;

enum X {
  bla
}

class Test {
   int a;
   X b;
}

void main() {
   Test t = new Test();
   Stdout.formatln(t.tupleof.stringof);
   foreach (int i, x; t.tupleof) {
       Stdout.formatln(t.tupleof[i].stringof);
   }
}

Output:
    tuple((t.a),(t.b))
    t.a
    int

The third line should be "t.b".
Newer dmd versions output the type of the enum instead of "int" or "t.b".
Status: doesn't work with v1.037

bug report: http://d.puremagic.com/issues/show_bug.cgi?id=2881

+/
