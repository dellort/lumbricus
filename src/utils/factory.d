module utils.factory;

import utils.misc;

class ClassNotFoundException : CustomException {
    this(string msg) {
        super(msg);
    }
}

class WrapNotFoundException : CustomException {
    this(Exception e, string msg) {
        super("wrapped exception, this was thrown when trying to instantiate " ~
            msg ~ ": " ~ e.toString());
        next = e;
    }
}

//a small factory template
//ConstructorArgs is a tuple which is passed as constructor arguments
class Factory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private constructorCallback[string] mConstructors;
    private string[TypeInfo] mInverseLookup;
    private TypeInfo[ClassInfo] mCiToTi;

    //can't be named register(), because... hm? DMD is just borken.
    void registerByDelegate(string name, constructorCallback create) {
        if (auto pc = name in mConstructors) {
            //if the same, ignore it
            //(not sure if this is a good idea, but it can't really harm)
            if (*pc is create)
                return;
            throw new CustomException("oh noes! class already exists: " ~ name);
        }
        mConstructors[name] = create;
    }

    //register by type
    //call it like: Factory!(YourInterface).register!(YourClass)("name")
    void register(X)(string name) {
        static assert( is (X : T));

        //argh, using a function literal here crashes DMD *g*
        T inst(ConstructorArgs x) {
            return new X(x);
        }

        registerByDelegate(name, &inst);
        mInverseLookup[typeid(X)] = name;
        mCiToTi[X.classinfo] = typeid(X);
    }

    //register using the unqualified class name
    //named registerX() because overloading doesn't work
    void registerX(X)() {
        register!(X)(X.stringof);
    }

    T instantiate(string name, ConstructorArgs args) {
        auto del = name in mConstructors;
        if (!del) {
            throw new ClassNotFoundException("class '"~name~"' not found.");
        }
        T res;
        try {
            res = (*del)(args);
        } catch (ClassNotFoundException cnfe) {
            //wrap the exception, else someone might catch the wrong exception
            //(I had several debugging nightmares because it wasn't done)
            throw new WrapNotFoundException(cnfe, "class "~T.stringof
                ~" with name '"~name~"'");
        }
        return res;
    }

    //return true if a class is registered under this name
    bool exists(string name) {
        return !!(name in mConstructors);
    }

    string[] classes() {
        return mConstructors.keys;
    }

    string lookup(X : T)() {
        return lookupDynamic(typeid(X));
    }

    string lookupDynamic(TypeInfo t) {
        auto pname = t in mInverseLookup;
        return pname ? *pname : "";
    }

    //why thank you D for this extra hashmap needed in this case
    //(no way for ClassInfo -> TypeInfo?)
    string lookupDynamic(ClassInfo ci) {
        auto pt = ci in mCiToTi;
        return pt ? lookupDynamic(*pt) : null;
    }
}

///Unique = string literal that makes the instantiated type unique
///see unittest how to use this
final class StaticFactory(string Unique, T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private alias Factory!(T, ConstructorArgs) DFactory;

    //return the dynamic factory (which is created on demand)
    static DFactory factory() {
        //Note: Unique is needed to make the following static symbol unique
        //      accross the program
        static DFactory f;
        if (!f)
            f = new DFactory();
        return f;
    }

    static void registerByDelegate(string name, constructorCallback create) {
        factory().registerByDelegate(name, create);
    }

    static void register(X)(string name) {
        factory().register!(X)(name);
    }

    static void registerX(X)() {
        factory().registerX!(X)();
    }

    static T instantiate(string name, ConstructorArgs args) {
        return factory().instantiate(name, args);
    }

    static bool exists(string name) {
        return factory().exists(name);
    }

    static string[] classes() {
        return factory().classes();
    }

    static string lookup(X : T)() {
        return factory().lookup!(X)();
    }

    static string lookupDynamic(TypeInfo t) {
        return factory().lookupDynamic(t);
    }

    static string lookupDynamic(ClassInfo ci) {
        return factory().lookupDynamic(ci);
    }
}

private:
debug:

class X {
}
class Y {
}

alias StaticFactory!("f1", X) Factory1;
alias StaticFactory!("f2", X) Factory2;
alias StaticFactory!("f3", Y) Factory3;

unittest {
    Factory1.register!(X)("x");
    Factory3.register!(Y)("x");
    Factory2.register!(X)("x");
}
