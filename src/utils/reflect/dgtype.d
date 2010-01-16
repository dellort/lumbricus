module utils.reflect.dgtype;

import utils.reflect.type;
import utils.reflect.types;
import utils.reflect.safeptr;
import utils.misc;

class DelegateType : Type {
    //use create()
    private this(Types a_owner, TypeInfo a_ti) {
        super(a_owner, a_ti);
    }

    package static DelegateType create(T)(Types a_owner) {
        static assert(is(T == delegate));
        DelegateType t = new DelegateType(a_owner, typeid(T));
        t.do_init!(T)();
        return t;
    }

    override char[] toString() {
        //note that the return value from TypeInfo_Delegate.toString() looks
        //like D syntax, but the arguments are not included
        //e.g. "long delegate(int z)" => "long delegate()"
        return "DelegateType[]";
    }
}

