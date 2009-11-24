module animutil;

import derelict.lua.lua;
import tango.stdc.stringz;
import tango.core.tools.TraceExceptions;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType;
import cstd = tango.stdc.stdlib;
import str = utils.string;

import utils.misc;
import utils.stream;

extern (C) void *my_lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
    if (nsize == 0) {
        cstd.free(ptr);
        return null;
    } else {
        return cstd.realloc(ptr, nsize);
    }
}

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
            LuaState ustate = cast(LuaState)(lua_touserdata(state,
                lua_upvalueindex(1)));
            Class c = ustate.getSingleton!(Class)();
            int baseidx = 1;
            if (!c) {
                Object o = cast(Object)lua_touserdata(state, baseidx);
                baseidx++;
                if (!o) {
                    assert(false, "script passed garbage");
                }
                c = cast(Class)(o);
            }
            auto del = mixin("&c."~name);
            alias ParameterTupleOf!(typeof(del)) Params;
            Params p;
            foreach (int idx, x; p) {
                alias typeof(x) T;
                static if (isIntegerType!(T)) {
                    p[idx] = lua_tointeger(state, baseidx + idx);
                } else {
                    static assert("add me, you fool");
                }
            }
            del(p);
            return 0;
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

class LuaState {
    private {
        //handle to LUA whatever-thingy
        lua_State* mLua;
        Object[ClassInfo] mSingletons;

    }

    this() {
        mLua = lua_newstate(&my_lua_alloc, null);
        luaL_openlibs(mLua);
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

    void load(char[] code, char[] name) {
        StringChunk sc;
        sc.data = code;
        int res = lua_load(mLua, &lua_ReadString, &sc, toStringz(name));
        assert(res == 0);
    }
}

class Foo {
    void test(int x, byte y) {
        Trace.formatln("hello from lua! got: {} {}", x, y);
    }
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.method!(Foo, "test")();

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
    s.load(`
    print("Hello world")
    Foo_test(1, -34)
`, "Blub");
    if (lua_pcall(s.mLua, 0, 0, 0) != 0)
        Trace.formatln("Error: {}", lua_todstring(s.mLua, 1));
}
