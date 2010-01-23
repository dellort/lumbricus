module utils.reflect.classdef;

import utils.reflect.type;
import utils.reflect.types;
import utils.reflect.structtype;
import utils.reflect.refctor;
import utils.reflect.dgtype;
import utils.reflect.safeptr;
import utils.misc;
import str = utils.string;

import tango.stdc.ctype : isalnum;

///Describes the contents of a class or a struct
///This is not derived from Type, because ReferenceType is actually used to
///describe classes and interfaces. However, the class "Class" provides further
///information (like members), which can only be obtained at compiletime.
class Class {
    private {
        StructuredType mOwner;
        ClassInfo mCI;
        Class mSuper;
        size_t mClassSize; //just used for verificating stuff
        char[] mName;
        ClassElement[] mElements;
        ClassMember[] mMembers, mNTMembers;
        ClassMethod[] mMethods;
        Object mDummy; //for default values - only if isClass()
        void[] mInit; //for default values - only if isStruct()
        Object delegate(ReflectCtor c) mCreateDg;
        bool[size_t] mTransientCache;  //
        Class[] mHierarchy; //filled on demand
    }

    package this(ReferenceType a_owner, TypeInfo_Class cti) {
        mOwner = a_owner;
        mCI = cti.info;
        mClassSize = mCI.init.length;
        assert (mOwner.typeInfo() is cti);
        a_owner.setClass(this);
    }

    private this(StructType a_owner) {
        mOwner = a_owner;
        mClassSize = a_owner.size();
        a_owner.setClass(this);
        //TypeInfo.init() can be null
        //for the sake of generality, allocate a byte array in this case
        TypeInfo ti = mOwner.typeInfo();
        mInit = mOwner.initData();
        assert (mInit.length == mOwner.size());
    }

    package void name(char[] n) {
        mName = n;
    }
    package void createDg(typeof(mCreateDg) cdg) {
        mCreateDg = cdg;
    }
    package void dummy(Object d) {
        mDummy = d;
    }

    private void addElement(ClassElement e) {
        foreach (ClassElement old; mElements) {
            //NOTE: the only way this can happen is (besides an internal error)
            //      template mixins which are used several times
            assert (old.name() != e.name());
        }
        mElements = mElements ~ e;
        if (auto me = cast(ClassMember)e) {
            mMembers ~= me;
            if (!(me.offset in mTransientCache))
                mNTMembers ~= me;
        }
        if (auto md = cast(ClassMethod)e)
            mMethods ~= md;
    }

    package void addTransientMember(size_t relOffset) {
        mTransientCache[relOffset] = true;
    }

    final ClassElement[] elements() {
        return mElements;
    }

    final ClassMember[] members() {
        return mMembers;
    }

    final ClassMember[] nontransientMembers() {
        return mNTMembers;
    }

    final ClassMethod[] methods() {
        return mMethods;
    }

    final char[] name() {
        return mName;
    }

    final StructuredType type() {
        return mOwner;
    }

    final Class superClass() {
        return mSuper;
    }

    //class hierarchy with all super classes, starting with this class
    // res[$-1] is this
    // for each 1<=a<res.length: res[a].superClass() is res[a-1]
    // res[0].superClass() is null
    //for structs, only contains itself
    final Class[] hierarchy() {
        if (mHierarchy.length == 0) {
            Class[] hier;
            auto curc = this;
            while (curc) {
                mHierarchy ~= curc;
                curc = curc.superClass();
            }
            mHierarchy.reverse;
        }
        debug {
            assert(mHierarchy[$-1] is this);
            assert(mHierarchy[0].superClass() is null);
            for (int n = 1; n < mHierarchy.length; n++) {
                assert(mHierarchy[n].superClass() is mHierarchy[n-1]);
            }
            if (isStruct()) {
                assert(mHierarchy.length == 1);
            }
        }
        return mHierarchy;
    }

    final bool isClass() {
        return !!mCI;
    }

    final bool isStruct() {
        return !isClass();
    }

    final StructuredType owner() {
        return mOwner;
    }

    package void addMethod(DelegateType dgt, void* funcptr, char[] name) {
        foreach (ClassMethod m; mMethods) {
            if (m.name() == name) {
                if (m.mDgType !is dgt || m.mAddress !is funcptr)
                    throw new CustomException("different method with same name");
                return;
            }
        }
        if (auto other = owner.owner.lookupMethod(funcptr)) {
            //for a class hierarchy, all ctors are called, when a dummy object
            //is created, and so, a subclass will try to register all methods
            //from a super class
            //note that supertypes register their methods first...
            // simply assume that this.isSubTypeOf(other.klass())==true
            //can't really check that, too much foobar which prevents that
            //xxx won't work if the superclass is abstract, maybe just add all
            //    possible classes to the address? ClassMethod[][void*] map
            assert (name == other.name);
            //writefln("huh: {}: {} {}", name, this.name, other.klass.name);
            //ok, add the method anyway, who cares
            //return;
        }
        new ClassMethod(this, dgt, funcptr, name);
    }

