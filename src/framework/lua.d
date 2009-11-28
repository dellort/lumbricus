module framework.lua;

import derelict.lua.lua;
import derelict.lua.pluto;
import derelict.util.exception : SharedLibLoadException;
import czstr = tango.stdc.stringz;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType,
    ElementTypeOfArray, isArrayType, isAssocArrayType, KeyTypeOfAA, ValTypeOfAA,
    ReturnTypeOf;
import cstd = tango.stdc.stdlib;
import str = utils.string;
import net.marshal;

import utils.hashtable;
import utils.misc;
import utils.stream;

version = Lua_In_D_Memory;

version (Lua_In_D_Memory) {

extern (C) void *my_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    //make Lua use the D heap
    //note that this will go horribly wrong if...
    //- Lua would create a new OS thread (but it doesn't)
    //- Lua uses malloc() for some stuff (probably doesn't; lua_Alloc would
    //  be pointless)
    //- Lua stores state in global variables (I think it doesn't)
    //  (assuming D GC doesn't scan the C datasegment; probably wrong)
    //also, we'll assume that Lua always aligns out userdata correctly (if not,
    //  the D GC won't see it, and heisenbugs will occur)
    //all this is to make passing D objects as userdata simpler
    void[] odata = ptr[0..osize];
    if (nsize == 0) {
        delete odata;
        return null;
    } else {
        //this is slow (probably slower than C realloc)
        odata.length = nsize;
        return odata.ptr;
    }
}

} else {

extern (C) void *my_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    if (nsize == 0) {
        cstd.free(ptr);
        return null;
    } else {
        return cstd.realloc(ptr, nsize);
    }
}

}


//read code from char[]
struct StringChunk {
    char[] data;
}
extern(C) char* lua_ReadString(lua_State *L, void *data, size_t *size) {
    auto sc = cast(StringChunk*)data;
    *size = sc.data.length;
    auto code = sc.data;
    sc.data = null;
    return code.ptr;
}

//read code (or anything else) from Stream
extern(C) char* lua_ReadStream(lua_State *L, void *data, size_t *size) {
    const cBufSize = 16*1024;
    auto buf = new ubyte[cBufSize];
    auto st = cast(Stream)data;
    auto res = cast(char[])st.readUntilEof(buf);
    *size = res.length;
    return res.ptr;
}

//write to stream
extern(C) int lua_WriteStream(lua_State* L, void* p, size_t sz, void* ud) {
    auto st = cast(Stream)ud;
    st.writeExact(cast(ubyte[])p[0..sz]);
    return 0;
}

//panic function: called on unprotected lua error (message is on the stack)
extern(C) int my_lua_panic(lua_State *L) {
    char[] err = lua_todstring(L, -1);
    lua_pop(L, 1);
    throw new LuaException(err);
}

char[] lua_todstring(lua_State* L, int i) {
    size_t len;
    char* s = lua_tolstring(L, i, &len);
    if (!s)
        throw new LuaException("no string at given stack index");
    return s[0..len];
}

class LuaException : Exception { this(char[] msg) { super(msg); } }

//this alias is just so that we can pretend out scripting interface is generic
alias LuaException ScriptingException;

//create an error message if the error is caused by a wrong script
void raiseLuaError(lua_State *state, char[] msg) {
    luaL_where(state, 1);
    lua_pushstring(state, czstr.toStringz(msg));
    lua_concat(state, 2);
    lua_error(state);
}

