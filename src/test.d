module test;

import tango.io.Stdout;
import tango.text.convert.Layout;
import str = utils.string;
import utils.misc;
import tango.core.Tuple : Tuple;
import tango.text.Util : delimiters;
import utils.mytrace;
import strparser = utils.strparser;
import utils.configfile;
import tango.core.Traits : isIntegerType, isRealType, isAssocArrayType;
import utils.reflection;
import md = minid.api;
import md_bind = minid.bind;

debug import tango.core.stacktrace.TraceExceptions;
debug import tracer = utils.mytrace; //some stack tracing stuff for Linux

//Wrapper which uses our reflection to enable method calls from MiniD -> D
//derived from Jarett's example code
/+
further ideas:
- use integer indices to map name -> methods (and let minid do the lookup)
- cache object wrappers, instead of creating them on each push
+/
class MinidReflectWrapper {
static:
    private {
        const cMDWrapperMethod = "wrapper_opMethod";

        Types mTypes;
        BindClass[ClassInfo] mClasses;
        //registered ones; marshalling is a compile time thing (at least here),
        //and if you didn't add your type here, the wrapper will raise an error
        //note that de/marshallers for objects are not included here
        Marshaller[Type] mMarshallers;
        Demarshaller[Type] mDemarshallers;

        class BindClass {
            BindMethod[char[]] methods;
        }
        class BindMethod {
            ClassMethod member;
            Demarshaller[] demarshall_params;
            //null for void
            Marshaller marshall_return;
        }
    }

    //Marshaller: push data on minid stack
    alias void function(md.MDThread*, SafePtr data) Marshaller;

    //Demarshaller: read data from minid stack (using that slot) and write to
    //data
    alias void function(md.MDThread*, int slot, SafePtr data) Demarshaller;

    //ctor lol
    void init(Types reflection_base, md.MDThread* t) {
        mTypes = reflection_base;

        md.newFunction(t, &methodHandler, "opMethod");
        md.setRegistryVar(t, cMDWrapperMethod);

        //annoying, but can't do this at compiletime, unless the bindings are
        //generated at compiletime too
        addSimpleMarshallers!(int, char[]);
    }

    void addSimpleMarshallers(T...)() {
        foreach (int idx, _; T) {
            addSimpleMarshaller!(T[idx])();
        }
    }

    //marshallers that use superPush()
    //note that if T is a complex type that contain object members, stuff breaks
    //  => no arrays or structs that reference objects
    //  (possible solution: steal the code from superPush() and always use our
    //  own push to handle objects)
    //xxx no, just need to deal with complex types at runtime
    //    but for now...
    void addSimpleMarshaller(T)() {
        Type t = mTypes.getType!(T)();
        bool a = !!(t in mMarshallers);
        bool b = !!(t in mDemarshallers);
        assert(a == b); //wut, only one registered?
        if (a && b)
            return; //already registered
        //xxx: interfaces?
        static if (is(T == class)) {
            static assert(false, "objects use a different mechanism, doofus");
        } else {
            //xxx superGet fails at compiletime, so I didn't use it
            //    yeah, compile time duck typing is a great idea!
            mMarshallers[t] = function void(md.MDThread* th, SafePtr p) {
                //md_bind.superPush(th, p.read!(T)());
                T val = p.read!(T)();
                static if (is(T == int)) {
                    md.pushInt(th, val);
                } else static if (is(T == char[])) {
                    md.pushString(th, val);
                } else {
                    static assert(false, "lol");
                }
            };
            mDemarshallers[t] = function void(md.MDThread* th, int slot,
                SafePtr p)
            {
                //p.write!(T)(md_bind.superGet!(T)(th, slot));
                T val;
                static if (is(T == int)) {
                    val = md.getInt(th, slot);
                } else static if (is(T == char[])) {
                    //about that .dup... superGet does it too, and there's
                    //probably no safe way to avoid it
                    val = md.getString(th, slot).dup;
                } else {
                    static assert(false, "lol");
                }
                p.write!(T)(val);
            };
        }
    }

    //objects: D -> MiniD
    private void marshall_wrapper(md.MDThread* t, SafePtr p) {
        push(t, p.toObject());
    }

    //objects: MiniD -> D
    private void demarshall_wrapper(md.MDThread* t, int slot, SafePtr p) {
        //table object as generated in push() is expected on slot
        md.field(t, slot, "obj", true);
        Object o = md.getNativeObj(t, -1);
        md.pop(t, 1);
        if (!p.castAndAssignObject(o))
            throw new Exception("could not cast: "~o.classinfo.name~ " to "
                ~p.type.toString());
    }

    Marshaller get_marshaller(Type t) {
        if (t is mTypes.getType!(void)())
            return null;
        if (cast(ReferenceType)t)
            return &marshall_wrapper;
        if (auto m = t in mMarshallers)
            return *m;
        assert(false, "missing marshaller: "~t.toString());
    }
    //excercice for the reader: remove code duplication with above
    Demarshaller get_demarshaller(Type t) {
        if (t is mTypes.getType!(void)())
            return null;
        if (cast(ReferenceType)t)
            return &demarshall_wrapper;
        if (auto m = t in mDemarshallers)
            return *m;
        assert(false, "missing demarshaller: "~t.toString());
    }