    //find a method by name; also searches superclasses
    //return null if not found
    final ClassMethod findMethod(char[] name) {
        Class ck = this;
        outer: while (ck) {
            foreach (ClassMethod curm; ck.methods()) {
                if (curm.name() == name) {
                    return curm;
                }
            }
            ck = ck.superClass();
        }
        return null;
    }

    //return if "this" is inherited from (or the same as) "other"
    final bool isSubTypeOf(Class other) {
        Class cur = this;
        while (cur) {
            if (cur is other)
                return true;
            cur = cur.mSuper;
        }
        return false;
    }

    final Types types() {
        return mOwner.owner;
    }

    final Object newInstance() {
        if (!mCreateDg) {
            debug Trace.formatln("no: {}", name());
            return null;
        }
        auto c = types().refCtor;
        c.recreateTransient = true;
        scope(exit) c.recreateTransient = false;
        Object o = mCreateDg(c);
        assert (!!o);
        assert (types.findClass(o) is this);
        return o;
    }

    //everything about this is read-only
    //null for structs
    final Object defaultValues() {
        return mDummy;
    }
}

//share code for ClassMember & ClassMethod
class ClassElement {
    private {
        Class mOwner;
        char[] mName;
    }

    private this(Class a_owner, char[] a_name) {
        mOwner = a_owner;
        mName = a_name;
        mOwner.addElement(this);
    }

    final char[] name() {
        return mName;
    }

    final char[] fullname() {
        return myformat("{}.{}", mOwner.name(), name());
    }

    final Class klass() {
        return mOwner;
    }
}

///Class member as in a variable declaration in a class
class ClassMember : ClassElement {
    private {
        Type mType;
        size_t mOffset; //byte offset
    }

    private this(Class a_owner, char[] a_name, Type a_type, size_t a_offset) {
        mType = a_type;
        mOffset = a_offset;
        super(a_owner, a_name);
    }

    final Type type() {
        return mType;
    }

    final size_t offset() {
        return mOffset;
    }

    ///Return a pointer to the member of the passed object
    ///  obj = pointer to the object reference, must be of the exact type
    ///Note that the semantic is the same like in D: &someobject.member will
    ///return a pointer to member.
    SafePtr get(SafePtr obj) {
        obj.checkExactNotNull(mOwner.mOwner, "ClassMember.get()");
        void* ptr = obj.realptr();
        assert (!!ptr);
        return SafePtr(mType, ptr + mOffset);
    }

    ///check if this member is set to the default value on the passed object
    bool isInit(SafePtr obj) {
        SafePtr memberPtr = get(obj);
        byte* bptr_m = cast(byte*)memberPtr.ptr;
        assert(bptr_m);
        byte* bptr_def;
        if (mOwner.isClass) {
            //class, check against dummy instance
            bptr_def = (cast(byte*)mOwner.mDummy) + mOffset;
        } else {
            //struct, check against typeinfo
            //attention: checks against default struct initializer,
            //    not member initializer in class definition
            bptr_def = (cast(byte*)mOwner.mInit.ptr) + mOffset;
        }
        return bptr_m[0..type.size] == bptr_def[0..type.size];
    }

    char[] toString() {
        return myformat("{} @ {} : {}", fullname(), offset(), type());
    }
}

///Method of a class
///at least needed for serializing delegates
class ClassMethod : ClassElement {
    private {
        //type of the function ptr of the delegate
        DelegateType mDgType;
        //address of the code
        void* mAddress;
        //lol; also means structs have no methods for now
        ReferenceType mOwnerType;
    }

    private this(Class a_owner, DelegateType dgt, void* addr, char[] a_name) {
        super(a_owner, a_name);
        mOwnerType = castStrict!(ReferenceType)(mOwner.type());
        mDgType = dgt;
        mAddress = addr;
        Types t = mOwner.mOwner.owner; //oh absurdity
        //xxx maybe could happen if the user registers two virtual functions
        //    (overridden ones, with the same name), and then removes the one
        //    in the sub class => no compiletime or runtime error, but this
//        assert (!(addr in t.mMethodMap));
        t.addMethod(addr, this);
    }

    final void* address() {
        return mAddress;
    }

    final DelegateType type() {
        return mDgType;
    }

    char[] toString() {
        return myformat("{}() @ {:x#} : {}", fullname(), address(), type());
    }
}

char[] structFullyQualifiedName(T)() {
    //better way?
    return typeid(T).toString();
}

class DefineClass {
    private {
        Class mClass;
        Types mBase;
    }