T luaStackValue(T)(lua_State *state, int stackIdx) {
    //xxx no check if stackIdx is valid (is checked in demarshal() anyway)
    void expected(char[] t) {
        throw new LuaException(t ~ " expected, got "
            ~ czstr.fromStringz(luaL_typename(state, stackIdx)));
    }
    static if (isIntegerType!(T) || isFloatingPointType!(T) ||
        (is(T Base == enum) && isIntegerType!(Base)))
    {
        lua_Number ret = lua_tonumber(state, stackIdx);
        if (ret == 0 && !lua_isnumber(state, stackIdx))
            expected("number");
        return cast(T)ret;
    } else static if (is(T : bool)) {
        //accepts everything, true for anything except 'false' and 'nil'
        return !!lua_toboolean(state, stackIdx);
    } else static if (is(T : char[])) {
        try {
            return lua_todstring(state, stackIdx);
        } catch (LuaException e) {
            expected("string");
        }
    } else static if (is(T == class)) {
        //allow userdata and nil, nothing else
        if (!lua_islightuserdata(state, stackIdx) && !lua_isnil(state,stackIdx))
            expected("class reference");
        //by convention, all light userdatas are casted from Object
        //which means we can always type check it
        Object o = cast(Object)lua_touserdata(state, stackIdx);
        T res = cast(T)o;
        if (o && !res) {
            throw new LuaException(myformat("{} expected, got {}",
                T.classinfo.name, o.classinfo.name));
        }
        return res;
    } else static if (is(T == struct)) {
        //Note: supports both {x = 1, y = 2} and {1, 2} access mode,
        //      but mixing both in one declaration will fail horribly
        if (!lua_istable(state, stackIdx))
            expected("struct table");
        T ret;
        foreach (int idx, x; ret.tupleof) {
            //first try named access
            static assert(ret.tupleof[idx].stringof[0..4] == "ret.");
            luaPush(state, (ret.tupleof[idx].stringof)[4..$]);
            lua_gettable(state, stackIdx);   //replaces key by value
            if (lua_isnil(state, -1)) {
                //named access failed, try indexed
                lua_pop(state, 1);
                luaPush(state, idx+1);
                lua_gettable(state, stackIdx);
            }
            if (!lua_isnil(state, -1)) {
                ret.tupleof[idx] = luaStackValue!(typeof(ret.tupleof[idx]))(
                    state, -1);
            }
            lua_pop(state, 1);
        }
        return ret;
    } else static if (isArrayType!(T) || isAssocArrayType!(T)) {
        if (!lua_istable(state, stackIdx))
            expected("array table");
        T ret;
        lua_pushnil(state);  //first key
        int tablepos = stackIdx < 0? stackIdx-1 : stackIdx;
        while (lua_next(state, tablepos) != 0) {
            //lua_next pushes key, then value
            static if(isAssocArrayType!(T)) {
                auto curVal = luaStackValue!(ValTypeOfAA!(T))(state, -1);
                ret[luaStackValue!(KeyTypeOfAA!(T))(state, -2)] = curVal;
            } else {
                ret ~= luaStackValue!(ElementTypeOfArray!(T))(state, -1);
            }
            lua_pop(state, 1);   //pop value, leave key
        }
        return ret;
    } else static if (is(T == delegate)) {
        //the lua function to call is at stackIdx and must be stored for later
        //  calling. So it is added to the lua registry table with a unique key
        //  (the Wrapper memory address)
        //xxx changed Wrapper to class for lua registry cleanup and (possibly)
        //    serialization; old struct code here: http://codepad.org/s1TnASTV
        //    (I'm too stupid to see all the consequences)
        if (lua_isnil(state,stackIdx))
            return null;
        if (!lua_isfunction(state, stackIdx))
            expected("closure");
        alias ParameterTupleOf!(T) Params;
        alias ReturnTypeOf!(T) RetType;

        //deja-vu...
        class Wrapper {
            lua_State* state;
            uint key;
            this(lua_State* st) {
                state = st;
            }
            //making Wrapper serializable (with state external) should just
            //  do the right thing (lua registry value would be saved by pluto)
            //just when to register it?
            /*this(ReflectCtor c) {
                super(c);
                Types t = c.types();
                t.registerMethod(this, &cbfunc, "cbfunc");
            }*/
            ~this() {
                //remove function from registry (if state became invalid, those
                //  functions will just fail quietly)
                //--D GC is completely asynchronous and indeterministic; if this
                //--    dtor brings anything, then only segfaults on random
                //--    occasions; don't know how to solve this (maybe do the
                //--    same crap as with surfaces in the framework)
                //--lua_pushnumber(state, key);
                //--lua_pushnil(state);
                //--lua_settable(state, LUA_REGISTRYINDEX);
            }
            //will return delegate to this function
            RetType cbfunc(Params args) {
                //get callee from the registry and call
                lua_pushnumber(state, key);
                lua_gettable(state, LUA_REGISTRYINDEX);
                assert(lua_isfunction(state, -1));
                //will pop function from the stack
                return doLuaCall!(RetType, Params)(state, args);
            }
        }
        auto pwrap = new Wrapper(state);
        //use the hashed memory address as key (hashed because of GC)
        //bswap, the best and only hash function!!11
        //xxx not guaranteed to be unique in context of serialization, add check
        pwrap.key = intr.bswap(cast(size_t)cast(void*)pwrap);

        lua_pushnumber(state, pwrap.key);  //unique key
        lua_pushvalue(state, -2);                    //lua closure
        lua_settable(state, LUA_REGISTRYINDEX);

        return &pwrap.cbfunc;
    } else {
        static assert(false, "add me, you fool: " ~ T.stringof);
    }
}

