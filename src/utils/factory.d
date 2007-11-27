module utils.factory;

class ClassNotFoundException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

//a small factory template
//ConstructorArgs is a tuple which is passed as constructor arguments
class Factory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private constructorCallback[char[]] mConstructors;
    private char[][TypeInfo] mInverseLookup;

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
        return (*del)(args);
    }

    //return true if a class is registered under this name
    bool exists(char[] name) {
        return !!(name in mConstructors);
    }

    char[][] classes() {
        return mConstructors.keys;
    }

    char[] lookup(X : T)() {
        return mInverseLookup[typeid(X)];
    }
}

class StaticFactory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private alias Factory!(T, ConstructorArgs) DFactory;

    //return the dynamic factory (which is created on demand)
    static DFactory factory() {
        //xxx: this static variable is shared across all factory classes of the
        //same type (same T and ConstructorArgs), which is terribly wrong.
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

class Factory1 : StaticFactory!(X) {
}
class Factory2 : StaticFactory!(X) {
}
class Factory3 : StaticFactory!(Y) {
}

unittest {
    Factory1.register!(X)("x");
    Factory3.register!(Y)("x");
    //xxx fails :(
    //Factory2.register!(X)("x");
}
