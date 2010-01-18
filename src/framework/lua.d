module framework.lua;

import derelict.lua.lua;
import derelict.util.exception : SharedLibLoadException;
import czstr = tango.stdc.stringz;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType,
    ElementTypeOfArray, isArrayType, isAssocArrayType, KeyTypeOfAA, ValTypeOfAA,
    ReturnTypeOf;
import cstd = tango.stdc.stdlib;
import rtraits = tango.core.RuntimeTraits;
import str = utils.string;
import net.marshal;

import utils.misc;
import utils.stream;
import utils.strparser;

import tango.core.Exception;

//--- stuff which might appear as keys in the Lua "Registry"

//mangle value that's unique for each D type
//used for metatables for certain D types in Lua
//must be null-terminated
//xxx could use a lightuserdata with the type's TypeInfo as value
//  (the Lua registry can use lightuserdata as keys)
//  requires more API calls, but possibly faster than hashing the string...
private template C_Mangle(T) {
    const C_Mangle = "D_bind_" ~ T.mangleof ~ '\0';
}
private char* envMangle(char[] envName) {
    return czstr.toStringz("chunk_env_" ~ envName);
}

const cLuaDelegateTable = "D_delegates";

//--- Lua "Registry" stuff end


private extern (C) void *my_lua_alloc(void *ud, void *ptr, size_t osize,
    size_t nsize)
{
    //make Lua use the D heap
    //note that this will go horribly wrong if...
    //- Lua would create a new OS thread (but it doesn't)
    //- Lua uses malloc() for some stuff (probably doesn't; lua_Alloc would
    //  be pointless)
    //- Lua stores state in global variables (I think it doesn't)
    //  (assuming D GC doesn't scan the C datasegment; probably wrong)
    //also, we'll assume that Lua always aligns our userdata correctly (if not,
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

//read code from char[]
private struct StringChunk {
    char[] data;
}
private extern(C) char* lua_ReadString(lua_State *L, void *data, size_t *size) {
    auto sc = cast(StringChunk*)data;
    *size = sc.data.length;
    auto code = sc.data;
    sc.data = null;
    return code.ptr;
}

//read code (or anything else) from Stream
private extern(C) char* lua_ReadStream(lua_State *L, void *data, size_t *size) {
    const cBufSize = 16*1024;
    auto buf = new ubyte[cBufSize];
    auto st = cast(Stream)data;
    auto res = cast(char[])st.readUntilEof(buf);
    *size = res.length;
    return res.ptr;
}

//write to stream
private extern(C) int lua_WriteStream(lua_State* L, void* p, size_t sz,
    void* ud)
{
    auto st = cast(Stream)ud;
    st.writeExact(cast(ubyte[])p[0..sz]);
    return 0;
}

//panic function: called on unprotected lua error (message is on the stack)
private extern(C) int my_lua_panic(lua_State *L) {
    scope (exit) lua_pop(L, 1);
    char[] err = lua_todstring(L, -1).dup;
    throw new LuaException(err);
}

//if the string is going to be used after the Lua value is popped from the
//  stack, you must .dup it (Lua may GC and reuse the string memory)
private char[] lua_todstring(lua_State* L, int i) {
    size_t len;
    char* s = lua_tolstring(L, i, &len);
    if (!s)
        throw new LuaException("no string at given stack index");
    char[] res = s[0..len];
    debug {
        try {
            str.validate(res);
        } catch (str.UnicodeException s) {
            //not sure if it should be this exception
            throw new LuaException("invalid utf-8 string from Lua");
        }
    }
    return res;
}

//if index is a relative stack index, convert it to an absolute one
//  e.g. -2 => 4 (if stack size is 5)
private int luaRelToAbsIndex(lua_State* state, int index) {
    if (index < 0) {
        //the tricky part is dealing with pseudo-indexes (also non-negative)
        int stacksize = lua_gettop(state);
        if (index <= -1 && index >= -1 - stacksize)
            index = stacksize + 1 + index;
    }
    return index;
}

class LuaException : Exception { this(char[] msg) { super(msg); } }

//this alias is just so that we can pretend our scripting interface is generic
alias LuaException ScriptingException;

//create an error message if the error is caused by a wrong script
void raiseLuaError(lua_State *state, char[] msg) {
    luaL_where(state, 1);
    lua_pushstring(state, czstr.toStringz(msg));
    lua_concat(state, 2);
    lua_error(state);
}

private void luaExpected(lua_State* state, int stackIdx, char[] expected) {
    throw new LuaException(expected ~ " expected, got "
        ~ czstr.fromStringz(luaL_typename(state, stackIdx)));
}
private void luaExpected(char[] expected, char[] got) {
    throw new LuaException(myformat("{} expected, got {}", expected, got));
}

//if this returns a string, you can use it only until you pop the corresponding
//  Lua value from the stack (because after this, Lua may garbage collect it)
T luaStackValue(T)(lua_State *state, int stackIdx) {
    void expected(char[] t) { luaExpected(state, stackIdx, t); }
    //xxx no check if stackIdx is valid (is checked in demarshal() anyway)
    static if (isIntegerType!(T) || isFloatingPointType!(T)) {
        lua_Number ret = lua_tonumber(state, stackIdx);
        if (ret == 0 && !lua_isnumber(state, stackIdx))
            expected("number");
        return cast(T)ret;
    } else static if (is(T Base == enum)) {
        if (lua_type(state, stackIdx) == LUA_TSTRING) {
            //we have this enumStrings() thing in strparser; try to use it
            //this costs a slow AA lookup
            auto pconvert = typeid(T) in gBoxParsers;
            if (!pconvert)
                expected("enum "~T.stringof);
            return (*pconvert)(lua_todstring(state, stackIdx)).unbox!(T)();
        } else {
            //try base type
            return cast(T)luaStackValue!(Base)(state, stackIdx);
        }
    } else static if (is(T : bool)) {
        //accepts everything, true for anything except 'false' and 'nil'
        return !!lua_toboolean(state, stackIdx);
    } else static if (is(T : char[])) {
        //there is the strange behaviour that tolstring may change the stack
        //  value, if the value is a number, and that can cause trouble with
        //  other functions - thus, better reject numbers
        //http://www.lua.org/manual/5.1/manual.html#lua_tolstring
        //NOTE: lua_isstring returns true for numbers (implicitly convertible
        //  to string), but I'd say "fuck implicit conversion to string"
        try {
            if (lua_type(state, stackIdx) == LUA_TSTRING)
                return lua_todstring(state, stackIdx);
        } catch (LuaException e) {
        }
        expected("string");
    } else static if (is(T == class)) {
        //allow userdata and nil, nothing else
        if (!lua_islightuserdata(state, stackIdx) && !lua_isnil(state,stackIdx))
            expected("class reference of type "~T.stringof);
        //by convention, all light userdatas are casted from Object
        //which means we can always type check it
        Object o = cast(Object)lua_touserdata(state, stackIdx);
        T res = cast(T)o;
        if (o && !res) {
            luaExpected(T.classinfo.name, o.classinfo.name);
        }
        return res;
    } else static if (is(T == struct)) {
        //Note: supports both {x = 1, y = 2} and {1, 2} access mode,
        //      but mixing both in one declaration will fail horribly
        if (!lua_istable(state, stackIdx))
            expected("struct table");
        T ret;
        int tablepos = luaRelToAbsIndex(state, stackIdx);
        foreach (int idx, x; ret.tupleof) {
            //goddamn dmd crap
            //dmd bug http://d.puremagic.com/issues/show_bug.cgi?id=2881
            //  will strike here; see end of this file for a test
            //xxx we now require a patched compiler; I hope the fix
            //    gets accepted soon
            //first try named access
            static assert(ret.tupleof[idx].stringof[0..4] == "ret.");
            luaPush(state, (ret.tupleof[idx].stringof)[4..$]);
            lua_gettable(state, tablepos);   //replaces key by value
            if (lua_isnil(state, -1)) {
                //named access failed, try indexed
                lua_pop(state, 1);
                luaPush(state, idx+1);
                lua_gettable(state, tablepos);
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
        int tablepos = luaRelToAbsIndex(state, stackIdx);
        lua_pushnil(state);  //first key
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
        return luaStackDelegate!(T)(state, stackIdx);
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
        //NOTE about enums: we could convert enums to strings (with
        //  enumStrings), but numbers are faster to pass; plus you had to do a
        //  slow AA lookup to get the string
        lua_pushnumber(state, value);
    } else static if (is(T : bool)) {
        lua_pushboolean(state, cast(int)value);
    } else static if (is(T : char[])) {
        lua_pushlstring(state, value.ptr, value.length);
    } else static if (is(T == class)) {
        if (value is null) {
            lua_pushnil(state);
        } else {
            lua_pushlightuserdata(state, cast(void*)value);
        }
    } else static if (is(T == struct)) {
        //This is a hack to allow functions to return multiple values without
        //exposing internal lua functions. The function returns a struct with
        //a special "marker constant", and all contained values will be returned
        //separately. S.numReturnValues can be defined to dynamically change
        //the number of return values
        static if (is(typeof(T.cTupleReturn)) && T.cTupleReturn) {
            int numv = int.max;
            //special marker to set how many values were returned
            //(useful e.g. for functions returning a bool success and an outval)
            static if (is(typeof(value.numReturnValues))) {
                numv = value.numReturnValues;
            }
            int argc = 0;
            foreach (int idx, x; value.tupleof) {
                //lol, better way?
                static if(value.tupleof[idx].stringof == "value.numReturnValues")
                    continue;
                if (numv <= 0)
                    break;
                argc += luaPush(state, x);
                numv--;
            }
            return argc;
        }
        lua_newtable(state);
        foreach (int idx, x; value.tupleof) {
            static assert(value.tupleof[idx].stringof[0..6] == "value.");
            luaPush(state, (value.tupleof[idx].stringof)[6..$]);
            luaPush(state, value.tupleof[idx]);
            lua_settable(state, -3);
        }
        //set the metatable for the type, if it was set by addScriptType()
        lua_getfield(state, LUA_REGISTRYINDEX, C_Mangle!(T).ptr);
        lua_setmetatable(state, -2);
    } else static if (isArrayType!(T) || isAssocArrayType!(T)) {
        const bool IsArray = isArrayType!(T);
        lua_newtable(state);
        foreach (k, v; value) {
            static if (IsArray)
                lua_pushinteger(state, k+1);
            else
                luaPush(state, k);

            luaPush(state, v);
            lua_settable(state, -3);
        }
    } else static if (is(T == delegate)) {
        luaPushDelegate(state, value);
    } else static if (is(T == void*)) {
        //allow pushing 'nil', but no other void*
        assert(value is null);
        lua_pushnil(state);
    } else {
        static assert(false, "add me, you fool: " ~ T.stringof);
    }
    return 1;  //default to 1 argument
}

//convert D delegate to a Lua c-closure, and push it on the Lua stack
//beware that the D delegate never should be from the stack, because Lua code
//  may call it even if the containing function returned (thus accessing random
//  data and the stack and causing corruption)
//to be safe, pass only normal object methods (of GC'ed objects)
private void luaPushDelegate(T)(lua_State* state, T del) {
    static assert(is(T == delegate));

    extern(C) static int demarshal(lua_State* state) {
        T del;
        del.ptr = lua_touserdata(state, lua_upvalueindex(1));
        del.funcptr = cast(typeof(del.funcptr))
            lua_touserdata(state, lua_upvalueindex(2));
        return callFromLua(del, state, 0, "some D delegate");
    }

    lua_pushlightuserdata(state, del.ptr);
    lua_pushlightuserdata(state, del.funcptr);
    lua_pushcclosure(state, &demarshal, 2);
}

//same as "Wrapper" and same idea from before
//garbage collection: maybe put all wrapper objects into a weaklist, and do
//  regular cleanups (e.g. each game frame); the weaklist would return the set
//  of dead objects free'd since the last query, and the Lua delegate table
//  entry could be removed without synchronization problems
private abstract class LuaDelegateWrapper {
    private {
        lua_State* mState;
        int mLuaRef = LUA_NOREF;
    }

    private this(lua_State* state, int stackIdx) {
        mState = state;

        //put a "Lua ref" to the closure into the delegate table
        lua_getfield(mState, LUA_REGISTRYINDEX, cLuaDelegateTable.ptr);
        lua_pushvalue(mState, stackIdx);
        mLuaRef = luaL_ref(mState, -2);
        assert(mLuaRef != LUA_REFNIL);
    }

    void release() {
        if (mLuaRef == LUA_NOREF)
            return;
        lua_getfield(mState, LUA_REGISTRYINDEX, cLuaDelegateTable.ptr);
        luaL_unref(mState, -1, mLuaRef);
        mLuaRef = LUA_NOREF;
    }
}

private class LuaDelegateWrapperT(T) : LuaDelegateWrapper {
    alias ParameterTupleOf!(T) Params;
    alias ReturnTypeOf!(T) RetType;

    //only to be called from luaStackDelegate()
    private this(lua_State* state, int stackIdx) {
        super(state, stackIdx);
    }

    ~this() {
        //--D GC is completely asynchronous and indeterministic; if this
        //--    dtor brings anything, then only segfaults on random
        //--    occasions; don't know how to solve this (maybe do the
        //--    same crap as with surfaces in the framework)
        //--release();
    }

    //delegate to this is returned by luaStackDelegate/luaStackValue!(T)
    RetType cbfunc(Params args) {
        assert(mLuaRef != LUA_NOREF, "call delegate after .release()");
        //get callee from the registry and call
        lua_getfield(mState, LUA_REGISTRYINDEX, cLuaDelegateTable.ptr);
        lua_rawgeti(mState, -1, mLuaRef);
        //replace ref to delegate table by closure (stack cleanup)
        lua_replace(mState, -2);
        assert(lua_isfunction(mState, -1));
        //will pop function from the stack
        return doLuaCall!(RetType, Params)(mState, args);
    }
}

//convert a Lua function on that stack index to a D delegate
private T luaStackDelegate(T)(lua_State* state, int stackIdx) {
    //the lua function to call is at stackIdx and must be stored for later
    //  calling.
    if (lua_isnil(state, stackIdx))
        return null;
    if (!lua_isfunction(state, stackIdx))
        luaExpected(state, stackIdx, "closure");

    //xxx: could cache wrappers (Lua can do the Lua closure => unique int key
    //  mapping), but D has no such thing as weak hashtables
    auto pwrap = new LuaDelegateWrapperT!(T)(state, stackIdx);
    return &pwrap.cbfunc;
}

//call the function on top of the stack
private RetType doLuaCall(RetType, T...)(lua_State* state, T args) {
    int argc;
    foreach (int idx, x; args) {
        argc += luaPush(state, args[idx]);
    }
    const bool ret_void = is(RetType == void);
    lua_call(state, argc, ret_void ? 0 : 1);
    static if (!ret_void) {
        RetType res = luaStackValue!(RetType)(state, -1);
        lua_pop(state, 1);
        return res;
    }
}

//Execute the callable del, taking parameters from the lua stack
//  skipCount: skip this many parameters from beginning
//  funcName:  used in error messages
//stack size must match the requirements of del
static int callFromLua(T)(T del, lua_State* state, int skipCount,
    char[] funcName)
{
    //eh static assert(is(T == delegate) || is(T == function));

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
    } catch (AssertException e) {
        //go boom immediately to avoid confusion
        //this should also be done for other "runtime" exceptions, but at least
        //  in D1, the exception class hierarchy is too retarded and you have
        //  to catch every single specialized exception type (got fixed in D2)
        Trace.formatln("catching failing assert before returning to Lua:");
        e.writeOut((char[] s) { Trace.format("{}", s); });
        Trace.formatln("done, will die now.");
        asm { hlt; }
    } catch (Exception e) {
        raiseLuaError(state, e.msg);
    }
}

class LuaRegistry {
    private {
        Method[] mMethods;
        char[][ClassInfo] mPrefixes;
    }

    enum MethodType {
        Method,
        Property_R,
        Property_W,
        Ctor,
        FreeFunction,
    }

    struct Method {
        ClassInfo classinfo;
        char[] name;
        char[] prefix;
        char[] fname;
        bool is_static;
        lua_CFunction demarshal;
        MethodType type;
    }

    this() {
        DerelictLua.load();
    }

    //e.g. setClassPrefix!(GameEngine)("Game"), to keep scripting names short
    //call before any method() calls
    void setClassPrefix(Class)(char[] name) {
        mPrefixes[Class.classinfo] = name;
    }

    private void registerDMethod(ClassInfo ci, char[] method,
        lua_CFunction demarshal, MethodType type)
    {
        Method m;
        m.name = method;
        m.fname = method;
        if (type == MethodType.Property_W) {
            m.fname = "set_" ~ m.fname;
        }
        if (ci) {
            //BlaClass.somemethod becomes BlaClass_somemethod in Lua
            char[] clsname;
            if (auto cn = ci in mPrefixes) {
                clsname = *cn;
            } else {
                clsname = ci.name;
                //strip package/module path
                int i = str.rfind(clsname, ".");
                if (i >= 0) {
                    clsname = clsname[i+1..$];
                }
                mPrefixes[ci] = clsname;
            }
            m.classinfo = ci;
            m.prefix = clsname;
            m.fname = clsname ~ "_" ~ m.fname;
        } else {
            assert(type == MethodType.FreeFunction);
        }
        m.demarshal = demarshal;
        m.type = type;
        mMethods ~= m;
    }

    private static char[] methodThisError(char[] name, ClassInfo expected,
        Object got)
    {
        return myformat("method call to '{}' requires non-null "
            "this pointer of type {} as first argument, but got: {}", name,
            expected.name, got ? got.classinfo.name : "*null");
    }

    //Register a class method
    void method(Class, char[] name)(char[] rename = null) {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;

            Object o = cast(Object)lua_touserdata(state, 1);
            Class c = cast(Class)(o);

            if (!c) {
                raiseLuaError(state, methodThisError(methodName,
                    Class.classinfo, o));
            }

            auto del = mixin("&c."~name);
            return callFromLua(del, state, 1, methodName);
        }

        registerDMethod(Class.classinfo, rename.length ? rename : name,
            &demarshal, MethodType.Method);
    }

    //a constructor for a given class
    //there can be multiple ctors and they can't be named => PITA
    //you have to explicitly pass the argument types and a name
    void ctor(Class, Args...)(char[] name = "ctor") {
        extern(C) static int demarshal(lua_State* state) {
            const cDebugName = "constructor " ~ Class.stringof;
            static Class construct(Args args) {
                //if you get an error here, it means ctor registration and
                //  declaration mismatch
                return new Class(args);
            }
            return callFromLua(&construct, state, 0, cDebugName);
        }

        registerDMethod(Class.classinfo, name, &demarshal, MethodType.Ctor);
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
            const cDebugName = "property get " ~ name;
            static Type get(Class o) {
                if (!o) {
                    throw new LuaException(methodThisError(cDebugName,
                        Class.classinfo, null));
                }
                return mixin("o." ~ name);
            }
            return callFromLua(&get, state, 0, cDebugName);
        }

        registerDMethod(ci, name, &demarshal_get, MethodType.Property_R);

        static if (rw) {
            //xxx: a bit strange how it does three nested calls for stuff known
            //     at compile time...
            extern(C) static int demarshal_set(lua_State* state) {
                const cDebugName = "property set " ~ name;
                static void set(Class o, Type t) {
                    if (!o) {
                        throw new LuaException(methodThisError(cDebugName,
                            Class.classinfo, null));
                    }
                    //mixin() must be an expression here, not a statement
                    //but the parser messes it up, we don't get an expression
                    //make use of the glorious comma operator to make it one
                    //"I can't believe this works"
                    1, mixin("o." ~ name) = t;
                }
                return callFromLua(&set, state, 0, cDebugName);
            }

            registerDMethod(ci, name, &demarshal_set, MethodType.Property_W);
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

    //also a shortcut
    void properties_ro(Class, Names...)() {
        foreach (int idx, _; Names) {
            property_ro!(Class, Names[idx])();
        }
    }

    //Register a function
    void func(alias Fn)(char[] rename = null) {
        //stringof returns "& functionName", strip that
        const funcName = (&Fn).stringof[2..$];
        extern(C) static int demarshal(lua_State* state) {
            return callFromLua(&Fn, state, 0, funcName);
        }
        registerDMethod(null, rename.length ? rename : funcName, &demarshal,
            MethodType.FreeFunction);
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

    void methods(Names...)() {
        registry.methods!(Class, Names)();
    }

    void property(char[] name, bool rw = true)() {
        registry.property!(Class, name, rw)();
    }

    void properties(Names...)() {
        registry.properties!(Class, Names)();
    }

    void property_ro(char[] name)() {
        registry.property!(Class, name, false)();
    }

    void properties_ro(Names...)() {
        registry.properties_ro!(Class, Names)();
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
        char[][ClassInfo] mClassNames;
        Object[ClassInfo] mSingletons;
    }

    const cLanguageAndVersion = LUA_VERSION;

    this(int stdlibFlags = LuaLib.safe) {
        mLua = lua_newstate(&my_lua_alloc, null);
        lua_atpanic(mLua, &my_lua_panic);
        loadStdLibs(stdlibFlags);

        //this is security relevant; allow only in debug code
        debug loadStdLibs(LuaLib.debuglib);

        //list of active delegates
        lua_newtable(mLua);
        lua_setfield(mLua, LUA_REGISTRYINDEX, cLuaDelegateTable.ptr);

        //own std stuff
        auto reg = new LuaRegistry();
        reg.func!(ObjectToString)();
        register(reg);

        //passing a userdata as light userdata causes a demarshal error
        //which means utils.formatln() could cause an error by passing userdata
        //  to ObjectToString(); but there doesn't seem to be a way for Lua
        //  code to distinguish between userdata and light userdata
        extern (C) static int d_islightuserdata(lua_State* state) {
            int light = lua_islightuserdata(state, 1);
            lua_pop(state, 1);
            lua_pushboolean(state, light);
            return 1;
        }
        lua_pushcfunction(mLua, &d_islightuserdata);
        lua_setglobal(mLua, "d_islightuserdata".ptr);

        void kill(char[] global) {
            lua_pushnil(mLua);
            lua_setglobal(mLua, czstr.toStringz(global));
        }

        //dofile and loadfile are unsafe, and even worse, freeze your program
        //  if called with no argument (because they want to read from stdin)
        kill("dofile");
        kill("loadfile");

        stack0();

        scriptExec(`_G.d_get_obj_metadata = ...`, &script_get_obj_metadata);
    }

    void destroy() {
        //let the GC do the work (for now)
        mLua = null;
    }

    final lua_State* state() {
        return mLua;
    }

    //return memory used by Lua in bytes
    final size_t vmsize() {
        return lua_gc(mLua, LUA_GCCOUNT, 0)*1024
            + lua_gc(mLua, LUA_GCCOUNTB, 0);
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

    void register(LuaRegistry stuff) {
        foreach (m; stuff.mMethods) {
            auto name = czstr.toStringz(m.fname);

            lua_getglobal(mLua, name);
            bool nil = lua_isnil(mLua, -1);
            lua_pop(mLua, 1);

            if (!nil) {
                //this caused some error which took me 30 minutes of debugging
                //most likely multiple bind calls for a method
                throw new Exception("attempting to overwrite existing name "
                    "in _G when adding D method: "~m.fname);
            }

            lua_pushcclosure(mLua, m.demarshal, 0);
            lua_setglobal(mLua, name);

            mMethods ~= m;
        }
        foreach (ClassInfo key, char[] value; stuff.mPrefixes) {
            mClassNames[key] = value;
        }
    }

    struct MetaData {
        char[] type;        //stringified LuaRegistry.MethodType
        char[] dclass;      //name/prefix of the D class for the method
        char[] name;        //name of the mthod
        char[] lua_g_name;  //name of the Lua bind function in _G
    }
    //return MetaData for all known bound D functions for the passed object
    //if from is null, an empty array is returned
    private MetaData[] script_get_obj_metadata(Object from) {
        if (!from)
            return null;
        MetaData[] res;
        foreach (LuaRegistry.Method m; mMethods) {
            if (rtraits.isDerived(from.classinfo, m.classinfo))
                res ~= convert_md(m);
        }
        return res;
    }
    private MetaData convert_md(LuaRegistry.Method m) {
        alias LuaRegistry.MethodType MT;
        MetaData d;
        switch (m.type) {
            case MT.Method: d.type = "Method"; break;
            case MT.Property_R: d.type = "Property_R"; break;
            case MT.Property_W: d.type = "Property_W"; break;
            case MT.Ctor: d.type = "Ctor"; break;
            case MT.FreeFunction: d.type = "FreeFunction"; break;
        }
        d.dclass = m.prefix;
        d.name = m.name;
        d.lua_g_name = m.fname;
        return d;
    }

    void addSingleton(T)(T instance) {
        addSingletonD(T.classinfo, instance);
    }

    //non-templated
    //xxx actually, this should follow the inheritance chain, shouldn't it?
    //    would be a problem, because not all superclasses would be singleton
    //let's just say this singleton stuff is broken design
    void addSingletonD(ClassInfo ci, Object instance) {
        assert(!!instance);
        assert(!!ci);
        assert(!(ci in mSingletons));
        mSingletons[ci] = instance;

        //just rewrite the already registered methods
        //if methods are added after this call, the user is out of luck
        stack0();
        foreach (m; mMethods) {
            if (m.classinfo !is ci)
                continue;
            if (m.is_static)
                continue;
            //the method name is the same, just that the singleton is now
            //  automagically added on a call (not sure if that's a good idea)
            scriptExec(`
                local fname, singleton = ...
                local orgfunction = _G[fname]
                local function dispatch(...)
                    -- yay closures
                    return orgfunction(singleton, ...)
                end
                _G[fname] = dispatch
            `, m.fname, instance);
        }
        stack0();

        //add a global variable for the singleton (script can use it)
        if (auto pname = ci in mClassNames) {
            char[] name = *pname;
            scriptExec(`local name, inst = ...; _G[name] = inst`,
                name, instance);
        }
    }

    private void lua_loadChecked(lua_Reader reader, void *d, char[] chunkname) {
        //'=' means use the name as-is (else "string " is added)
        int res = lua_load(mLua, reader, d, czstr.toStringz('='~chunkname));
        if (res != 0) {
            scope (exit) lua_pop(mLua, 1);  //remove error message
            char[] err = lua_todstring(mLua, -1);
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

    void luaLoadAndPush(char[] name, Stream input) {
        lua_loadChecked(&lua_ReadStream, cast(void*)input, name);
    }

    //another variation
    //load script in "code", using "name" for error messages
    //there's also scriptExec() if you need to pass parameters
    void loadScript(char[] name, char[] code) {
        stack0();
        luaLoadAndPush(name, code);
        luaCall!(void)();
        stack0();
    }
    void loadScript(char[] name, Stream input) {
        stack0();
        luaLoadAndPush(name, input);
        luaCall!(void)();
        stack0();
    }
    //load code from stream and assign it the env. environmentId
    //the environment will be created if it doesn't exist, and reused if it does
    //a metatable is set to forward lookups to the globals table
    //(see http://lua-users.org/lists/lua-l/2006-05/msg00121.html )
    void loadScriptEnv(char[] name, char[] environmentId, Stream input) {
        stack0();
        luaLoadAndPush(name, input);

        //check if the environment was defined before
        lua_getfield(mLua, LUA_REGISTRYINDEX, envMangle(environmentId));
        if (!lua_istable(mLua, -1)) {
            lua_pop(mLua, 1);
            //new environment
            lua_newtable(mLua);

            //environment metatable
            lua_newtable(mLua);
            //meta = { __index = _G }
            lua_pushvalue(mLua, LUA_GLOBALSINDEX);
            lua_setfield(mLua, -2, "__index");
            lua_setmetatable(mLua, -2);

            //store for later use
            lua_pushvalue(mLua, -1);
            lua_setfield(mLua, LUA_REGISTRYINDEX, envMangle(environmentId));
        }

        lua_setfenv(mLua, -2);
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

    //store a value as global Lua variable
    //slightly inefficient (because of toStringz heap activity)
    void setGlobal(T)(char[] name, T value) {
        stack0();
        luaPush(mLua, value);
        lua_setglobal(mLua, czstr.toStringz(name));
        stack0();
    }
    T getGlobal(T)(char[] name) {
        stack0();
        lua_getglobal(mLua, czstr.toStringz(name));
        T res = luaStackValue!(T)(mLua, 1);
        lua_pop(mLua, 1);
        stack0();
        return res;
    }

    //this redirects the print() function from stdio to cb(); the string passed
    //  to cb() should be output literally (the string will contain newlines)
    void setPrintOutput(void delegate(char[]) cb) {
        assert(cb !is null);
        //xxx: actually, it completely replaces the print() function, and it
        //  might behave a little bit differently; feel free to fix it
        scriptExec(`
            local d_out = ...
            _G["print"] = function(...)
                local args = {...}
                for i, s in ipairs(args) do
                    if i > 1 then
                        -- Lua uses \t here
                        d_out("\t")
                    end
                    d_out(tostring(s))
                end
                d_out("\n")
            end
        `, cb);
    }

    void stack0() {
        assert(lua_gettop(mLua) == 0);
    }

    //assign a lua-defined metatable tableName to a D struct type
    void addScriptType(T)(char[] tableName) {
        //get the metatable from the global scope and write it into the registry
        lua_getfield(mLua, LUA_GLOBALSINDEX, czstr.toStringz(tableName));
        lua_setfield(mLua, LUA_REGISTRYINDEX, C_Mangle!(T).ptr);
    }
}

//test for http://d.puremagic.com/issues/show_bug.cgi?id=2881
//(other static asserts will throw; this is just to output a good error message)
private enum _Compiler_Test {
    x,
}
private _Compiler_Test _test_enum;
static assert(_test_enum.stringof == "_test_enum", "Get a dmd version "
    "where #2881 is fixed (or patch dmd yourself)");