//returns the number of values pushed (for Vectors maybe, I don't know)
//xxx: that would be a problem, see luaCall()
int luaPush(T)(lua_State *state, T value) {
    static if (isFloatingPointType!(T) || isIntegerType!(T) ||
        (is(T Base == enum) && isIntegerType!(Base)))
    {
        //everything is casted to double internally anyway; avoids overflows
        lua_pushnumber(state, value);
    } else static if (is(T : bool)) {
        lua_pushboolean(state, cast(int)value);
    } else static if (is(T : char[])) {
        lua_pushlstring(state, value.ptr, value.length);
    } else static if (is(T == class)) {
        lua_pushlightuserdata(state, cast(void*)value);
    } else static if (is(T == struct)) {
        lua_newtable(state);
        foreach (int idx, x; value.tupleof) {
            static assert(value.tupleof[idx].stringof[0..6] == "value.");
            luaPush(state, (value.tupleof[idx].stringof)[6..$]);
            luaPush(state, value.tupleof[idx]);
            lua_settable(state, -3);
        }
        const c_mangle = "D_struct_" ~ T.mangleof ~ '\0';
        lua_getfield(state, LUA_REGISTRYINDEX, c_mangle.ptr);
        lua_setmetatable(state, -2);
    } else static if (isArrayType!(T) || isAssocArrayType!(T)) {
        lua_newtable(state);
        foreach(k, v; value) {
            static if(isIntegerType!(typeof(k)))
                lua_pushinteger(state, k+1);
            else
                luaPush(state, k);

            luaPush(state, v);
            lua_settable(state, -3);
        }
    } else static if (is(T == void*)) {
        //allow pushing 'nil', but no other void*
        assert(value is null);
        lua_pushnil(state);
    } else {
        static assert(false, "add me, you fool: " ~ T.stringof);
    }
    return 1;  //default to 1 argument
}

//call the function on top of the stack
RetType doLuaCall(RetType, T...)(lua_State* state, T args) {
    int argc;
    foreach (int idx, x; args) {
        argc += luaPush(state, args[idx]);
    }
    const bool ret_void = is(RetType == void);
    lua_call(state, argc, ret_void ? 0 : 1);
    static if (!ret_void) {
        RetType res = luaStackValue!(RetType)(state, 1);
        lua_pop(state, 1);
        return res;
    }
}

bool gPlutoOK; //Pluto could was loaded

class LuaRegistry {
    private {
        Method[] mMethods;
        char[][ClassInfo] mPrefixes;
    }

    struct Method {
        ClassInfo classinfo;
        char[] fname;
        lua_CFunction demarshal;
    }

    this() {
        DerelictLua.load();
        //try loading Pluto, but treat it as optional dependency
        try {
            DerelictLua_Pluto.load();
            gPlutoOK = true;
        } catch (SharedLibLoadException) {
        }
        debug Trace.formatln("pluto available: {}", gPlutoOK);
    }

    //e.g. setClassPrefix!(GameEngine)("Game"), to keep scripting names short
    //call before any method() calls
    void setClassPrefix(Class)(char[] name) {
        mPrefixes[Class.classinfo] = name;
    }

