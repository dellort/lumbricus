module utils.reflect.dgtype;

import utils.reflect.type;
import utils.reflect.types;
import utils.reflect.safeptr;
import utils.misc;

//how the D compiler layouts a delegate
//args this is ABI dependent, but D doesn't allow to write to the delegate's
//.ptr and .funcptr properties, so we have to do this evil thing
//(ABI = can be different from platform to platform)
struct D_Delegate {
    void* ptr;
    void* funcptr;
}

//wow, an union template!
union DgConvert(T) {
    static assert(is(T == delegate));
    static assert(d1.sizeof == d2.sizeof);
    D_Delegate d1;
    T d2;
}

static this() {
    //test if the delegate ABI is as expected
    class TestDg { void foo() {} }
    TestDg t = new TestDg();
    auto dg = &t.foo;
    DgConvert!(typeof(dg)) dgc;
    dgc.d2 = dg;
    if (!(dgc.d1.ptr is dgc.d2.ptr && dgc.d1.funcptr is dgc.d2.funcptr))
        throw new Exception("ABI test in reflection.d failed.");
}

class DelegateType : Type {
    private {
        Type mReturnType;
        Type[] mParameterTypes;
        void function(SafePtr, SafePtr, SafePtr[]) mInvoker;
        void function(DelegateType, SafePtr, void delegate(SafePtr, SafePtr[],
            void delegate())) mTrampoline;
    }

    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    package static DelegateType create(T)(Types a_owner) {
        static assert(is(T == delegate));
        DelegateType t = new DelegateType(a_owner, typeid(T));
        t.do_init!(T)();
        //squeeze out ret types and params
        static if(is(T TF == delegate)) {
            static if(is(TF Params == function)) {
                //better way to get rettype?
                T foo;
                Params p;
                alias typeof(foo(p)) RetType;
                t.mReturnType = a_owner.getType!(RetType);
                const cRetVoid = is(RetType == void);

                foreach (int idx, _; Params) {
                    t.mParameterTypes ~= a_owner.getType!(Params[idx]);
                }
                t.mReturnType = a_owner.getType!(RetType)();

                //generate actual call code for dynamic invocation
                t.mInvoker = function void(SafePtr del, SafePtr ret,
                    SafePtr[] args)
                {
                    Params p;
                    foreach (int idx, _; p) {
                        p[idx] = args[idx].read!(typeof(p[idx]));
                    }
                    ret.check(typeid(RetType)); //type-check before actual call
                    T rdel = del.read!(T)();
                    //actual call
                    //arrgh shitty special case
                    static if (cRetVoid) {
                        rdel(p);
                    } else {
                        auto r = rdel(p);
                        ret.write!(RetType)(r);
                    }
                };

                //meh...
                t.mTrampoline = function void(DelegateType me, SafePtr del,
                    void delegate(SafePtr, SafePtr[], void delegate()) jump)
                {
                    Params p;
                    SafePtr[Params.length] pp;
                    foreach (int idx, _; p) {
                        pp[idx].type = me.mParameterTypes[idx];
                        pp[idx].ptr = &p[idx];
                    }
                    SafePtr pr;
                    pr.type = me.mReturnType;
                    static if (!cRetVoid) {
                        RetType r;
                        pr.ptr = &r;
                    }
                    T rdel = del.read!(T)();
                    //the user calls the passed delegate, as soon as he has
                    //filled the params
                    jump(pr, pp, {
                        static if (cRetVoid) {
                            rdel(p);
                        } else {
                            r = rdel(p); //note that pr points to r
                        }
                    });
                };
            } else {
                static assert(false);
            }
        } else {
            static assert(false);
        }
        return t;
    }

    final Type[] parameterTypes() {
        return mParameterTypes;
    }

    final Type returnType() {
        return mReturnType;
    }

    //call a delegate dynamically
    //  del = ptr to the delegate (== this.typeInfo())
    //  ret = pointer to where the return value will be written
    //        (must be of the exact type obviously)
    //  args = parameters
    final void invoke_dynamic(SafePtr del, SafePtr ret, SafePtr[] args) {
        mInvoker(del, ret, args);
    }

    //same functionality as invoke_dynamic, but fills ret and args automatically
    //works like this:
    //  - init ret and args
    //  - call jump() with ret, args, and the call delegate (which will later
    //    execute the actual call)
    //  - user fills args with his values
    //  - user calls call()
    //  - actual method (referred to by del) is executed
    //  - call() returns and fills ret
    //  - user reads return value from ret
    //it's allowed to not call call() at all or to call it more than once
    final void invoke_dynamic_trampoline(SafePtr del,
        void delegate(SafePtr ret, SafePtr[] args, void delegate() call) jump)
    {
        mTrampoline(this, del, jump);
    }

    override char[] toString() {
        //note that the return value from TypeInfo_Delegate.toString() looks
        //like D syntax, but the arguments are not included
        //e.g. "long delegate(int z)" => "long delegate()"
        char[] res = "DelegateType[";
        res ~= mReturnType.toString();
        foreach (m; mParameterTypes) {
            res ~= ", " ~ m.toString();
        }
        return res ~ "]";
    }
}