    //ti = TypeInfo of the defined class
    this(Types a_owner, Class k) {
        mClass = k;
        mBase = a_owner;
    }

    this(Types a_owner, StructType t) {
        mClass = new Class(t);
        mBase = a_owner;
    }

    //also used for structs
    void autoclass(T)() {
        T obj;
        static if (is(T == class)) {
            assert (!!mClass.mDummy);
            obj = castStrict!(T)(mClass.mDummy);
            T obj_addr = obj;
            //uh, moved getting the name
        } else {
            T* obj_addr = &obj;
            mClass.mName = structFullyQualifiedName!(T);
        }
        size_t[] offsets;
        Type[] member_types;
        size_t member_count = obj.tupleof.length;
        offsets.length = member_count;
        member_types.length = member_count;
        foreach (int index, x; obj.tupleof) {
            //this is a manual .offsetof
            //it sucks much less than the compiler's builtin one
            //also see http://d.puremagic.com/issues/show_bug.cgi?id=947
            auto p_obj = cast(void*)obj_addr;
            auto p_member = cast(void*)&obj.tupleof[index];
            offsets[index] = cast(size_t)p_member - cast(size_t)p_obj;
            member_types[index] = mBase.getType!(typeof(x))();
            //doesn't work! search for "dmd tupleof-enum bug"
            //char[] name = obj.tupleof[i].stringof;
            //recurse!
            /+ probably not a good idea: instantiates a lot of templates
            static if (isReflectableClass!(typeof(x))()) {
                mBase.registerClass!(typeof(x))();
            }
            +/
        }
        //since the direct approach doesn't work, do this to get member names:
        //parse the tupleof string
        char[] names = obj.tupleof.stringof;
        const cPrefix = "tuple(";
        const cSuffix = ")";
        assert (str.startsWith(names, cPrefix));
        assert (str.endsWith(names, cSuffix));
        names = names[cPrefix.length .. $ - cSuffix.length];
        char[][] parsed_names = str.split(names, ",");
        assert (parsed_names.length == member_count);
        foreach (ref char[] name; parsed_names) {
            //older compiler versions include the name in ()
            //who knows in which ways future compilers will break this
            if (name.length && name[0] == '(' && name[$-1] == ')')
                name = name[1 .. $-1];
            char[] objstr = obj.stringof;
            assert (str.startsWith(name, objstr));
            name = name[objstr.length .. $];
            assert (name.length > 0 && name[0] == '.');
            name = name[1 .. $];
            //must be a valid D identifier now
            for (int n = 0; n < name.length; n++) {
                assert (isalnum(name[n]) || name[n] == '_');
            }
        }
        //actually add the fields
        for (int n = 0; n < member_count; n++) {
            addField(parsed_names[n], member_types[n], offsets[n]);
        }
        //time for some MAGIC
        //created by Methods!()
        static if (is(typeof( {obj._register_methods(obj, mBase);} ))) {
            obj._register_methods(obj, mBase);
        }
        //handle super classes
        static if (is(T S == super)) {
            static if (!is(S[0] == Object)) {
                //mClass.mSuper = mBase.registerClass!(S[0])();
                mClass.mSuper = mBase.registerSuperClass!(S[0])(mClass.mDummy);
            }
        }
    }

    void autostruct(T)() {
        autoclass!(T)();
    }

    void addField(char[] name, Type type, size_t offset) {
        assert(!!type);
        auto p_obj = cast(void*)mClass.mDummy;
        auto p_member = p_obj + offset;
        assert(p_member >= p_obj);
        assert(p_member + type.size() <= p_obj + mClass.mClassSize);
        new ClassMember(mClass, name, type, offset);
    }

    /// define a field for the class being defined - must pass an unique name,
    /// and a reference pointing to same field in the dummy object
    /// called like this: .field("field0", &field0);
    void field(T)(char[] name, T* member) {
        addField(name, mBase.getType!(T)(),
            cast(void*)member - cast(void*)mClass.mDummy);
    }

    /// like field(), but for methods
    /// called like this: .method("method0", &method0);
    /// (a real delegate is passed, not a pointer)
    void method(T)(char[] name, T del) {
        static assert(is(T == delegate));
        //must be a delegate to a method of mDummy
        assert(del.ptr is cast(void*)mClass.mDummy);
        mClass.addMember(new ClassMethod(mClass.mOwner, name,
            typeid(typeof(del.funcptr)), del.funcptr));
    }
}

//unittest, as static ctor because failures can lead to silent breakages
import utils.test : Test;
static this() {
    Test z = new Test();
    char[] res;
    foreach (int index, x; z.tupleof) {
        res ~= z.tupleof[index].stringof ~ "|";
    }
    assert (res == "z.a|z.b|z.c|z.d|");
    assert (structFullyQualifiedName!(Test.S) == "utils.test.Test.S");
}