    //Execute the callable del, taking parameters from the lua stack
    //  skipCount: skip this many parameters from beginning
    //  funcName:  used in error messages
    //stack size must match the requirements of del
    private static int callFromLua(T)(T del, lua_State* state, int skipCount,
        char[] funcName)
    {
        void error(char[] msg) {
            throw new LuaException(msg);
        }

        try {
            int numArgs = lua_gettop(state);

            alias ParameterTupleOf!(typeof(del)) Params;
            //min/max arguments allowed to be passed from lua (incl. 'this')
            int maxArgs = Params.length + skipCount;
            int minArgs = requiredArgCount!(del)() + skipCount;
            //argument count has to be in accepted range (exact match)
            if (numArgs < minArgs || numArgs > maxArgs) {
                if (minArgs == maxArgs) {
                    error(myformat("'{}' requires {} arguments, got {}",
                        funcName, maxArgs, numArgs));
                } else {
                    error(myformat("'{}' requires {}-{} arguments, got {}",
                        funcName, minArgs, maxArgs, numArgs));
                }
            }
            //number of arguments going to the delegate call
            int numRealArgs = numArgs - skipCount;

            //hack: add dummy type, to avoid code duplication
            alias Tuple!(Params, int) Params2;
            Params2 p;
            foreach (int idx, x; p) {
                //generate code for all possible parameter counts, and select
                //the right case at runtime
                static if (is(typeof(del(p[0..idx])) RetType)) {
                    if (numRealArgs == idx) {
                        static if (is(RetType == void)) {
                            del(p[0..idx]);
                            return 0;
                        } else {
                            auto ret = del(p[0..idx]);
                            return luaPush(state, ret);
                        }
                    }
                }
                assert(idx < Params.length);
                alias typeof(x) T;
                try {
                    p[idx] = luaStackValue!(T)(state, skipCount + idx + 1);
                } catch (LuaException e) {
                    error(myformat("bad argument #{} to '{}' ({})", idx + 1,
                        funcName, e.msg));
                }
            }
            assert(false);
        } catch (LuaException e) {
            raiseLuaError(state, e.msg);
        }
    }

    //Register a class method
    void method(Class, char[] name)() {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;
            void error(char[] msg) {
                raiseLuaError(state, msg);
            }

            //--LuaState ustate = cast(LuaState)(lua_touserdata(state,
            //--    lua_upvalueindex(1)));

            Object o = cast(Object)lua_touserdata(state, 1);
            Class c = cast(Class)(o);

            if (!c) {
                error(myformat("method call to '{}' requires "
                    "non-null this pointer of type {} as first argument, but "
                    "got: {}", methodName, Class.stringof,
                    o ? o.classinfo.name : "*null"));
            }

            auto del = mixin("&c."~name);
            return callFromLua(del, state, 1, methodName);
        }

        registerDMethod(Class.classinfo, name, &demarshal);
    }

    private void registerDMethod(ClassInfo ci, char[] method,
        lua_CFunction demarshal)
    {
        Method m;
        auto cn = ci in mPrefixes;
        char[] clsname = cn ? *cn : ci.name;
        //strip package/module path
        int i = str.rfind(clsname, ".");
        if (i >= 0) {
            clsname = clsname[i+1..$];
        }
        m.fname = clsname ~ "_" ~ method;
        m.demarshal = demarshal;
        m.classinfo = ci;
        mMethods ~= m;
    }

    //read/write accessor (if rw==false, it's read-only)
    // Class.'name' can be either a setter/getter, or a field
    void property(Class, char[] name, bool rw = true)() {
        //works by introducing "renaming" functions, which just call the
        //  setters/getters; that's because &Class.name would return only the
        //  first declared function of that name, and generating the actual
        //  calling code is the only way of

        //NOTE: could support autodetection of read-only properties via is(),
        //  but I think that's a bad idea: is() could hide semantic errors, and
        //  then a property would be read-only unintentionally (then e.g. a
        //  script could fail unexplainably)

        //get type of the accessor (setter and getter should use the same types)
        //good that DG literals have return value type inference
        alias typeof({ Class d; return mixin("d." ~ name); }()) Type;

        auto ci = Class.classinfo;

        extern(C) static int demarshal_get(lua_State* state) {
            static Type get(Class o) {
                return mixin("o." ~ name);
            }
            return callFromLua(&get, state, 0, "property get " ~ name);
        }

        registerDMethod(ci, "get_" ~ name, &demarshal_get);

        static if (rw) {
            //xxx: a bit strange how it does three nested calls for stuff known
            //     at compile time...
            extern(C) static int demarshal_set(lua_State* state) {
                static void set(Class o, Type t) {
                    //mixin() must be an expression here, not a statement
                    //but the parser messes it up, we don't get an expression
                    //make use of the glorious comma operator to make it one
                    //"I can't believe this works"
                    1, mixin("o." ~ name) = t;
                }
                return callFromLua(&set, state, 0, "property set " ~ name);
            }

            registerDMethod(ci, "set_" ~ name, &demarshal_set);
        }
    }

    //read-only property
    //note that unlike method(), this also works for fields, and works better if
    //  there's also a property setter (which you want to hide from scripts)
    void property_ro(Class, char[] name)() {
        property!(Class, name, false)();
    }

    //shortcut for registering multiple methods of a class
    //each item of Names is expected to be a char[] (a method name of Class)
    void methods(Class, Names...)() {
        foreach (int idx, _; Names) {
            method!(Class, Names[idx])();
        }
    }

    //also a shortcut; each Names item is a char[]
    void properties(Class, Names...)() {
        foreach (int idx, _; Names) {
            property!(Class, Names[idx])();
        }
    }

    //Register a function
    void func(alias Fn)(char[] rename = null) {
        //stringof returns "& functionName", strip that
        const funcName = (&Fn).stringof[2..$];
        extern(C) static int demarshal(lua_State* state) {
            return callFromLua(&Fn, state, 0, funcName);
        }
        Method m;
        m.fname = rename.length ? rename : funcName;
        m.demarshal = &demarshal;
        mMethods ~= m;
    }

    DefClass!(Class) defClass(Class)(char[] prefixname = "") {
        if (prefixname.length)
            setClassPrefix!(Class)(prefixname);
        return DefClass!(Class)(this);
    }
}

