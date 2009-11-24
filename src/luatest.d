module luatest;

import derelict.lua.lua;
import tango.stdc.stringz;
import tango.core.tools.TraceExceptions;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType;
import cstd = tango.stdc.stdlib;
import str = utils.string;
import tango.util.Convert : to;

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

//read code from Stream
extern(C) char* lua_ReadStream(lua_State *L, void *data, size_t *size) {
    const cBufSize = 16*1024;
    auto buf = new ubyte[cBufSize];
    auto st = cast(Stream)data;
    auto res = cast(char[])st.readUntilEof(buf);
    *size = res.length;
    return res.ptr;
}

//panic function: called on unprotected lua error (message is on the stack)
extern(C) int my_lua_panic(lua_State *L) {
    char[] err = lua_todstring(L, 1);
    throw new LuaException("Lua error: " ~  err);
}

class LuaException : Exception { this(char[] msg) { super(msg); } }

//create an error message if the error is caused by a wrong script
void raiseLuaError(lua_State *state, char[] msg) {
    //xxx add filename/line number
    lua_pushstring(state, toStringz(msg));
    lua_error(state);
}

T luaStackValue(T)(lua_State *state, int stackIdx) {
    //xxx error checking
    static if (isIntegerType!(T)) {
        return lua_tointeger(state, stackIdx);
    } else static if (isFloatingPointType!(T)) {
        return lua_tonumber(state, stackIdx);
    } else static if (is(T : bool)) {
        return !!lua_toboolean(state, stackIdx);
    } else static if (is(T : char[]) || is(T : wchar[]) || is(T : dchar[])) {
        //xxx I think it's not worth supporting wchar, dchar, rather I'd prefer
        // to remove to!() because to!() makes memory managment less clear
        return to!(T)(lua_todstring(state, stackIdx));
    } else static if (is(T == class)) {
        //by convention, all light userdatas are casted from Object
        //which means we can always type check it
        Object o = cast(Object)lua_touserdata(state, stackIdx);
        T res = cast(T)o;
        if (o && !res) {
            raiseLuaError(state, myformat("expected {}, got {}",
                T.classinfo.name, o.classinfo.name));
        }
        return res;
    } else {
        static assert(false, "add me, you fool");
    }
}

//returns the number of values pushed (for Vectors maybe, I don't know)
//xxx: that would be a problem, see luaCall()
int luaPush(T)(lua_State *state, T value) {
    static if (isIntegerType!(T)) {
        lua_pushinteger(state, stackIdx);
        return 1;
    } else static if (isFloatingPointType!(T)) {
        lua_pushnumber(state, value);
        return 1;
    } else static if (is(T : bool)) {
        lua_pushboolean(state, cast(int)value);
        return 1;
    } else static if (is(T : char[])) {
        lua_pushlstring(state, value.ptr, value.length);
        return 1;
    } else static if (is(T : wchar[]) || is(T : dchar[])) {
        char[] tmp = to!(char[])(value);
        lua_pushlstring(state, tmp.ptr, tmp.length);
        return 1;
    } else static if (is(T == class)) {
        lua_pushlightuserdata(state, cast(void*)value);
        return 1;
    } else static if (is(T == void*)) {
        //???
        assert(value is null);
        lua_pushnil(state);
        return 1;
    } else {
        static assert(false, "add me, you fool");
    }
}

class LuaRegistry {
    private {
        Method[] mMethods;
    }

    struct Method {
        ClassInfo ci;
        char[] name, fname;
        lua_CFunction demarshal;
    }

    this() {
        DerelictLua.load();
    }

