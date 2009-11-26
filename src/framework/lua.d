module framework.lua;

import derelict.lua.lua;
import derelict.lua.pluto;
import derelict.util.exception : SharedLibLoadException;
import tango.stdc.stringz;
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

//create an error message if the error is caused by a wrong script
void raiseLuaError(lua_State *state, char[] msg) {
    luaL_where(state, 1);
    lua_pushstring(state, toStringz(msg));
    lua_concat(state, 2);
    lua_error(state);
}

T luaStackValue(T)(lua_State *state, int stackIdx) {
    //xxx no check if stackIdx is valid (is checked in demarshal() anyway)
    void expected(char[] t) {
        throw new LuaException(t ~ " expected, got "
            ~ fromStringz(luaL_typename(state, stackIdx)));
    }
    static if (isIntegerType!(T) || isFloatingPointType!(T)) {
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
                lua_pushnumber(state, key);
                lua_pushnil(state);
                lua_settable(state, LUA_REGISTRYINDEX);
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
        pwrap.key = intr.bswap(cast(uint)cast(void*)pwrap);

        lua_pushnumber(state, pwrap.key);  //unique key
        lua_pushvalue(state, -2);                    //lua closure
        lua_settable(state, LUA_REGISTRYINDEX);

        return &pwrap.cbfunc;
    } else {
        static assert(false, "add me, you fool");
    }
}

//returns the number of values pushed (for Vectors maybe, I don't know)
//xxx: that would be a problem, see luaCall()
int luaPush(T)(lua_State *state, T value) {
    static if (isFloatingPointType!(T) || isIntegerType!(T)) {
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
        static assert(false, "add me, you fool");
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
            //....seriously? bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat bloat
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
    }

    //Register a class method
    void method(Class, char[] name)() {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;
            void error(char[] msg) {
                raiseLuaError(state, msg);
            }

            LuaState ustate = cast(LuaState)(lua_touserdata(state,
                lua_upvalueindex(1)));
            Class c = ustate.getSingleton!(Class)();
            int skipCount = 0;
            if (!c) {
                Object o = cast(Object)lua_touserdata(state, 1);
                skipCount++;
                c = cast(Class)(o);
                if (!c) {
                    error(myformat("method call to '{}' requires "
                        "this pointer as first argument", methodName));
                }
            }

            auto del = mixin("&c."~name);
            try {
                return callFromLua(del, state, skipCount, methodName);
            } catch (LuaException e) {
                error(e.msg);
            }
        }

        Method m;
        auto ci = Class.classinfo;
        auto cn = ci in mPrefixes;
        char[] clsname = cn ? *cn : ci.name;
        //strip package/module path
        int i = str.rfind(clsname, ".");
        if (i >= 0) {
            clsname = clsname[i+1..$];
        }
        m.fname = clsname ~ "_" ~ name;
        m.demarshal = &demarshal;
        mMethods ~= m;
    }

    //shortcut for registering multiple methods of a class
    //each item of Names is expected to be a char[] (a method name of Class)
    void methods(Class, Names...)() {
        foreach (int idx, _; Names) {
            method!(Class, Names[idx])();
        }
    }

    //Register a function
    void func(alias Fn)(char[] rename = null) {
        //stringof returns "& functionName", strip that
        const funcName = (&Fn).stringof[2..$];
        extern(C) static int demarshal(lua_State* state) {
            try {
                return callFromLua(&Fn, state, 0, funcName);
            } catch (LuaException e) {
                raiseLuaError(state, e.msg);
            }
        }
        Method m;
        m.fname = rename.length ? rename : funcName;
        m.demarshal = &demarshal;
        mMethods ~= m;
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
        Object[ClassInfo] mSingletons;
    }

    this(int stdlibFlags = LuaLib.all) {
        mLua = lua_newstate(&my_lua_alloc, null);
        lua_atpanic(mLua, &my_lua_panic);
        loadStdLibs(stdlibFlags);
    }

    void loadStdLibs(int stdlibFlags) {
        foreach (lib; luaLibs) {
            if (stdlibFlags & lib.flag) {
                lua_pushcfunction(mLua, *lib.func);
                lua_pushstring(mLua, toStringz(lib.name));
                lua_call(mLua, 1, 0);
            }
        }
    }

    T getSingleton(T)() {
        auto i = T.classinfo in mSingletons;
        return i ? cast(T)(*i) : null;
    }

    void register(LuaRegistry stuff) {
        foreach (m; stuff.mMethods) {
            lua_pushlightuserdata(mLua, cast(void*)this);
            lua_pushcclosure(mLua, m.demarshal, 1);
            lua_setglobal(mLua, toStringz(m.fname));
        }
    }

    void addSingleton(T)(T instance) {
        assert(!(T.classinfo in mSingletons));
        mSingletons[T.classinfo] = instance;
    }

    private void lua_loadChecked(lua_Reader reader, void *d, char[] chunkname) {
        //'=' means use the name as-is (else "string " is added)
        int res = lua_load(mLua, reader, d, toStringz('='~chunkname));
        if (res != 0) {
            char[] err = lua_todstring(mLua, -1);
            lua_pop(mLua, 1);  //remove error message
            throw new LuaException("Parse error: " ~ err);
        }
    }

    //prepended all very-Lua-specific functions with lua

    /+
    //"generic scripting" load function (yeah, the language of the loaded script
    //  is still lua)
    void load(char[] function_name, char[] code) {
        ...
    }
    +/

    void luaLoadAndPush(char[] name, char[] code) {
        StringChunk sc;
        sc.data = code;
        lua_loadChecked(&lua_ReadString, &sc, name);
    }

    void luaLoadAndPush(char[] name, Stream input) {
        lua_loadChecked(&lua_ReadStream, cast(void*)input, name);
    }

    //Call a function defined in lua
    void call(T...)(char[] funcName, T args) {
        return callR!(void, T)(funcName, args);
    }

    //like call(), but with return value
    //better name?
    //also, it seems dmd can't infer only some parameters, e.g.:
    //      callR!(int)("test", "abc", "def")
    //fails.
    //if you get something like "Error: template framework.lua.LuaState.callR(RetType,T...) declaration T is already defined", it means dmd is being retarded, and one of the subseqeuent template instantiatoins copntain semantic errors
    RetType callR(RetType, T...)(char[] funcName, T args) {
        //xxx should avoid memory allocation (toStringz)
        stack0();
        lua_getglobal(mLua, toStringz(funcName));
        if (!lua_isfunction(mLua, 1)) {
            throw new LuaException(funcName ~ ": not a function.");
        }
        scope(success)
            stack0();
        return doLuaCall!(RetType, T)(mLua, args);
    }

    //execute the global scope
    RetType luaCall(RetType, T...)(T args) {
        return doLuaCall!(RetType, T)(mLua, args);
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

        lua_getfield(mLua, LUA_GLOBALSINDEX, toStringz(stuff));

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
        lua_setfield(mLua, LUA_GLOBALSINDEX, toStringz(stuff));
        lua_pop(mLua, 1);
        stack0();
    }

    void addScriptType(T)(char[] tableName) {
        lua_getfield(mLua, LUA_GLOBALSINDEX, toStringz(tableName));
        const c_mangle = "D_struct_" ~ T.mangleof ~ '\0';
        lua_setfield(mLua, LUA_REGISTRYINDEX, c_mangle.ptr);
    }
}
