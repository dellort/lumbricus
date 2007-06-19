module utils.factory;

//a small factory template
//ConstructorArgs is a tuple which is passed as constructor arguments
class Factory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private constructorCallback[char[]] mConstructors;

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
    }

    //register using the unqualified class name
    //named registerX() because overloading doesn't work
    void registerX(X)() {
        register!(X)(X.stringof);
    }

    T instantiate(char[] name, ConstructorArgs args) {
        auto del = name in mConstructors;
        if (!del) {
            throw new Exception("class '"~name~"' not found.");
        }
        return (*del)(args);
    }

    char[][] classes() {
        return mConstructors.keys;
    }
}

//nice cutnpaste
static class StaticFactory(T, ConstructorArgs...) {
    alias T delegate(ConstructorArgs) constructorCallback;
    private static constructorCallback[char[]] mConstructors;

    //can't be named register(), because... hm? DMD is just borken.
    static void registerByDelegate(char[] name, constructorCallback create) {
        if (name in mConstructors) {
            throw new Exception("oh noes! class already exists: " ~ name);
        }
        mConstructors[name] = create;
    }

    //register by type
    //call it like: Factory!(YourInterface).register!(YourClass)("name")
    static void register(X)(char[] name) {
        static assert( is (X : T));

        //argh, using a function literal here crashes DMD *g*
        T inst(ConstructorArgs x) {
            return new X(x);
        }

        registerByDelegate(name, &inst);
    }

    //register using the unqualified class name
    //named registerX() because overloading doesn't work
    static void registerX(X)() {
        register!(X)(X.stringof);
    }

    static T instantiate(char[] name, ConstructorArgs args) {
        auto del = name in mConstructors;
        if (!del) {
            throw new Exception("class '"~name~"' not found.");
        }
        return (*del)(args);
    }

    static char[][] classes() {
        return mConstructors.keys;
    }
}