    void method(Class, char[] name)() {
        extern(C) static int demarshal(lua_State* state) {
            void error(char[] msg) {
                //"Foo.method: Error"
                raiseLuaError(state, Class.stringof ~ '.' ~ name ~ ": " ~ msg);
            }

            int numArgs = lua_gettop(state);

            LuaState ustate = cast(LuaState)(lua_touserdata(state,
                lua_upvalueindex(1)));
            Class c = ustate.getSingleton!(Class)();
            int baseidx = 1;
            if (!c) {
                Object o = cast(Object)lua_touserdata(state, baseidx);
                baseidx++;
                c = cast(Class)(o);
                if (!c) {
                    error("Method call requires this pointer as first argument.");
                }
            }

            auto del = mixin("&c."~name);
            alias ParameterTupleOf!(typeof(del)) Params;
            int reqArgs = Params.length + baseidx - 1;
            //xxx ignores superfluous arguments, ok?
            //  is there some Lua convention that encourages this?
            //  I'd prefer it'd has to match the exact arg count
            if (numArgs != reqArgs) {
                error(myformat("Required {} arguments, got {}.", reqArgs,
                    numArgs));
            }

            Params p;
            foreach (int idx, x; p) {
                alias typeof(x) T;
                p[idx] = luaStackValue!(T)(state, baseidx + idx);
            }
            alias typeof(del(p)) RetType;
            static if (is(RetType == void)) {
                del(p);
                return 0;
            } else {
                auto ret = del(p);
                return luaPush(state, ret);
            }
        }
        Method m;
        m.ci = Class.classinfo;
        m.name = name;
        char[] clsname = m.ci.name;
        //strip package/module path
        int i = str.rfind(clsname, ".");
        if (i >= 0) {
            clsname = clsname[i+1..$];
        }
        m.fname = clsname ~ "_" ~ m.name;
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
        int res = lua_load(mLua, reader, d, toStringz(chunkname));
        if (res != 0) {
            throw new LuaException("Lua load error: " ~ lua_todstring(mLua, 1));
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

    void luaLoadAndPush(char[] code, char[] name) {
        StringChunk sc;
        sc.data = code;
        lua_loadChecked(&lua_ReadString, &sc, name);
    }

    void luaLoadAndPush(Stream input, char[] name) {
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
    RetType callR(RetType, T...)(char[] funcName, T args) {
        //xxx should avoid memory allocation (toStringz)
        lua_getglobal(mLua, toStringz(funcName));
        if (!lua_isfunction(mLua, 1)) {
            throw new LuaException(funcName ~ ": not a function.");
        }
        return luaCall!(RetType, T)(args);
    }

    //execute the global scope
    RetType luaCall(RetType, T...)(T args) {
        int argc;
        foreach (int idx, x; args) {
            argc += luaPush(mLua, args[idx]);
        }
        const bool ret_void = is(RetType == void);
        lua_call(mLua, argc, ret_void ? 0 : 1);
        static if (!ret_void) {
            return luaStackValue!(RetType)(mLua, 1);
        }
    }
}



class Bar {
    char[] meh;

    void test(char[] msg) {
        Trace.formatln("Called Bar.test('{}')", msg);
    }

    char[] blurgh() {
        return meh;
    }
}

class Evul {
}

class Foo {
    char[] test(int x, float y, char[] msg) {
        return myformat("hello from D! got: {} {} '{}'", x, y, msg);
    }

    void passBar(Bar the_bar) {
        Trace.formatln("received a bar: '{}'", the_bar.classinfo.name);
        if (the_bar)
            assert(!!cast(Bar)cast(Object)the_bar);
    }

    Bar createBar() {
        auto b = new Bar();
        b.meh = "I'm a bar.";
        return b;
    }

    Evul createEvul() {
        return new Evul();
    }
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.method!(Foo, "test")();
    scripting.method!(Foo, "createBar")();
    scripting.method!(Foo, "createEvul")();
    scripting.method!(Foo, "passBar")();
    scripting.method!(Bar, "test")();
    scripting.method!(Bar, "blurgh")();

    //lua.method!(Sprite, "setState")();
    //lua.method!(GameEngine, "explosion")();
}

/*void startgame() {
    lua.addSingleton!(GameEngine)("GameEngine", engine);
}*/

void main(char[][] args) {
    LuaState s = new LuaState();
    s.register(scripting);
    auto foo = new Foo();
    s.addSingleton(foo);

    void loadexec(char[] code) {
        s.luaLoadAndPush(code, "blub");
        s.luaCall!(void)();
    }

    loadexec(`
        print("Hello world")
        print(Foo_test(1, -4.2, "Foobar"))
        b = Foo_createBar()
        Bar_test(b, "hurf")

        function test(arg)
            print(string.format("Called Lua function test('%s')", arg))
            return "blabla"
        end

        Foo_passBar(b)
    `);
    s.call("test", "Blubber");

    Trace.formatln("got: '{}'", s.callR!(char[], char[])("test", "..."));

    //don't try this without version Lua_In_D_Memory

    //get some garbage, trigger GC and overwriting of free'd data, etc.
    for (int i = 0; i < 5000000; i++) {
        new ubyte[1];
    }

    loadexec(`
        print(Bar_blurgh(b))
    `);

    //these are expected to fail (type checks etc.)
    //I don't know how to fail "gracefully", so all commented out

    //too many args
    //--loadexec(`Bar_test(b, "a", "b")`);
    //too few args
    //--loadexec(`Bar_test()`);
    //wrong type
    //--loadexec(`Foo_passBar(Foo_createEvul())`);
}