//for convenience; might be completely useless
//basically saves you from typing the class name all the time again
//if it shows not to be useful, it should be removed
//returned by LuaRegistry.defClass!(T)
struct DefClass(Class) {
    LuaRegistry registry;

    //documentation see LuaRegistry

    void method(char[] name)() {
        registry.method!(Class, name)();
    }

    void property(char[] name, bool rw = true)() {
        registry.property!(Class, name, rw)();
    }

    void properties(Names...)() {
        registry.properties!(Class, Names);
    }

    void property_ro(char[] name)() {
        registry.property!(Class, name, false)();
    }

    void methods(Names...)() {
        registry.methods!(Class, Names);
    }
}

//flags for LuaState.loadStdLibs
enum LuaLib {
    base = 1,
    table = 2,
    io = 4,
    os = 8,
    string = 16,
    math = 32,
    debuglib = 64,
    packagelib = 128,

    all = int.max,
    safe = base | table | string | math,
}

private {
    struct LuaLibReg {
        int flag;
        char[] name;
        lua_CFunction* func;
    }
    //cf. linit.c from lua source
    const LuaLibReg[] luaLibs = [
        {LuaLib.base, "", &luaopen_base},
        {LuaLib.table, LUA_TABLIBNAME, &luaopen_table},
        {LuaLib.io, LUA_IOLIBNAME, &luaopen_io},
        {LuaLib.os, LUA_OSLIBNAME, &luaopen_os},
        {LuaLib.string, LUA_STRLIBNAME, &luaopen_string},
        {LuaLib.math, LUA_MATHLIBNAME, &luaopen_math},
        {LuaLib.debuglib, LUA_DBLIBNAME, &luaopen_debug},
        {LuaLib.packagelib, LUA_LOADLIBNAME, &luaopen_package}];
}

class LuaState {
    private {
        //handle to LUA whatever-thingy
        lua_State* mLua;
        LuaRegistry.Method[] mMethods;
        Object[ClassInfo] mSingletons;
    }

    this(int stdlibFlags = LuaLib.all) {
        mLua = lua_newstate(&my_lua_alloc, null);
        lua_atpanic(mLua, &my_lua_panic);
        loadStdLibs(stdlibFlags);

        //own std stuff
        auto reg = new LuaRegistry();
        reg.func!(ObjectToString)();
        register(reg);
    }

    //needed by utils.lua to format userdata
    private static char[] ObjectToString(Object o) {
        return o ? o.toString() : "null";
    }

    void loadStdLibs(int stdlibFlags) {
        foreach (lib; luaLibs) {
            if (stdlibFlags & lib.flag) {
                lua_pushcfunction(mLua, *lib.func);
                lua_pushstring(mLua, czstr.toStringz(lib.name));
                lua_call(mLua, 1, 0);
            }
        }
    }

/+
    T getSingleton(T)() {
        auto i = T.classinfo in mSingletons;
        return i ? cast(T)(*i) : null;
    }
+/

    void register(LuaRegistry stuff) {
        foreach (m; stuff.mMethods) {
            //--lua_pushlightuserdata(mLua, cast(void*)this);
            //--lua_pushcclosure(mLua, m.demarshal, 1);
            lua_pushcclosure(mLua, m.demarshal, 0);
            lua_setglobal(mLua, czstr.toStringz(m.fname));

            mMethods ~= m;
        }
    }

