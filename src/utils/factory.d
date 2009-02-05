module utils.factory;

class ClassNotFoundException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

class WrapNotFoundException : Exception {
    this(Exception e, char[] msg) {
        super("wrapped exception, this was thrown when trying to instantiate " ~
            msg ~ ": " ~ e.toString());
    }
}

//a small factory template
//ConstructorArgs is a tuple which is passed as constructor arguments
class Factory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private constructorCallback[char[]] mConstructors;
    private char[][TypeInfo] mInverseLookup;
    private TypeInfo[ClassInfo] mCiToTi;

    //can't be named register(), because... hm? DMD is just borken.
    void registerByDelegate(char[] name, constructorCallback create) {
        if (name in mConstructors) {
            throw new Exception("oh noes! class already exists: " ~ name);
        }
        mConstructors[name] = create;
    }

    //register by type
    //call it like: Factory!(YourInterface).register!(YourClass)("name")
    void register(X)(char[] name) {
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

    T instantiate(char[] name, ConstructorArgs args) {
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
    bool exists(char[] name) {
        return !!(name in mConstructors);
    }

    char[][] classes() {
        return mConstructors.keys;
    }

    char[] lookup(X : T)() {
        return lookupDynamic(typeid(X));
    }

    char[] lookupDynamic(TypeInfo t) {
        auto pname = t in mInverseLookup;
        return pname ? *pname : "";
    }

    //why thank you D for this extra hashmap needed in this case
    //(no way for ClassInfo -> TypeInfo?)
    char[] lookupDynamic(ClassInfo ci) {
        auto pt = ci in mCiToTi;
        return pt ? lookupDynamic(*pt) : null;
    }
}

///Unique = string literal that makes the instantiated type unique
///see unittest how to use this
final class StaticFactory(char[] Unique, T, ConstructorArgs...) {
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

    static void registerByDelegate(char[] name, constructorCallback create) {
        factory().registerByDelegate(name, create);
    }

    static void register(X)(char[] name) {
        factory().register!(X)(name);
    }

    static void registerX(X)() {
        factory().registerX!(X)();
    }

    static T instantiate(char[] name, ConstructorArgs args) {
        return factory().instantiate(name, args);
    }

    static bool exists(char[] name) {
        return factory().exists(name);
    }

    static char[][] classes() {
        return factory().classes();
    }

    static char[] lookup(X : T)() {
        return factory().lookup!(X)();
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