    private BindClass initClass(ClassInfo cls) {
        assert(!(cls in mClasses));
        //Trace.formatln(">{}<", cls.name);
        Class c = mTypes.findClass(cls);
        if (!c)
            throw new Exception("class not reflected: "~cls.name);
        auto bc = new BindClass();
        while (c) {
            foreach (ClassMethod m; c.methods()) {
                //reflection stuff is quite confused about inheriting methods
                // and all that *shrug*
                assert(!(m.name() in bc.methods));
                auto bm = new BindMethod();
                bm.member = m;
                bc.methods[m.name()] = bm;
                DelegateType dgt = m.type();
                bm.marshall_return = get_marshaller(dgt.returnType());
                foreach (Type t; dgt.parameterTypes()) {
                    bm.demarshall_params ~= get_demarshaller(t);
                }
            }
            c = c.superClass();
        }
        bc.methods.rehash;
        mClasses[cls] = bc;
        return bc;
    }

    //covert a native object to minid (result is on minid's stack)
    md.word push(md.MDThread* t, Object o) {
        md.newTable(t);
        md.pushNativeObj(t, o);
        md.fielda(t, -2, "obj");
        md.getRegistryVar(t, cMDWrapperMethod);
        md.fielda(t, -2, "opMethod");
        return md.stackSize(t) - 1;
    }

    //return number of return values, or something similar
    static md.uword methodHandler(md.MDThread* t, md.uword numParams) {
        md.field(t, 0, "obj");
        Object obj = md.getNativeObj(t, -1);
        assert(obj !is null);

        //find method, which is just passed as string due to opMethod
        //memory for method string is volatile in some icky ways, see minid docs
        char[] method = md.getString(t, 1);
        auto pcls = obj.classinfo in mClasses;
        BindClass cls;
        if (!pcls) {
            cls = initClass(obj.classinfo);
        } else {
            cls = *pcls;
        }
        auto pm = method in cls.methods;
        if (!pm)
            throw new Exception("method not found: " ~ method);
        BindMethod m = *pm;

        int return_value = 0; //number of return values
        //that thing allocates and inits ret/args at "compile time", so it's a
        //  static array and doesn't require heap memory allocation xD
        m.member.invoke_dynamic_trampoline(obj,
            (SafePtr ret, SafePtr[] args, void delegate() call) {
                //demarshall
                if (args.length != numParams - 1)
                    throw new Exception(myformat("wrong param count from minid"
                        " script, call {} with {} params", m.member,
                        numParams-1));
                for (int i = 0; i < args.length; i++) {
                    Demarshaller d = m.demarshall_params[i];
                    d(t, i+2, args[i]);
                }
                //actual invocation here (uses ret/args)
                call();
                //marshall return value
                //if r is null, return type is void
                Marshaller r = m.marshall_return;
                if (r) {
                    return_value = 1;
                    r(t, ret);
                }
                //tracing for debugging
                auto mem = m.member;
                char[] f = myformat("{}(", mem.fullname());
                foreach (int idx, a; args) {
                    if (idx > 0)
                        f ~= ", ";
                    f ~= a.type.dataToString(a);
                }
                f ~= ") -> ";
                f ~= ret.type.dataToString(ret);
                Trace.formatln("MiniD->D call: {}.", f);
            }
        );
        return return_value;
    }
}


void md_test()
{
    Trace.formatln("MiniD test");

    md.MDVM vm;
    md.MDThread* t = md.openVM(&vm);
    md.loadStdlibs(t);

    MinidReflectWrapper.init(gTypes, t);

    md.loadString(t, `
        local a = vararg;
        local b = a.grizzle("lol this is minid", 145);
        a.grizzle(b, 56);
        a.a();
        //passing D objects back to D
        local c = a.foobar();
        a.b(c);
    `);

    md.pushNull(t);
    auto a = new Test5();
    MinidReflectWrapper.push(t, a);
    md.rawCall(t, -3, 0);
}


void dyn_invoke_test() {
    //lol
    auto x1 = gTypes.getType!(Test5)();
    auto x2 = cast(ReferenceType)x1;
    auto x3 = x2.klass();
    auto x4 = x3.findMethod("grizzle");
    auto x5 = x4.type();
    //object instance
    auto o = x3.newInstance();
    (cast(Test5)o).c = 123;
    //invoke "grizzle" dynamically
    char[] ret;
    SafePtr pret = gTypes.ptrOf(ret);
    char[] p1 = "hullo";
    int p2 = 456;
    SafePtr[2] pparams = [gTypes.ptrOf(p1), gTypes.ptrOf(p2)];
    x4.invoke_dynamic(o, pret, pparams);
    Trace.formatln("result: >{}<", ret);
    //second way
    x4.invoke_dynamic_trampoline(o,
        (SafePtr ret, SafePtr[] args, void delegate() call) {
            args[0].write!(char[])("muh");
            args[1].write!(int)(789);
            call();
            auto res = ret.read!(char[])();
            Trace.formatln("result: >{}<", res);
        }
    );
}

class Test5 {
    this() { }
    this(ReflectCtor c) { }

    short c;

    void a() {
    }

    void b(Test6 xd) {
        Trace.formatln("b({})", xd);
    }

    Test6 foobar() {
        return new Test6();
    }

    char[] grizzle(char[] a, int b) {
        auto res = myformat("{}", a.length+b*3);
        //Trace.formatln("grizzle('{}', {}) = {}", a, b, res);
        return res;
    }

    mixin Methods!("a", "b", "grizzle", "foobar");
}

class Test6 {
    this() { }
    this(ReflectCtor c) { }

    Object mFun;

    void setFun(Object o) {
        mFun = o;
    }

    Object getFun() {
        return mFun;
    }

    Test6 getThis() {
        return this;
    }

    mixin Methods!("getThis", "getFun", "setFun");
}

Types gTypes;

void main(char[][] args) {
    gTypes = new Types();
    gTypes.registerClasses!(Test5, Test6);
    debugDumpTypeInfos(gTypes);
    dyn_invoke_test();
    md_test();
    Stdout.formatln("end");
}


import physics.collisionmap;
import physics.contact;