    void addSingleton(T)(T instance) {
        doAddSingleton(T.classinfo, instance);
    }

    //non-templated
    //xxx actually, this should follow the inhertiance chain, shouldn't it?
    //    would be a problem, because not all superclasses would be singleton
    private void doAddSingleton(ClassInfo ci, Object instance) {
        assert(!!instance);
        assert(!(ci in mSingletons));
        mSingletons[ci] = instance;
        //just rewrite the already registered methods
        //if methods are added after this call, the user is out of luck
        stack0();
        foreach (m; mMethods) {
            if (m.classinfo !is ci)
                continue;
            //the method name is the same, just that the singleton is now
            //  automagically added on a call (not sure if that's a good idea)
            //auto singleton_name = "singleton_" ~ m.classinfo.name;
            //luaPush(mLua, instance);
            //lua_setglobal(mLua, czstr.toStringz(singleton_name));
            scriptExec(`
                local fname, ston = ...
                local orgfunction = _G[fname]
                --local singleton = _G[sname]
                local singleton = ston
                local function dispatch(...)
                    -- yay closures
                    return orgfunction(singleton, ...)
                end
                _G[fname] = dispatch
            `, m.fname, instance); //singleton_name);
        }
        stack0();
    }

    private void lua_loadChecked(lua_Reader reader, void *d, char[] chunkname) {
        //'=' means use the name as-is (else "string " is added)
        int res = lua_load(mLua, reader, d, czstr.toStringz('='~chunkname));
        if (res != 0) {
            char[] err = lua_todstring(mLua, -1);
            lua_pop(mLua, 1);  //remove error message
            throw new LuaException("Parse error: " ~ err);
        }
    }

    //prepended all very-Lua-specific functions with lua
    //functions starting with lua should be avoided in user code

    void luaLoadAndPush(char[] name, char[] code) {
        StringChunk sc;
        sc.data = code;
        lua_loadChecked(&lua_ReadString, &sc, name);
    }

/+
    void luaLoadAndPush(char[] name, Stream input) {
        lua_loadChecked(&lua_ReadStream, cast(void*)input, name);
    }
+/

    //another variation
    //load script in "code", using "name" for error messages
    //there's also scriptExec() if you need to pass parameters
    void loadScript(char[] name, char[] code) {
        stack0();
        luaLoadAndPush(name, code);
        luaCall!(void)();
        stack0();
    }

    //Call a function defined in lua
    void call(T...)(char[] funcName, T args) {
        return callR!(void)(funcName, args);
    }

    //like call(), but with return value
    //better name?
    //this tripple nesting (thx to h3) allows us to use type inference:
    //  state.callR!(int)("func", 123, "abc", 5.4);
    template callR(RetType) {
        RetType callR(T...)(char[] funcName, T args) {
            //xxx should avoid memory allocation (czstr.toStringz)
            stack0();
            lua_getglobal(mLua, czstr.toStringz(funcName));
            if (!lua_isfunction(mLua, 1)) {
                throw new LuaException(funcName ~ ": not a function.");
            }
            scope(success)
                stack0();
            return doLuaCall!(RetType, T)(mLua, args);
        }
    }

    //execute the global scope
    RetType luaCall(RetType, Args...)(Args args) {
        return doLuaCall!(RetType, Args)(mLua, args);
    }

    template scriptExecR(RetType) {
        RetType scriptExecR(Args...)(char[] code, Args a) {
            luaLoadAndPush("scriptExec", code);
            return luaCall!(RetType, Args)(a);
        }
    }

    //execute a script snippet (should only be used for slow stuff like command
    //  line interpreters, or initialization code)
    void scriptExec(Args...)(char[] code, Args a) {
        scriptExecR!(void)(code, a);
    }

    void stack0() {
        assert(lua_gettop(mLua) == 0);
    }

    private const cSerializeNull = "#null";
    private const cSerializeMagic = "MAGIC";

    //write contents of global variable stuff into Stream st
    //external_id() is called for D objects residing inside the lua dump; the
    //  only requirement for the returned IDs is to unique and to be != ""
    //returning "" from external_id() means "unknown object" and will trigger an
    //  error
    void serialize(char[] stuff, Stream st,
        char[] delegate(Object o) external_id)
    {
        assert(gPlutoOK);
        stack0();

        lua_getfield(mLua, LUA_GLOBALSINDEX, czstr.toStringz(stuff));

        //pluto expects us to resolve externals in advance (permanents-table)
        //traverse Lua's object graph, and find any light user data (= external)
        //be aware that the Pluto crap will serialize userdata as POINTERS if
        //  you don't add them to the permanents-table (yes, really)
        //do this in Lua because that's simply simpler
        //this helps: http://lua-users.org/wiki/TableSerialization
        luaLoadAndPush("serialize_find_externals", `
            -- xxx: metatables, environments, ...?
            local done = {}
            local exts = {}
            local ws = {}

            local function add(x)
                if type(x) == "table" then
                    if done[x] == nil then
                        ws[x] = true
                    end
                end
                if type(x) == "userdata" then
                    exts[x] = true
                end
            end

            --for key, value in pairs(...) do
            --    add(value)
            --end
            add(...)

            while true do
                -- like a stack.pop()
                -- look how simple and elegant Lua makes this!
                local cur = next(ws)
                if cur == nil then break end
                ws[cur] = nil

                done[cur] = true
                for key, value in pairs(cur) do
                    add(key)
                    add(value)
                end
            end

            return exts
        `);
        lua_pushvalue(mLua, -2);
        lua_call(mLua, 1, 1);
        lua_pushvalue(mLua, -1);
        int tidx = lua_gettop(mLua);
        assert(tidx == 3);

        //build Pluto "permanent table"; external objects as keys, id as values
        //reuses the returned set of userdata found by the script above
        char[][] externals;
        lua_pushnil(mLua);
        while (lua_next(mLua, tidx)) {
            Object o = luaStackValue!(Object)(mLua, -2);
            char[] id = cSerializeNull;
            if (o) {
                id = external_id(o);
                if (id.length == 0) {
                    assert(false, "can't serialize: " ~ o.classinfo.name);
                }
                externals ~= id;
            }
            lua_pop(mLua, 1);
            lua_pushvalue(mLua, -1); //key
            luaPush(mLua, id);
            lua_settable(mLua, tidx);
            //key remains on stack for lua_next
        }
        lua_pop(mLua, 1); //table

        assert(lua_gettop(mLua) == 2);

        //Pluto crap requires us to construct the permanents-table before
        //  deserializing; so we store our own crap in the stream
        auto marshal = Marshaller((ubyte[] d) { st.writeExact(d); });
        marshal.write(externals);
        marshal.write!(char[])(cSerializeMagic);

        //stack contents: 1=stuff, 2=permanent-table
        //exchange 1 and 2
        lua_pushvalue(mLua, 1);
        lua_remove(mLua, 1);

        //pluto is very touchy about this, and non-debug versions don't catch it
        assert(lua_gettop(mLua) == 2);
        pluto_persist(mLua, &lua_WriteStream, cast(void*)st);

        assert(lua_gettop(mLua) == 2);
        lua_pop(mLua, 2);
    }

    //parameters same as serialize
    //external_id is the inverse as in serialize(); returning null means error
    void deserialize(char[] stuff, Stream st,
        Object delegate(char[]) external_id)
    {
        auto unmarshal =
            Unmarshaller((ubyte[] d) { st.readExact(d); return size_t.max; });
        auto ext_names = unmarshal.read!(char[][])();

        stack0();
        lua_newtable(mLua);

        void add_ext(char[] name, Object o) {
            luaPush(mLua, name);
            luaPush(mLua, o);
            lua_settable(mLua, -3);
        }

        foreach (name; ext_names) {
            Object o = external_id(name);
            if (!o) {
                assert(false, "object not found: "~name);
            }

            add_ext(name, o);
        }

        add_ext("#null", null);

        auto m = unmarshal.read!(char[])();
        assert(m == cSerializeMagic);

        assert(lua_gettop(mLua) == 1); //perm-table
        pluto_unpersist(mLua, &lua_ReadStream, cast(void*)st);

        //should push the desrrialized objects
        assert(lua_gettop(mLua) == 2);
        lua_setfield(mLua, LUA_GLOBALSINDEX, czstr.toStringz(stuff));
        lua_pop(mLua, 1);
        stack0();
    }

    void addScriptType(T)(char[] tableName) {
        lua_getfield(mLua, LUA_GLOBALSINDEX, czstr.toStringz(tableName));
        const c_mangle = "D_struct_" ~ T.mangleof ~ '\0';
        lua_setfield(mLua, LUA_REGISTRYINDEX, c_mangle.ptr);
    }
}
