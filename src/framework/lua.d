module framework.lua;

import derelict.lua.lua;
import czstr = tango.stdc.stringz;
import cstdlib = tango.stdc.stdlib;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType,
    ElementTypeOfArray, isArrayType, isAssocArrayType, KeyTypeOfAA, ValTypeOfAA,
    ReturnTypeOf, isStaticArrayType;
import rtraits = tango.core.RuntimeTraits;
import env = tango.sys.Environment;
import tango.core.WeakRef : WeakRef;
import tango.core.Exception;

import str = utils.string;
import utils.list2;
import utils.misc;
import utils.stream;
import utils.strparser;
import utils.time;      //for special Time marshalling

/+
Error handling notes:
- should never mix Lua C API or D error handling: a piece of code should either
  use D exceptions, or Lua's error handling (lua_pcall/lua_error)
  see http://lua-users.org/wiki/ErrorHandlingBetweenLuaAndCplusplus
- normal D exceptions are "tunneled" through the Lua stack by using the D
  exception as userdata Lua error value; they can be catched by Lua scripts
- unrecoverable D exceptions (assertions, out of memory errors, ...) usually
  lead to a corrupted program state, and should never be catchable by Lua and
  are never catched by D (that is, at least in our code)
  list of exceptions considered unrecoverable (by us):
    Exception itself, OutOfMemoryException, SwitchException, AssertException,
    UnicodeException (probably), ArrayBoundsException, FinalizeException,
    AccessViolation, ...?

D error handling domain:
- never raise raw Lua errors
- may throw Lua errors wrapped inside exceptions (LuaException)
- can throw CustomExceptions (that includes LuaExceptions)
- if Lua calls D code which throws a CustomException, the wrapper will wrap that
  into a LuaException (if it isn't already a LuaException)

Lua error handling domain:
- won't throw any recoverable D exceptions (CustomException)
- will raise Lua errors (longjmp)
- any recoverable exceptions thrown by del are converted into lua errors
- as a hack, unrecoverable exceptions are "allowed" => you can use things like
  assert() or D memory allocation

Neutral error handling domain (often used in error handler code itself):
- won't throw CustomExceptions
- won't raise Lua errors (not even out-of-memory ones)
- may throw unrecoverable exceptions

Going from...
- D -> Lua: use luaProtected()
- Lua -> D: use a try-catch block and then luaDError(), such as in callFromLua

Most functions starting with lua* are in the Lua error handling domain.
The user (D code outside of this module) always is in D error handling domain.

XXX: right now, we rely on D being able to unwind the Lua stack in case of
    unrecoverable exceptions to crash gracefully. it would be fine to crash at
    any point before this: all what we really want is a nice backtrace, and then
    fix the code so it never happens again. (the only such exception that may
    happen even with bugfree code is OutOfMemoryException, but when that happens
    we're done for anyway and can't really resume.)
    this could be fixed by wrapping all "bottom most" D code called from Lua
    (i.e. all functions added via lua_pushcclosure/lua_pushcfunction) into a
    try-catch, and call abort() in the catch block to terminate the program. we
    couldn't call lua_error(), because Lua scripts could simply catch the error
    via pcall().

XXX2: there's still some trouble when Lua scripts raise errors in strange
    locations. e.g. a script can set a metatable on _G, and raise an error in
    the "index" method. then D code calling LuaState.getGlobal() will receive
    a LuaException. maybe we want to take the same approach like with delegates
    here: if a Lua closure wrapped as D delegate raises an error, the error is
    handed to LuaState.reportDelegate. the user can set a callback that prints
    out an error message and then ignores the error (the D delegate will just
    return).
+/

//comment this to disable unsafe debug extensions
//Warning: leaving this enabled has security implications
debug version = DEBUG_UNSAFE;

//counters incremented on each function call
//doesn't include Lua builtin/stdlib calls or manually registered calls
debug int gLuaToDCalls, gDToLuaCalls;

//total number of D->Lua/Lua->D references that have been created
debug int gDLuaRefs, gLuaDRefs;

//this alias is just so that we can pretend our scripting interface is generic
alias LuaException ScriptingException;
alias LuaState ScriptingState;

//--- stuff which might appear as keys in the Lua "Registry"
/+
In general:
- all integer indices are reserved for the luaL_ref mechanism, and Lua 5.2 uses
  some integer keys for internal stuff (LUA_RIDX_*)
- luaPush/LuaState.addScriptType map registry[lud]=type_table, where lud is
  the type's TypeInfo wrapped as light userdata
- stuff that needs to be fast or is used in critical glue code uses light
  userdata as keys (although the speed thing could be an illusion)
- string keys should use "D_" as prefix
+/

//table that maps chunk_name->environment_table
const char[] cEnvTable = "D_chunk_environment";

//c closure used as __gc metatable function - frees D object wrappers
const char[] cGCHandler = "D_gc_handler";

//map ClassInfos (wrapped as light userdata) to the userdata metatables
const char[] cMetatableCache = "D_metatables";

//the _addresses_ of these are wrapped as lightuserdata, and then used as key in
//  the registry; doing this for speed and safety (no string hashing/allocation)
private {
    //reference to LuaState
    int cLuaStateKey;
    //the table with all cached objects (must be separate because weak values)
    int cRefCacheKey;
    //"ID" table for userdata wrapping D objects
    int cDObjectUDKey;
    //the error handler c closures
    int cPInvokeHandlerKey;
    int cErrorHandlerKey;
}

//--- Lua "Registry" stuff end


private struct UD_Object {
    Object o;
    int pinID; //hack to make pinning code simpler
}


//panic function: called on unprotected lua error (message is on the stack)
//if all code is correct, it will never be called, except on:
//- out of memory errors in early initialization
//- failures in error handler
private extern(C) int my_lua_panic(lua_State *L) {
    assert(false, "(should be) unused");
}

//if the string is going to be used after the Lua value is popped from the
//  stack, you must .dup it (Lua may GC and reuse the string memory)
//this is an optimization; if unsure, use lua_todstring()
//if geterr is set, assign it the error message, instead of raising an error
//error handling: Lua domain
private char[] lua_todstring_unsafe(lua_State* L, int i, char[]* geterr = null)
{
    size_t len;
    char* s = lua_tolstring(L, i, &len);
    char[] error;
    if (!s) {
        error = "lua_todstring: string expected";
        goto Lerror;
    }
    char[] res = s[0..len];
    //as long as the D program is rather fragile about utf-8 errors (anything
    //  parsing utf-8 will throw UnicodeException on invalid utf-8 => basically
    //  that exception may be thrown from random parts of the program), always
    //  disallow Lua to pass invalid utf-8
    try {
        str.validate(res);
    } catch (str.UnicodeException s) {
        //not sure if it should be this exception
        error = "lua_todstring: invalid utf-8 string";
        goto Lerror;
    }
    return res;

    //blame the Lua API or something for the heretic goto
Lerror:
    if (geterr) {
        *geterr = error;
    } else {
        luaErrorf(L, "{}", error);
    }
    return "";
}

//always allocates memory (except if string has len 0)
private char[] lua_todstring(lua_State* L, int i) {
    return lua_todstring_unsafe(L, i).dup;
}

//like lua_todstring, but returns error messages in the string
//xxx: may still lua_error is certain cases, see lua_tolstring
private char[] lua_todstring_protected(lua_State* L, int i) {
    char[] err;
    auto res = lua_todstring_unsafe(L, i, &err).dup;
    if (err.length)
        return "<error: " ~ err ~ ">";
    return res;
}

//if index is a relative stack index, convert it to an absolute one
//  e.g. -2 => 4 (if stack size is 5)
//there's also (unaccessible):
//  http://www.lua.org/source/5.1/lauxlib.c.html#abs_index
private int luaRelToAbsIndex(lua_State* state, int index) {
    if (index < 0) {
        //the tricky part is dealing with pseudo-indexes (also non-negative)
        int stacksize = lua_gettop(state);
        if (index <= -1 && index >= -1 - stacksize)
            index = stacksize + 1 + index;
    }
    return index;
}

//version of luaL_where() that returns the result directly (no Lua stack)
//code taken from http://www.lua.org/source/5.1/lauxlib.c.html#luaL_where (MIT)
private char[] luaWhere(lua_State* L, int level) {
    lua_Debug ar;
    if (lua_getstack(L, level, &ar)) {  /* check function at level */
        lua_getinfo(L, "Sl", &ar);  /* get info about it */
        if (ar.currentline > 0) {  /* is there info? */
            return myformat("{}:{}: ", czstr.fromStringz(ar.short_src.ptr),
                ar.currentline);
        }
    }
    /* else, no information available... */
    return "";
}

//Source: http://www.lua.org/source/5.1/ldblib.c.html#db_errorfb
//License: MIT
//looks like Lua 5.2 will have luaL_traceback(), making this unneeded
private char[] luaStackTrace(lua_State* state, int level = 1) {
    const LEVELS1 = 12;      /* size of the first part of the stack */
    const LEVELS2 = 10;      /* size of the second part of the stack */

    char[] ret;
    int firstpart = 1;  /* still before eventual `...' */
    lua_Debug ar;
    while (lua_getstack(state, level++, &ar)) {
        if (level > LEVELS1 && firstpart) {
            /* no more than `LEVELS2' more levels? */
            if (!lua_getstack(state, level+LEVELS2, &ar))
                level--;  /* keep going */
            else {
                ret ~= "\n\t...";  /* too many levels */
                while (lua_getstack(state, level+LEVELS2, &ar))  /* find last levels */
                    level++;
            }
            firstpart = 0;
            continue;
        }
        ret ~= "\t";
        lua_getinfo(state, "Snl", &ar);
        ret ~= czstr.fromStringz(ar.short_src.ptr) ~ ":";
        if (ar.currentline > 0)
            ret ~= myformat("{}:", ar.currentline);
        if (*ar.namewhat != '\0')  /* is there a name? */
            ret ~= myformat(" in function '{}'", czstr.fromStringz(ar.name));
        else {
            if (*ar.what == 'm')  /* main? */
                ret ~= " in main chunk";
            else if (*ar.what == 'C' || *ar.what == 't')
                ret ~= " ?";  /* C function or tail call */
            else
                ret ~= myformat(" in function <{}:{}>",
                    czstr.fromStringz(ar.short_src.ptr), ar.linedefined);
        }
        ret ~= "\n";
    }
    return ret.length ? ret[0..$-1] : ret;
}

//public exception type ("what the user sees")
class LuaException : CustomException {
    //NOTE: the member next (from Exception) is used if a D exception caused
    //  this exception (e.g. Lua calls D code, D code throws ParameterException,
    //  wrapper glue catches the exception, and throws a new LuaException with
    //  LuaException.next = ParameterException)
    //lua_message and lua_traceback are from the first lua_pcall error handler
    //  function (lua_message is empty if a D exception was the cause)
    //the wrapper code doesn't handle the case when there are multiple lua
    //  states, so there's only one lua_traceback (even if the Lua code jumps
    //  between nested Lua and D code multiple times)
    char[] lua_message;
    char[] lua_traceback;

    //state, level are passed to stackTrace
    //Important: the ONLY place where this constructor should be used is
    //  from lua_pcall's error function; the stack trace is generated here
    //  and nowhere else
    this(lua_State* state, int level, char[] msg, Exception next) {
        auto nmsg = msg;
        //Note: pure lua errors will already contain filename/linenumber
        //  (unless the user is stupid enough to call error() with a non-string)
        if (next) {
            //"level" is the D function that caused the exception,
            //  so the lua pos is at level + 1
            char[] codePos = luaWhere(state, level + 1);
            nmsg = codePos ~ "D " ~ className(next) ~ " [" ~ next.msg ~ "]";
        }
        //also append the trace like it used to be
        //but I think this should be changed
        auto trace = luaStackTrace(state, level);
        nmsg ~= ". Lua backtrace:\n" ~ trace;
        super(nmsg, next);
        if (!next) { //stupid ctor rules make me write stupid code
            lua_message = msg;
        }
        lua_traceback = trace;
    }

    //true: caused by lua_error() or Lua error() function
    //false: caused by a recoverable D exception when Lua called D code
    bool isNativeLuaError() {
        return !!next;
    }
}

//recoverable exceptions are wrapped as Lua errors,
//  and unwind the stack via a longjmp in lua_error()
//the lua_pcall error handler will catch it and wrap it in a LuaException
//if Lua raises an error via lua_error()/error(), lua_pcall's error handler will
//  catch that and create a new LuaException accordingly
private void luaDError(lua_State* state, CustomException e) {
    assert(!!e);
    LuaState.luaPushDObject(state, e);
    lua_error(state);
}

//similar to luaL_error(), but with Tango formatter instead of C sprintf
//allocates memory
//xxx: maybe in the future, we may want to add D backtrace info??
private void luaErrorf(lua_State* state, char[] fmt, ...) {
    char[] error = myformat_fx(fmt, _arguments, _argptr);
    //old implementation: luaDError(state, new LuaError(error));
    lua_pushlstring(state, error.ptr, error.length);
    lua_error(state);
}

private char[] className(Object o) {
    if (!o) {
        return "null";
    }
    char[] ret = o.classinfo.name;
    return ret[str.rfind(ret, '.')+1..$];
}

private char[] fullClassName(Object o) {
    if (!o) {
        return "null";
    }
    return o.classinfo.name;
}

private bool canCast(ClassInfo from, ClassInfo to) {
    return rtraits.isImplicitly(from, to);
}

private void luaExpected(lua_State* state, int stackIdx, char[] expected) {
    char* s = luaL_typename(state, stackIdx);
    luaExpected(state, expected, czstr.fromStringz(s));
}
private void luaExpected(lua_State* state, char[] expected, char[] got) {
    luaErrorf(state, "{} expected, got {}", expected, got);
}

//if this returns a TempString, you can use it only until you pop the
//  corresponding Lua value from the stack (because after this, Lua may garbage
//  collect it); char[] values are .dup'ed on the D heap
//Lua error domain
private T luaStackValue(T)(lua_State *state, int stackIdx) {
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
            T res;
            try {
                return stringToType!(T)(lua_todstring_unsafe(state, stackIdx));
            } catch (ConversionException e) {
                expected("enum "~T.stringof~"( error: " ~ e.msg ~ ")");
            }
            assert(false, "unreachable");
        } else {
            //try base type
            return cast(T)luaStackValue!(Base)(state, stackIdx);
        }
    } else static if (is(T : bool)) {
        //now more strict
        if (lua_type(state, stackIdx) != LUA_TBOOLEAN)
            expected("boolean");
        //accepts everything, true for anything except 'false' and 'nil'
        return !!lua_toboolean(state, stackIdx);
    } else static if (is(T : char[])) {
        //TempString just means that the string may be deallocated later
        //Lua will keep the string as long as it is on the Lua script's stack
        return luaStackValue!(TempString)(state, stackIdx).raw.dup;
    } else static if (is(T == TempString)) {
        //there is the strange behaviour that tolstring may change the stack
        //  value, if the value is a number, and that can cause trouble with
        //  other functions - thus, better reject numbers
        //http://www.lua.org/manual/5.1/manual.html#lua_tolstring
        //NOTE: lua_isstring returns true for numbers (implicitly convertible
        //  to string), but I'd say "fuck implicit conversion to string"
        if (lua_type(state, stackIdx) == LUA_TSTRING)
            return TempString(lua_todstring_unsafe(state, stackIdx));
        expected("string");
    } else static if (is(T == LuaReference)) {
        return new LuaReference(state, stackIdx);
    } else static if (is(T == Object)) {
        return LuaState.luaToDObject(state, stackIdx);
    } else static if (is(T == class) || is(T == interface)) {
        Object o = LuaState.luaToDObject(state, stackIdx);
        T res = cast(T)o;
        if (o && !res) {
            luaExpected(state, T.classinfo.name, o.classinfo.name);
        }
        return res;
    } else static if (is(T == Time)) {
        return timeSecs!(double)(luaStackValue!(double)(state, stackIdx));
    } else static if (is(T == struct)) {
        //Note: supports both {x = 1, y = 2} and {1, 2} access mode,
        //      but mixing both in one declaration will fail horribly
        if (!lua_istable(state, stackIdx))
            expected("struct table");
        T ret;
        int tablepos = luaRelToAbsIndex(state, stackIdx);
        const char[][] membernames = structMemberNames!(T)();
        version (none) {
        //the code below works well, but it can't detect table entries that
        //  are not part of the struct (changing this would make it very
        //  inefficient)
            foreach (int idx, x; ret.tupleof) {
                //first try named access
                luaPush(state, memernames);
                lua_rawget(state, tablepos);   //replaces key by value
                if (lua_isnil(state, -1)) {
                    //named access failed, try indexed
                    lua_pop(state, 1);
                    luaPush(state, idx+1);
                    lua_rawget(state, tablepos);
                }
                if (!lua_isnil(state, -1)) {
                    ret.tupleof[idx] = luaStackValue!(typeof(ret.tupleof[idx]))(
                        state, -1);
                }
                lua_pop(state, 1);
            }
        } else {
        //alternative marshaller, which doesn't allow passing unused entries
        //it may be slightly slower if there are many struct items
        //actually, I'm not so sure; at least this version doesn't need to
        //  rehash the string for the name of each struct item
        //in any case, the code is more complicated, but I wanted to have it
        //  for debugging
        //it also detects mixed by-name/by-index access
            const cTName = "'struct " ~ T.stringof ~ "'";
            int mode = 0; //0: not known yet, 1: by-name, 2: by-index
            lua_pushnil(state);  //first key
            while (lua_next(state, tablepos) != 0) {
                //lua_next pushes: -2 = key, -1 = value
                auto keytype = lua_type(state, -2);
                if (keytype == LUA_TNUMBER) {
                    //array mode
                    if (mode != 0 && mode != 2)
                        luaExpected(state, -2, "string key");
                    mode = 2;
                    auto idx = lua_tonumber(state, -2);
                    int iidx = cast(int)idx;
                    if (iidx < 1 || iidx > ret.tupleof.length || iidx != idx) {
                        luaExpected(state, "valid integer index for " ~ cTName,
                            myformat("invalid index {}", idx));
                    }
                    iidx -= 1; //lua arrays are 1-based
                    //this loop must be a major WTF for people who don't know D
                    foreach (int sidx, x; ret.tupleof) {
                        if (sidx == iidx) {
                            ret.tupleof[sidx] =
                                luaStackValue!(typeof(x))(state, -1);
                            break;
                        }
                    }
                } else if (keytype == LUA_TSTRING) {
                    //named access mode
                    if (mode != 0 && mode != 1)
                        luaExpected(state, -2, "integer index");
                    mode = 1;
                    char[] name = lua_todstring_unsafe(state, -2);
                    bool ok = false;
                    foreach (int sidx, x; ret.tupleof) {
                        if (membernames[sidx] == name) {
                            ret.tupleof[sidx] =
                                luaStackValue!(typeof(x))(state, -1);
                            ok = true;
                            break;
                        }
                    }
                    if (!ok)
                        luaExpected(state, "valid member for "~cTName,
                            "'"~name~"'");
                } else {
                    expected("string or integer number as key in struct table");
                }
                lua_pop(state, 1);   //pop value, leave key
            }
        }
        return ret;
    } else static if (isArrayType!(T) || isAssocArrayType!(T)) {
        const is_assoc = isAssocArrayType!(T);
        if (!lua_istable(state, stackIdx))
            expected("array table");
        T ret;
        int tablepos = luaRelToAbsIndex(state, stackIdx);
        static if (!is_assoc) {
            //static arrays would check if the size is the same
            //but this function will never support static arrays (in D1)
            //xxx change to lua_rawlen in Lua 5.2
            auto tlen = lua_objlen(state, tablepos);
            //xxx evil Lua scripts could easily cause an out of memory error
            //  due to '#' not returning the array length, but something
            //  along the last integer key (see Lua manual)
            ret.length = tlen;
        }
        //arrays are the only data structure that cause data to be read
        //  recursively, and may lead to infinite recursion
        //so use checkstack to ensure the Lua stack either gets extended, or
        //  an out of memory Lua error is raised
        //note that in Lua accessing past the end of the stack causes random
        //  memory corruption (except if Lua is compiled with LUA_USE_APICHECK)
        luaL_checkstack(state, LUA_MINSTACK/2, "Lua stack out of memory");
        lua_pushnil(state);  //first key
        while (lua_next(state, tablepos) != 0) {
            //lua_next pushes key, then value
            static if(is_assoc) {
                auto curVal = luaStackValue!(ValTypeOfAA!(T))(state, -1);
                ret[luaStackValue!(KeyTypeOfAA!(T))(state, -2)] = curVal;
            } else {
                auto index = luaStackValue!(int)(state, -2);
                if (index < 1 || index > ret.length)
                    luaErrorf(state, "invalid index in lua array"
                        " table: got {} in range 1-{}", index, ret.length+1);
                index -= 1; //1-based arrays
                ret[index] = luaStackValue!(ElementTypeOfArray!(T))(state, -1);
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
//XXX: ok that tuple return is really weird... should be killed off IMHO
//Lua error domain
private int luaPush(T)(lua_State *state, T value) {
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
    } else static if (is(T == LuaReference)) {
        if (value.valid()) {
            value.push(state);
        } else {
            //good enough (or better raise an error?)
            lua_pushnil(state);
        }
    } else static if (is(T == class) || is(T == interface)) {
        LuaState.luaPushDObject(state, value);
    } else static if (is(T == Time)) {
        lua_pushnumber(state, value.secsd());
    } else static if (is(T == struct)) {
        //This is a hack to allow functions to return multiple values without
        //exposing internal lua functions. The function returns a struct with
        //a special "marker constant", and all contained values will be returned
        //separately. S.numReturnValues can be defined to dynamically change
        //the number of return values
        const membernames = structMemberNames!(T)();
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
                static if(membernames[idx] == "numReturnValues")
                    continue;
                if (numv <= 0)
                    break;
                argc += luaPush(state, x);
                numv--;
            }
            return argc;
        }
        lua_createtable(state, 0, value.tupleof.length);
        foreach (int idx, x; value.tupleof) {
            luaPush(state, membernames[idx]);
            luaPush(state, value.tupleof[idx]);
            lua_rawset(state, -3);
        }
        //set the metatable for the type, if it was set by addScriptType()
        lua_pushlightuserdata(state, cast(void*)typeid(T));
        lua_rawget(state, LUA_REGISTRYINDEX);
        lua_setmetatable(state, -2);
    } else static if (isArrayType!(T)) {
        lua_createtable(state, value.length, 0);
        foreach (k, v; value) {
            lua_pushinteger(state, k+1);
            luaPush(state, v);
            lua_rawset(state, -3);
        }
    } else static if (isAssocArrayType!(T)) {
        lua_newtable(state);
        foreach (k, v; value) {
            luaPush(state, k);
            luaPush(state, v);
            lua_rawset(state, -3);
        }
    } else static if (is(T == delegate)) {
        luaPushDelegate(state, value);
    } else static if (is(T X : X*) && is(X == function)) {
        luaPushFunction(state, value);
    } else static if (is(T == void*)) {
        //allow pushing 'nil', but no other void*
        assert(value is null);
        lua_pushnil(state);
    } else {
        static assert(false, "add me, you fool: " ~ T.stringof);
    }
    return 1;  //default to 1 argument
}

debug {
    import tango.core.Memory;

    void assert_gcptr(void* p) {
        //if this fails, the delegate probably points into the stack (unsafe)
        assert(GC.addrOf(p) !is null);
    }
}

//convert D delegate to a Lua c-closure, and push it on the Lua stack
//beware that the D delegate never should be from the stack, because Lua code
//  may call it even if the containing function returned (thus accessing random
//  data on the stack and causing corruption)
//to be safe, pass only normal object methods (of GC'ed objects)
private void luaPushDelegate(T)(lua_State* state, T del) {
    static assert(is(T == delegate));

    assert(del !is null);
    debug assert_gcptr(del.ptr);

    extern(C) static int demarshal(lua_State* state) {
        T del;
        del.ptr = LuaState.luaToDPtr(state, lua_upvalueindex(1));
        del.funcptr = cast(typeof(del.funcptr))
            lua_touserdata(state, lua_upvalueindex(2));
        return callFromLua(del, state, 0, "some D delegate");
    }

    //del.ptr may reference a GC'ed D object (actually assert_gcptr forces this
    //  right now), thus we must make sure it's pinned until Lua is done with it
    //del.funcptr just points to static code and doesn't need special treatment
    LuaState.luaPushDPtr(state, del.ptr);
    lua_pushlightuserdata(state, del.funcptr);
    lua_pushcclosure(state, &demarshal, 2);
}

//similar to luaPushDelegate
private void luaPushFunction(T)(lua_State* state, T fn) {
    //needing static if instead of just static assert is a syntax artefact
    static if (is(T X : X*) && is(X == function)) {
    } else { static assert(false); }

    assert(fn !is null);

    extern(C) static int demarshal(lua_State* state) {
        T fn = cast(T)lua_touserdata(state, lua_upvalueindex(1));
        return callFromLua(fn, state, 0, "some D function");
    }

    lua_pushlightuserdata(state, cast(void*)fn);
    lua_pushcclosure(state, &demarshal, 1);
}

//helper for cleaning up garbage collected LuaReferences
//this is just derived from WeakRef to save the overhead for 2 objects
private final class RealLuaRef : WeakRef {
private:
    int mLuaRef;
    LuaState mDState; //required to keep mState alive
    public ObjListNode!(typeof(this)) mNode;

    //add the value from the stack at stackIdx to the Lua ref table
    //the stack itself isn't changed
    //the Lua ref table entry will be removed as soon as referrer gets free'd
    //Lua error handling domain
    this(lua_State* state, int stackIdx, Object referrer) {
        assert(!!referrer);
        super(referrer);

        mDState = LuaState.getInstance(state);

        //put a "Lua ref" to the value into the reference table
        lua_pushvalue(state, stackIdx);
        mLuaRef = luaL_ref(state, LUA_REGISTRYINDEX);
        assert(mLuaRef != LUA_NOREF);

        //add to poll list for deferred freeing
        mDState.mRefList.add(this);

        debug gDLuaRefs++;
    }

    //neutral error handling domain
    void push(lua_State* state) {
        assert(mLuaRef != LUA_NOREF, "call .push() after .release()");
        //get ref'ed value from the reference table
        lua_rawgeti(state, LUA_REGISTRYINDEX, mLuaRef);
    }

    //return the Lua value as D value
    //get() is already taken by class WeakRef (and is completely different, arg)
    //D error domain
    T getT(T)() {
        if (!valid())
            throw new CustomException("invalid Lua reference");
        T res;
        auto state = mDState.mLua;
        luaProtected(state, {
            push(state);
            res = luaStackValue!(T)(state, -1);
            lua_pop(state, 1);
        });
        return res;
    }

    //clear the reference
    //neutral error domain
    void release() {
        if (!valid())
            return;
        luaL_unref(mDState.mLua, LUA_REGISTRYINDEX, mLuaRef);
        mLuaRef = LUA_NOREF;
        mDState.mRefList.remove(this);
    }

    //returns true if the reference hasn't been released yet
    //(it doesn't matter if the reference is a nil value; it behaves the same)
    //neutral error domain
    bool valid() {
        return mLuaRef != LUA_NOREF;
    }

    //called by LuaState
    //free the ref if the D object has been free'd
    bool pollRelease() {
        if (get() || !valid())
            return false;
        //no object set anymore; must have been collected or deleted
        release();
        return true;
    }
}

//holds a persistent reference to an arbitrary Lua value
//this is mainly used for the user API: you can bind a function with parameter
//  types of LuaReference to accept and return any Lua value
final class LuaReference {
    private {
        RealLuaRef mRef;
    }

    //create a reference to the value at stackIdx; the stack is not changed
    //users can create this object by using LuaReference as normal parameter in
    //  automatically bound D functions
    private this(lua_State* state, int stackIdx) {
        mRef = new RealLuaRef(state, stackIdx, this);
    }

    //push the referenced value on the stack
    private void push(lua_State* state) {
        mRef.push(state);
    }

    //return as D value
    T get(T)() {
        return mRef.getT!(T)();
    }

    //free reference (valid() -> false, push() will trigger assertion)
    void release() {
        mRef.release();
    }

    //returns true if the reference hasn't been released yet
    //(it doesn't matter if the reference is a nil value; it behaves the same)
    bool valid() {
        return mRef.valid();
    }
}

//wrapper for D->Lua delegates (implemented in Lua, called by D)
private class LuaDelegateWrapper(T) {
    private LuaState mDState;
    private RealLuaRef mRef;
    alias ParameterTupleOf!(T) Params;
    alias ReturnTypeOf!(T) RetType;

    //only to be called from luaStackDelegate()
    private this(lua_State* state, int stackIdx) {
        mRef = new RealLuaRef(state, stackIdx, this);
        mDState = mRef.mDState;
        assert(!!mDState);
    }

    //delegate to this is returned by luaStackDelegate/luaStackValue!(T)
    //of course in the D error domain
    RetType cbfunc(Params args) {
        const bool novoid = !is(RetType == void);
        static if (novoid)
            RetType res;
        try {
            lua_State* state = mDState.state;
            luaProtected(state, {
                mRef.push(state);
                assert(lua_isfunction(state, -1));
                static if (novoid)
                    res = luaCall!(RetType, Params)(state, args);
                else
                    luaCall!(void, Params)(state, args);
            });
        } catch (LuaException e) {
            //we could be anywhere in the code, and letting the LuaException
            //  through would most certainly cause a crash. So it is passed
            //  to the parent LuaState, which can report it back
            mDState.reportDelegateError(e);
            //if reportDelegate doesn't re-throw, return default
        }
        static if (novoid)
            return res;
    }
}

//convert a Lua function on that stack index to a D delegate
private T luaStackDelegate(T)(lua_State* state, int stackIdx) {
    static assert(is(T == delegate));
    //the lua function to call is at stackIdx and must be stored for later
    //  calling.
    if (lua_isnil(state, stackIdx))
        return null;
    if (!lua_isfunction(state, stackIdx))
        luaExpected(state, stackIdx, "closure");

    //xxx: could cache wrappers (Lua can do the Lua closure => unique int key
    //  mapping), but D has no such thing as weak hashtables
    auto pwrap = new LuaDelegateWrapper!(T)(state, stackIdx);
    return &pwrap.cbfunc;
}

//error handler:
//1. protect D code from Lua longjmp error handler
//2. make it possible to retrieve a Lua stack trace to the offending Lua code
extern (C) private int pcall_err_handler(lua_State* state) {
    //two cases for the error message value:
    //1. Lua code raised this error and may have passed any value
    //2. any Exception was passed through by other error handling code
    Exception stackEx = null;
    char[] msg;
    if (LuaState.luaIsDObject(state, 1)) {
        //note that a Lua script could have used a random D object
        //in that case stackEx would remain null
        Object o = LuaState.luaToDObject(state, 1);
        stackEx = cast(Exception)o;
    } else {
        //xxx I think this could trigger arbitrary script execution;
        //  what happens if the script raises an error?
        msg = lua_todstring_protected(state, 1);
    }
    //this also gets the Lua and D backtraces
    auto e = new LuaException(state, 1, msg, stackEx);
    //return e
    lua_pop(state, 1);
    LuaState.luaPushDObject(state, e);
    return 1;
}

//for luaProtected: simply calls the D delegate on the stack
extern (C) private int pcall_invoke_handler(lua_State* state) {
    void delegate() code;
    code.ptr = lua_touserdata(state, 1);
    code.funcptr = cast(void function())lua_touserdata(state, 2);
    //executed in Lua error domain
    code();
    return 0;
}

//this is in D error domain and calls code in Lua error domain (exactly once)
//basically similar to lua_cpcall, but for D (and doesn't alloc on Lua heap)
//it converts Lua errors raised in code to D exceptions thrown by this function
//the reverse, D error domain nested in Lua error domain, can be done by simply
//  wrapping the D domain code into a try-catch block:
//      try { ...code... } catch (CustomException e) { luaDError(state, e); }
//  (converts the D exception into a lua_error)
//it is guaranteed that the only thrown recoverable exception is LuaException
private void luaProtected(lua_State* state, void delegate() code) {
    //NOTE: heavily relies on the fact that all these functions don't raise any
    //  Lua errors (check the manual for the API); neutral error domain
    //get the cached C closure for the pcall_err_handler function
    lua_pushlightuserdata(state, &cErrorHandlerKey); //key
    lua_rawget(state, LUA_REGISTRYINDEX); //eh
    assert(lua_iscfunction(state, -1));
    //get the cached C closure for the pcall_invoke_handler function
    lua_pushlightuserdata(state, &cPInvokeHandlerKey); //eh key
    lua_rawget(state, LUA_REGISTRYINDEX); //eh ih
    assert(lua_iscfunction(state, -1));
    //push the parts of the delegate, these are the function arguments
    lua_pushlightuserdata(state, code.ptr); //eh ih ptr
    lua_pushlightuserdata(state, code.funcptr); //eh ih ptr fptr
    //stack: -4:errorfn -3:callfunction -2:arg1 -1:arg2
    int res = lua_pcall(state, 2, 0, -4);
    if (res != 0) {
        //stack: eh error
        if (res != LUA_ERRRUN) {
            //something REALLY bad happened *shrug*
            //  LUA_ERRMEM: out of memory... nothing will work anymore, go die
            //  LUA_ERRERR: even worse, everything is cursed
            throw new Exception(myformat("lua_pcall returned {}", res));
        }
        //the error handler (pcall_err_handler) always returns a LuaException
        assert(LuaState.luaIsDObject(state, -1));
        Object o_e = LuaState.luaUncheckedToDObject(state, -1);
        lua_pop(state, 2); //stack must be left clean
        LuaException e = cast(LuaException)o_e;
        assert(!!e);
        throw e;
    }
    //stack: eh
    //remove the error handler
    lua_pop(state, 1);
}

//call D -> Lua
//call the function on top of the stack
//Lua error handling domain
private RetType luaCall(RetType, T...)(lua_State* state, T args) {
    debug gDToLuaCalls++;

    //if lots of arguments, make sure to grow the stack
    //assumes luaPush returns 1 for each argument
    static if (T.length > LUA_MINSTACK/3)
        lua_checkstack(state, T.length);

    int argc;
    foreach (int idx, x; args) {
        argc += luaPush(state, args[idx]);
    }
    const bool ret_void = is(RetType == void);
    const int retc = ret_void ? 0 : 1;
    lua_call(state, argc, retc);
    static if (!ret_void) {
        RetType res = luaStackValue!(RetType)(state, -1);
        lua_pop(state, 1);
        return res;
    }
}

//call Lua -> D
//Execute the callable del, taking parameters from the lua stack
//  skipCount: skip this many parameters from beginning
//  funcName:  used in error messages
//stack size must match the requirements of del
//T must be something callable (delegate or function ptr)
//error handling: Lua domain
private int callFromLua(T)(T del, lua_State* state, int skipCount,
    char[] funcName)
{
    debug gLuaToDCalls++;

    int numArgs = lua_gettop(state);
    //number of arguments going to the D call
    int numRealArgs = numArgs - skipCount;

    //just to be safe: make sure there's a "reasonable" amount of stack
    if (numArgs > LUA_MINSTACK/3)
        lua_checkstack(state, LUA_MINSTACK/3);

    alias ParameterTupleOf!(typeof(del)) Params;

    if (numRealArgs != Params.length) {
        luaErrorf(state, "'{}' requires {} arguments, got {}, skip={}",
            funcName, Params.length+skipCount, numArgs, skipCount);
    }

    Params p;

    foreach (int idx, x; p) {
        alias typeof(x) PT;
        //xxx: so, how to generate good error messages?
        //try {
            p[idx] = luaStackValue!(PT)(state, skipCount + idx + 1);
        //} catch (LuaError e) {
        //    luaErrorf(state, "bad argument #{} to '{}' ({})", idx + 1,
        //        funcName, e.msg);
        //}
    }

    //the del is executed in D error handling domain
    static if (is(ReturnTypeOf!(del) == void)) {
        try {
            del(p);
            return 0;
        } catch (CustomException e) {
            luaDError(state, e);
        }
    } else {
        ReturnTypeOf!(del) ret = void;
        try {
            ret = del(p);
        } catch (CustomException e) {
            luaDError(state, e);
        }
        //marshal return value in Lua error domain
        return luaPush(state, ret);
    }

    assert(false, "unreachable");
}

extern (C) private int ud_gc_handler(lua_State* state) {
    LuaState.luaDestroyDObject(state, 1);
    return 0;
}

//special support for T() typechecking method provided to Lua
extern (C) private int typecheck_d_object(lua_State* state) {
    if (lua_gettop(state) != 1)
        luaErrorf(state, "T() expects exactly one argument");
    ClassInfo cls = cast(ClassInfo)lua_touserdata(state, lua_upvalueindex(1));
    Object obj = LuaState.luaToDObject(state, -1);
    if (!obj)
        luaErrorf(state, "nil passed to T()");
    if (!canCast(obj.classinfo, cls))
        luaErrorf(state, "T(): {} expected, but got {}", cls.name,
            obj.classinfo.name);
    //return argument on success
    return 1;
}

class LuaRegistry {
    private {
        Method[] mMethods;
        char[][ClassInfo] mPrefixes;
        bool mSealed;
    }

    enum MethodType {
        Method,
        StaticMethod,
        Property_R,
        Property_W,
        Ctor,
        FreeFunction,
    }

    struct Method {
        ClassInfo classinfo;
        char[] name;    //raw (actual) name
        char[] xname;   //not so raw (property writes are prefixed with set_)
        char[] prefix;  //basically the class name or ""
        lua_CFunction demarshal;
        MethodType type;
    }

    this() {
    }

    //e.g. setClassPrefix!(GameEngine)("Game"), to keep scripting names short
    //call before any method() calls
    void setClassPrefix(Class)(char[] name) {
        mPrefixes[Class.classinfo] = name;
    }

    private void registerDMethod(ClassInfo ci, char[] method,
        lua_CFunction demarshal, MethodType type)
    {
        assert(!mSealed);
        Method m;
        m.name = method;
        m.xname = method;
        if (type == MethodType.Property_W) {
            m.xname = "set_" ~ m.xname;
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
        } else {
            assert(type == MethodType.FreeFunction);
        }
        m.demarshal = demarshal;
        m.type = type;
        mMethods ~= m;
    }

    //Lua error domain
    private static void methodThisError(lua_State* state, char[] name,
        ClassInfo expected, Object got)
    {
        luaErrorf(state, "method call to '{}' requires non-null "
            "this pointer of type {} as first argument, but got: {}", name,
            expected.name, got ? got.classinfo.name : "*null");
    }

    //Register a class method
    void method(Class, char[] name)(char[] rename = null) {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;

            Object o = LuaState.luaToDObject(state, 1);
            Class c = cast(Class)(o);

            if (!c) {
                methodThisError(state, methodName,
                    Class.classinfo, o);
            }

            //NOTE: the following code is duplicated at least three times, with
            //  slight modifications. the problem is to unify functions, methods
            //  and static methods (and ctors if you'd want to be complete), and
            //  the slight differences seem to make unifying a major PITA. I
            //  didn't want to use string mixins to configure every aspect of
            //  the code, and taking the address of a symbol (function ptr,
            //  delegate) does not work because dmd bug 4028.

            //this crap is ONLY for default arguments
            //you can remove the code, you'll just lose the default args feature
            //--- default args start

            int realargs = lua_gettop(state) - 1;

            mixin ("alias Class."~name~" T;");
            alias ParameterTupleOf!(T) Params;
            const Params x;
            foreach (int idx, _; Repeat!(Params.length)) {
                const fn = "c."~name~"(x[0..idx])";
                static if (is(typeof( mixin(fn)))) {
                    if (idx >= realargs) {
                        //delegate indirection => runtime slowdown, additional
                        //  linker symbols
                        auto f = delegate(Params[0..idx] x) {
                            return mixin(fn);
                        };
                        return callFromLua(f, state, 1, methodName);
                    }
                }
            }

            //--- default args stop

            //no default arguments
            auto del = mixin("&c."~name);
            return callFromLua(del, state, 1, methodName);
        }

        registerDMethod(Class.classinfo, rename.length ? rename : name,
            &demarshal, MethodType.Method);
    }

    //register a static method for a class
    //not strictly necessary (redundant to func()), but here for more uniformity
    //  in the scripting and binding code (especially in combination with the
    //  singleton crap)
    void static_method(Class, char[] name)(char[] rename = null) {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;
            alias Class C;

            //this crap is ONLY for default arguments
            //you can remove the code, you'll just lose the default args feature
            //--- default args start

            int realargs = lua_gettop(state);

            mixin ("alias Class."~name~" T;");
            alias ParameterTupleOf!(T) Params;
            const Params x;
            foreach (int idx, _; Repeat!(Params.length)) {
                const fn = "c."~name~"(x[0..idx])";
                static if (is(typeof( mixin(fn)))) {
                    if (idx >= realargs) {
                        //delegate indirection => runtime slowdown, additional
                        //  linker symbols
                        auto f = delegate(Params[0..idx] x) {
                            return mixin(fn);
                        };
                        return callFromLua(f, state, 0, methodName);
                    }
                }
            }

            //--- default args stop

            //xxx when binding a normal virtual method with static_method, it
            //  compiles and a segfault happens as the script calls it
            auto fn = mixin("&C."~name);
            return callFromLua(fn, state, 0, methodName);
        }

        registerDMethod(Class.classinfo, rename.length ? rename : name,
            &demarshal, MethodType.StaticMethod);
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
            Type get(Class o) {
                if (!o) {
                    methodThisError(state, cDebugName, Class.classinfo, null);
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
                void set(Class o, Type t) {
                    if (!o) {
                        methodThisError(state, cDebugName,
                            Class.classinfo, null);
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
        //xxx this is crap, who knows what random strings .stringof will return
        //  in future compiler versions?
        const char[] funcName_raw = (&Fn).stringof;
        //DMD: "& funcname"
        //LDC: "&funcname"
        //if the string changes again (for any compiler vendor/version), this
        //  gives a nice silent regression
        //(duh, wasn't my idea; let's hope dmd bugzilla 4133 makes it through)
        static assert(funcName_raw[0] == '&');
        static if (funcName_raw[1] == ' ') {
            const funcName = funcName_raw[2..$];
        } else {
            const funcName = funcName_raw[1..$];
        }
        extern(C) static int demarshal(lua_State* state) {
            //this crap is ONLY for default arguments
            //you can remove the code, you'll just lose the default args feature
            //--- default args start

            int realargs = lua_gettop(state);

            alias ParameterTupleOf!(Fn) Params;
            const Params x;
            foreach (int idx, _; Repeat!(Params.length)) {
                const fn = "Fn(x[0..idx])";
                static if (is(typeof( mixin(fn)))) {
                    if (idx >= realargs) {
                        //delegate indirection => runtime slowdown, additional
                        //  linker symbols
                        auto f = delegate(Params[0..idx] x) {
                            return mixin(fn);
                        };
                        return callFromLua(f, state, 0, funcName);
                    }
                }
            }

            //--- default args stop

            return callFromLua(&Fn, state, 0, funcName);
        }
        registerDMethod(null, rename.length ? rename : funcName, &demarshal,
            MethodType.FreeFunction);
    }

    void seal() {
        mSealed = true;
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
        lua_State* mLua;
        LuaRegistry.Method[] mMethods;
        char[][ClassInfo] mClassNames;
        Object[ClassInfo] mSingletons;
        bool[ClassInfo] mClassUpdate; //xxx really needs to be global?
        ObjectList!(RealLuaRef, "mNode") mRefList; //D->Lua references
        int mRefListWatermark; //pseudo-GC
        bool mDestroyed;
        //Lua->D references
        PointerPinTable mPtrList;
    }

    //called when an error outside the "normal call path" occurs
    //  (i.e. a D->Lua delegate call fails)
    //when returning from this function normally, execution will somehow be
    //  resumed (in D->Lua delegate case, return to D; and if the function has
    //  a return type, return .init)
    //you can also throw any exception (including e)
    //if onError isn't set, "throw e;" is executed instead
    void delegate(LuaException e) onError;

    const cLanguageAndVersion = LUA_VERSION;

    static bool gLibLuaLoaded = false;

    this(int stdlibFlags = LuaLib.safe) {
        mRefList = new typeof(mRefList)();

        if (!gLibLuaLoaded) {
            char[] libname = env.Environment.get("LUALIB");
            if (!libname.length)
                libname = null; //derelict uses "libname is null"
            DerelictLua.load(libname);
            gLibLuaLoaded = true;
        }

        mLua = luaL_newstate();
        mPtrList = new PointerPinTable();
        //needed in theory, pointless in practise (at least currently)
        mPtrList.pinPointer(cast(void*)this);

        lua_atpanic(mLua, &my_lua_panic);

        //set "this" reference
        lua_pushlightuserdata(mLua, &cLuaStateKey);
        lua_pushlightuserdata(mLua, cast(void*)this);
        lua_rawset(mLua, LUA_REGISTRYINDEX);

        //c-closures for pcall error handler stuff
        lua_pushlightuserdata(mLua, &cPInvokeHandlerKey);
        lua_pushcfunction(mLua, &pcall_invoke_handler);
        lua_rawset(mLua, LUA_REGISTRYINDEX);
        lua_pushlightuserdata(mLua, &cErrorHandlerKey);
        lua_pushcfunction(mLua, &pcall_err_handler);
        lua_rawset(mLua, LUA_REGISTRYINDEX);

        //object reference table; map D references to userdata
        //the userdata is used to know the lifetime of references, so we
        //  need to make the table weak
        lua_newtable(mLua);
        //metatable to make values weak
        lua_newtable(mLua);
        lua_pushliteral(mLua, "v"); //weak values
        lua_setfield(mLua, -2, "__mode");
        lua_setmetatable(mLua, -2);
        //store the table in its place
        lua_pushlightuserdata(mLua, &cRefCacheKey);
        lua_insert(mLua, -2); //swap
        lua_rawset(mLua, LUA_REGISTRYINDEX);

        //the __gc method used in D wrapper metatables
        lua_pushliteral(mLua, cGCHandler);
        lua_pushcfunction(mLua, &ud_gc_handler);
        lua_rawset(mLua, LUA_REGISTRYINDEX);

        //the only purpose of this table is to enable fast identification of
        //  userdata that wraps objects (for marshaller type safety)
        lua_pushlightuserdata(mLua, &cDObjectUDKey);
        lua_newtable(mLua);
        lua_rawset(mLua, LUA_REGISTRYINDEX);

        //table for environments
        lua_newtable(mLua);
        lua_setfield(mLua, LUA_REGISTRYINDEX, cEnvTable.ptr);

        //metatables
        lua_newtable(mLua);
        lua_setfield(mLua, LUA_REGISTRYINDEX, cMetatableCache.ptr);

        assert(lua_gettop(mLua) == 0);

        //rest is stdlib kind of stuff

        loadStdLibs(stdlibFlags);

        //this is security relevant; allow only in debug code
        version (DEBUG_UNSAFE) {
            loadStdLibs(LuaLib.debuglib);
            loadStdLibs(LuaLib.packagelib);
        }

        //own std stuff
        auto reg = new LuaRegistry();
        reg.method!(Object, "toString")();
        reg.property_ro!(Object, "classinfo")();
        reg.func!(className);
        reg.func!(fullClassName);
        register(reg);

        extern (C) static int d_isobject(lua_State* state) {
            lua_pushboolean(state, luaIsDObject(state, 1));
            return 1;
        }
        lua_pushcfunction(mLua, &d_isobject);
        lua_setglobal(mLua, "d_isobject".ptr);

        void kill(char[] global) {
            lua_pushnil(mLua);
            lua_setglobal(mLua, czstr.toStringz(global));
        }

        //dofile and loadfile are unsafe, and even worse, freeze your program
        //  if called with no argument (because they want to read from stdin)
        kill("dofile");
        kill("loadfile");

        setGlobal("d_get_obj_metadata", &script_get_obj_metadata);
        setGlobal("d_get_class_metadata", &script_get_class_metadata);
        setGlobal("d_get_class", &script_get_class);
        setGlobal("d_find_class", &script_find_class);
        setGlobal("d_is_class", &script_is_class);
    }

    override void dispose() {
        super.dispose();
        lua_close(mLua);
        mLua = null;
        delete mPtrList;
        foreach (r; mRefList) {
            delete r;
        }
        delete mRefList;
        foreach (ClassInfo k, ref Object v; mSingletons) {
            v = null;
        }
    }

    ~this() {
        //if the program temrinates, it will call modules dtors, and after this
        //  it will call finalizers on all GC objects that are still alive. but
        //  the module dtors will make derelict to unload liblua, so finalizers
        //  for left over LuaStates can't call lua_close() LOL
        if (!DerelictLua.loaded())
            return;
        //this is VERY questionable - it does a lot of stuff in this function,
        //  and I don't know if it's really safe (the problem is that ~this can
        //  get called from foreign threads etc.)
        //at the very least, we shouldn't access stuff in __gc methods (which
        //  this function calls), and we set mLua to null to know about this
        if (mLua) {
            mDestroyed = true;
            //close the state (will call all left userdata __gc)
            lua_close(mLua);
            mLua = null;
        }
    }

    //return instance of LuaState from the registry
    //never returns null
    //neutral error domain
    private static LuaState getInstance(lua_State* state) {
        lua_pushlightuserdata(state, &cLuaStateKey);
        lua_rawget(state, LUA_REGISTRYINDEX);
        auto res = cast(LuaState)lua_touserdata(state, -1);
        assert(!!res);
        assert(res.classinfo is LuaState.classinfo);
        lua_pop(state, 1);
        return res;
    }

    //lua error domain
    private static Object luaToDObject(lua_State* state, int stackIdx) {
        if (!luaIsDObject(state, stackIdx))
            luaExpected(state, stackIdx, "object reference");
        return luaUncheckedToDObject(state, stackIdx);
    }

    //note: this goes horribly wrong for non-object userdata (it's unchecked)
    private static Object luaUncheckedToDObject(lua_State* state, int stackIdx)
    {
        assert(luaIsDObject(state, stackIdx));
        auto ud = cast(UD_Object*)lua_touserdata(state, stackIdx);
        if (ud) {
            assert(!!ud.o);
            return ud.o;
        } else {
            return null;
        }
    }

    //neutral error domain
    private static bool luaIsDObject(lua_State* state, int stackIdx) {
        //allow full userdata and nil, nothing else
        auto t = lua_type(state, stackIdx);
        //null refs are always marshalled as nil
        if (t == LUA_TNIL)
            return true;
        if (t != LUA_TUSERDATA)
            return false;
        //need to verify that the userdata was generated by this wrapper
        //the idea is that we don't conflict with userdata from C libraries (if
        //  we ever need this... otherwise, we could omit this check)
        lua_getfenv(state, stackIdx); //udenv
        lua_pushlightuserdata(state, &cDObjectUDKey); //udenv udkey
        lua_rawget(state, LUA_REGISTRYINDEX); //udenv udidtable
        int res = lua_rawequal(state, -2, -1); //udenv udidtable
        lua_pop(state, 2);
        return !!res;
    }

    private static void luaPushDObject(lua_State* state, Object value) {
        if (luaPushCachedDObject(state, cast(void*)value))
            return;

        //userdata not in cache; need to create it
        luaCreateDObject(state, value);
    }

    //fast path of luaPushDObject, returns success (if a wrapper is in cache)
    //on success, push a value on the stack; otherwise leave stack as is
    //value is void* instead of Object for stupid reasons, see luaToDPtr()
    private static bool luaPushCachedDObject(lua_State* state, void* value) {
        if (!value) {
            lua_pushnil(state);
            return true;
        }

        //retrieve the (hopefully) cached userdata from the registry
        //get ref cache table
        lua_pushlightuserdata(state, &cRefCacheKey); //refkey
        lua_rawget(state, LUA_REGISTRYINDEX); //reftable
        //the reference itself is used as index (awkward, but works)
        lua_pushlightuserdata(state, value); //reftable value
        lua_rawget(state, -2); //reftable ud
        auto type = lua_type(state, -1);
        if (type == LUA_TUSERDATA) {
            lua_replace(state, -2); //ud
            return true;
        } else {
            lua_pop(state, 2);
            return false;
        }
    }

    //create and push a userdata for value on the Lua stack
    private static void luaCreateDObject(lua_State* state, Object value) {
        debug int top = lua_gettop(state);

        LuaState lstate = getInstance(state);

        int pinID = lstate.mPtrList.pinPointer(cast(void*)value);
        auto ud = cast(UD_Object*)lua_newuserdata(state, UD_Object.sizeof); //ud
        ud.o = value;
        ud.pinID = pinID;

        //set metatable (list of methods for the D object and __gc)
        lstate.luaPushMetatable(state, value.classinfo); //ud metatable
        lua_setmetatable(state, -2); //ud

        //set the ID table as userdata environment table - need this to quickly
        //  distinguish userdata for D wrapper objects and "other" userdata
        //  (e.g. userdata by arbitrary Lua/C libraries)
        //normally, the userdata's metatable is used for this purpose, but due
        //  to the object oriented D API, there are multiple metatables
        //according to the Lua manual, userdata environment tables don't mean
        //  anything and are free for use by C
        lua_pushlightuserdata(state, &cDObjectUDKey); //ud udkey
        lua_rawget(state, LUA_REGISTRYINDEX); //ud udidtable
        lua_setfenv(state, -2); //ud

        //put it into the cache table
        lua_pushlightuserdata(state, &cRefCacheKey); //ud refkey
        lua_rawget(state, LUA_REGISTRYINDEX); //ud reftable
        lua_pushlightuserdata(state, cast(void*)value); //ud reftable value
        lua_pushvalue(state, -3); //ud reftable value ud
        lua_rawset(state, -3); //ud reftable
        lua_pop(state, 1); //ud

        //the userdata on the stack is returned
        assert(lua_type(state, -1) == LUA_TUSERDATA);
        debug assert(lua_gettop(state) == top + 1);

        debug gLuaDRefs++;
    }

    //called from the __gc method; the userdata is at stackIdx
    private static void luaDestroyDObject(lua_State* state, int stackIdx) {
        LuaState lstate = LuaState.getInstance(state);

        //special case for ~this
        if (lstate.mDestroyed)
            return;

        assert(luaIsDObject(state, 1));

        auto ud = cast(UD_Object*)lua_touserdata(state, stackIdx);
        assert(!!ud);
        lstate.mPtrList.unpinPointer(ud.pinID, cast(void*)ud.o);
    }

    //must not be used anywhere but here
    private static final class PtrWrapper {
        void* ptr; //will take care that ptr is not garbage collected
    }

    //mainly used for D delegates wrapped as Lua values, although it could
    //  potentially be used to "tunnel" any D pointer through Lua
    private static void* luaToDPtr(lua_State* state, int stackIdx) {
        Object o = luaToDObject(state, stackIdx);
        //isn't it BEAUTIFUL (yeah, kill me now)
        if (auto wrapper = cast(PtrWrapper)o) {
            return wrapper.ptr;
        } else {
            return cast(void*)o; //reason see luaPushDPtr
        }
    }

    //xxx: luaPushPtr calls with the same ptr value may create multiple wrappers
    private static void luaPushDPtr(lua_State* state, void* ptr) {
        //check if ptr is an object; in this case we just use the object's Lua
        //  reference wrapper - this is some sort of bonus to spare wrapper
        //  generation if ptr is both an object and was already wrapped
        if (luaPushCachedDObject(state, ptr))
            return;

        //no wrapper object existed; create one
        //for "simplicity" (uh oh) we create a D wrapper object; note that a
        //  future call to luaPushDPtr with the same arguments will just create
        //  a new wrapper, instead of using an existing one
        auto wrapper = new PtrWrapper;
        wrapper.ptr = ptr;
        luaCreateDObject(state, wrapper);
    }

    //like luaPushMetatable, but don't create MT if it doesn't exist
    //returns true: metatable has been pushed on Lua stack
    //returns false: no metatable returned, Lua stack is untouched
    private bool luaPushCachedMetatable(lua_State* state, ClassInfo cls) {
        lua_getfield(state, LUA_REGISTRYINDEX, cMetatableCache.ptr); //mc
        //the ClassInfo is used as key; assumes all ClassInfos are static data
        lua_pushlightuserdata(state, cast(void*)cls); //mc cls
        lua_rawget(state, -2); //mc mt
        lua_replace(state, -2); //mt
        if (lua_isnil(state, -1)) {
            lua_pop(state, 1);
            return false;
        }
        return true; //return mt
    }

    //the metatable is generated by the wrapper and contains the method entries;
    //  it also contains the __gc method, which is needed for garbage collecting
    //  the wrapper and the D object
    //because of the __gc method, it must only be used on userdata wrapping D
    //  objects, see luaCreateDObject()
    //returns metatable for cls on Lua stack
    private void luaPushMetatable(lua_State* state, ClassInfo cls) {
        if (luaPushCachedMetatable(state, cls))
            return;

        //expects on stack: methodtable sometable
        //stack is the same when the function leaves
        //sets up sometable as metatable, e.g. sets __index to methodtable
        void setupmt() {
            //stack: mth table
            //set table.__index to method-table
            lua_pushliteral(state, "__index"); //mth table __index
            lua_pushvalue(state, -3); //mth table __index mth
            lua_rawset(state, -3); //mth table
        }

        //create a new metatable, it didn't exist yet
        lua_newtable(state); //mt
        //add __gc method
        lua_pushliteral(state, "__gc"); //mt "__gc"
        lua_pushliteral(state, cGCHandler); //mt "__gc" handlerkey
        lua_rawget(state, LUA_REGISTRYINDEX); //mt "__gc" gchandler
        lua_rawset(state, -3); //mt
        //method-table, that contains a list of all methods
        lua_newtable(state); //mt mth
        //add the T method to the method-table
        lua_pushliteral(state, "T"); //mt mth "T"
        lua_pushlightuserdata(state, cast(void*)cls); //mt mth "T" cls
        lua_pushcclosure(state, &typecheck_d_object, 1); //mt mth "T" T()
        lua_rawset(state, -3); //mt mth
        //
        lua_pushvalue(state, -2); //mt mth mt
        setupmt(); //mt mth mt
        lua_pop(state, 1); //mt mth
        //fake metatable for below; indexing set up the same as real metatable
        lua_newtable(state); //mt mth fakemt
        setupmt(); //mt mth fakemt
        lua_remove(state, -2); //mt fakemt
        //hide metatable from script with the special __metatable field
        //this is critical for memory safety
        //if a script does getmetatable(userdata), return a fake metatable
        lua_pushliteral(state, "__metatable"); //mt fakemt __metatable
        lua_pushvalue(state, -2); //mt fakemt __metatable fakemt
        lua_rawset(state, -4); //mt fakemt
        lua_pop(state, 1); //mt
        //store in global cache table
        lua_getfield(state, LUA_REGISTRYINDEX, cMetatableCache.ptr); //mt mc
        lua_pushlightuserdata(state, cast(void*)cls); //mt mc cls
        lua_pushvalue(state, -3); //mt mc cls mt
        lua_rawset(state, -3); //mt mc
        lua_pop(state, 1); //mt
        //fill the metatable with methods
        luaUpdateMetatable(cls);
        //return mt
    }

    //this is needed to free D->Lua references
    //call it periodically (a good place is per-frame functions)
    //why not use destructors? I had to give a page-long explanation, but this
    //  has to do: it would never work correctly
    void periodicCleanup() {
        //this watermark stuff is just an attempt to reduce unnecessary work
        if (mRefList.count <= mRefListWatermark)
            return;
        foreach (RealLuaRef r; mRefList) {
            //r might remove itself from mRefList
            r.pollRelease();
        }
        mRefListWatermark = mRefList.count;
    }

    //hack for better error handling: delegate wrappers call this on errors
    //in D error domain
    void reportDelegateError(LuaException e) {
        if (onError) {
            onError(e);
        } else {
            //byebye
            throw e;
        }
    }

    private final lua_State* state() {
        return mLua;
    }

    //return memory used by Lua in bytes
    final size_t vmsize() {
        //xxx: marked with 'e' in the manual, but how would it raise errors?
        return lua_gc(mLua, LUA_GCCOUNT, 0)*1024
            + lua_gc(mLua, LUA_GCCOUNTB, 0);
    }

    //return the size of the reference table (may give hints about unfree'd
    //  D delegates referencing Lua functions, and stuff)
    //return value is not exact (lazy sweeping and the way luaL_unref works)
    final int reftableSize() {
        //so yeah, need to walk the whole table
        //all calls should be in neutral error domain (lua_next not strictly)
        int count = 0;
        lua_pushvalue(mLua, LUA_REGISTRYINDEX);
        lua_pushnil(mLua);
        while (lua_next(mLua, -2) != 0) {
            if (lua_type(mLua, -2) == LUA_TNUMBER)
                count++;
            lua_pop(mLua, 1);
        }
        lua_pop(mLua, 1);
        return count;
    }

    //number of unique D references in the Lua heap
    final int objtableSize() {
        int count = 0;
        //get reftable
        lua_pushlightuserdata(state, &cRefCacheKey);
        lua_rawget(state, LUA_REGISTRYINDEX);
        //and iterate it
        lua_pushnil(mLua);
        while (lua_next(mLua, -2) != 0) {
            count++;
            lua_pop(mLua, 1);
        }
        lua_pop(mLua, 1);
        return count;
    }

    void loadStdLibs(int stdlibFlags) {
        foreach (lib; luaLibs) {
            if (stdlibFlags & lib.flag) {
                luaProtected(mLua, {
                    lua_pushcfunction(mLua, *lib.func);
                    luaCall!(void, char[])(mLua, lib.name);
                });
            }
        }
    }

    void register(LuaRegistry stuff) {
        stuff.seal();

        CustomException error;

        foreach (ClassInfo key, char[] value; stuff.mPrefixes) {
            mClassNames[key] = value;
        }

        luaProtected(mLua, {
            foreach (m; stuff.mMethods) {

                if (m.type == LuaRegistry.MethodType.FreeFunction) {

                    lua_pushliteral(mLua, m.xname);
                    lua_gettable(mLua, LUA_GLOBALSINDEX);
                    bool nil = lua_isnil(mLua, -1);
                    lua_pop(mLua, 1);

                    if (nil) {
                        lua_pushliteral(mLua, m.xname);
                        lua_pushcclosure(mLua, m.demarshal, 0);
                        lua_settable(mLua, LUA_GLOBALSINDEX);
                    } else {
                        //most likely cause: multiple bind calls for a method
                        error = new CustomException("attempting to overwrite "
                            "existing name in _G when adding D method: "
                            ~m.xname);
                        return;
                    }
                }

                if (m.classinfo) {
                    mClassUpdate[m.classinfo] = true;
                }

                mMethods ~= m;
            }

            //mark all classes derived from updated classes as updated
            bool change = true;
            while (change) {
                change = false;
                outer: foreach (ClassInfo cls, ref bool update; mClassUpdate) {
                    if (update)
                        continue;
                    auto cur = cls;
                    while (cur) {
                        if (auto pcls = cur in mClassUpdate) {
                            if ((*pcls) && canCast(cls, cur)) {
                                update = true;
                                change = true;
                                continue outer;
                            }
                        }
                        cur = cur.base;
                    }
                }
            }

            //go over all classes and update the metatables related to them
            foreach (ClassInfo cls, ref bool update; mClassUpdate) {
                if (!update)
                    continue;
                update = false;
                luaUpdateMetatable(cls);

                //create a global variable, but only if it doesn't exist (e.g.
                //  consider what addSingleton() wants)
                char[] clsname = mClassNames[cls];
                lua_pushliteral(mLua, clsname); //name
                lua_rawget(mLua, LUA_GLOBALSINDEX); //_G[name]
                bool doset = lua_isnil(mLua, -1);
                lua_pop(mLua, 1); //-
                if (doset) {
                    lua_pushliteral(mLua, clsname); //name
                    luaPushMethodTable(mLua, cls); //name mth
                    lua_rawset(mLua, LUA_GLOBALSINDEX); //-
                }
            }
        });

        //must not throw it in Lua error domain code, so do it here
        if (error)
            throw error;
    }

    //pushes the method table for cls on the stack
    private void luaPushMethodTable(lua_State* state, ClassInfo cls) {
        luaPushMetatable(state, cls); //mt
        luaDoGetMethodTable(state); //mth
    }

    //exchanges metatable on stack top with method table
    private void luaDoGetMethodTable(lua_State* state) {
        lua_pushliteral(mLua, "__index"); //mt __index
        lua_rawget(mLua, -2); //mt mth
        lua_replace(mLua, -2); //mth
    }

    //update the Lua metatable for cls with new methods from cls and bases
    //methods that already exist (by name) are left untouched
    //(lua stack empty)
    private void luaUpdateMetatable(ClassInfo cls) {
        assert(!!cls);

        //pushes metatable on stack (only on success)
        //if the metatable doesn't exist, nothing has to be done
        if (!luaPushCachedMetatable(mLua, cls))
            return;

        luaDoGetMethodTable(mLua);

        //xxx sorting the methods by class might be advantageous
        foreach (LuaRegistry.Method m; mMethods) {
            if (!m.classinfo)
                continue;
            //only if cls is derived from m.classinfo
            if (!canCast(cls, m.classinfo))
                continue;
            //don't want the ctors for super classes in a class' metatable
            if (m.type == LuaRegistry.MethodType.Ctor && cls !is m.classinfo)
                continue;

            lua_pushliteral(mLua, m.xname); //mth name
            lua_pushvalue(mLua, -1); //mth name name
            lua_rawget(mLua, -3); //mth name value
            if (lua_isnil(mLua, -1)) {
                //nothing set yet
                lua_pop(mLua, 1); //mth name
                lua_pushcclosure(mLua, m.demarshal, 0); //mth name func
                lua_rawset(mLua, -3); //mth
            } else {
                lua_pop(mLua, 2); //mth
            }
        }

        lua_pop(mLua, 1); //the method-table
    }

    struct MetaData {
        char[] type;    //stringified LuaRegistry.MethodType
        char[] dclass;  //name/prefix of the D class for the method
        char[] name;    //name of the method
        char[] xname;   //method name with decoration, e.g. "get_" ~ name
    }
    //return MetaData for all known bound D functions for the passed class
    //if from is null, an empty array is returned
    private MetaData[] script_get_class_metadata(ClassInfo from) {
        if (!from)
            return null;
        MetaData[] res;
        foreach (LuaRegistry.Method m; mMethods) {
            if (canCast(from, m.classinfo))
                res ~= convert_md(m);
        }
        return res;
    }
    private MetaData convert_md(LuaRegistry.Method m) {
        alias LuaRegistry.MethodType MT;
        MetaData d;
        switch (m.type) {
            case MT.Method: d.type = "Method"; break;
            case MT.StaticMethod: d.type = "StaticMethod"; break;
            case MT.Property_R: d.type = "Property_R"; break;
            case MT.Property_W: d.type = "Property_W"; break;
            case MT.Ctor: d.type = "Ctor"; break;
            case MT.FreeFunction: d.type = "FreeFunction"; break;
        }
        d.dclass = m.prefix;
        d.name = m.name;
        d.xname = m.xname;
        return d;
    }

    private MetaData[] script_get_obj_metadata(Object from) {
        return script_get_class_metadata(script_get_class(from));
    }

    private ClassInfo script_get_class(Object from) {
        return from ? from.classinfo : null;
    }

    private ClassInfo script_find_class(char[] name) {
        //yes, the class prefix is not unique; one prefix can refer to several
        //  D classes, and this is by design (apparently this was d0c's idea;
        //  maybe he could be convinced otherwise)
        //actually, we'd have to return the least specific class in cases when
        //  a prefix is ambiguous, but instead just catch the ambiguous case
        //  and raise an error *shrug*
        ClassInfo win = null;
        foreach (LuaRegistry.Method m; mMethods) {
            if (m.prefix == name) {
                win = m.classinfo;
                break;
            }
        }
        if (!win)
            return null;
        //check for ambiguous prefixes
        foreach (LuaRegistry.Method m; mMethods) {
            if (m.classinfo is win) {
                if (m.prefix != name)
                    throw new CustomException("class prefix is not unique,"
                        " thus can't find unique classinfo: "~name);
            }
        }
        return win;
    }

    //if obj is a ClassInfo, return if it references a class derived from cls
    //otherwise, return if obj itself is derived from cls
    private bool script_is_class(Object obj, ClassInfo cls) {
        if (!obj || !cls)
            return false;
        ClassInfo cls1 = cast(ClassInfo)obj;
        if (!cls1)
            cls1 = obj.classinfo;
        return canCast(cls1, cls);
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

        //add a global variable for the singleton (script can use it)
        if (auto pname = ci in mClassNames) {
            char[] name = *pname;
            scriptExec(`local name, inst = ...; _G[name] = inst`,
                name, instance);
        }
    }

    //prefixed all very-Lua-specific functions with lua
    //all of them are in the lua error domain (= shoot yourself into the foot)

    //lua error domain
    private void luaLoadChecked(char[] chunkname, char[] data) {
        //'=' means use the name as-is (else "string " is added)
        int res = luaL_loadbuffer(mLua, data.ptr, data.length,
            czstr.toStringz('='~chunkname));
        if (res != 0) {
            //xxx if this fails to get the message (e.g. utf8 error), there
            //    will be no line number
            char[] err = lua_todstring_protected(mLua, -1);
            lua_pop(mLua, 1);  //remove error message
            luaErrorf(mLua, "Parse error: {}", err);
        }
    }

    //another variation
    //load script in "code", using "name" for error messages
    //there's also scriptExec() if you need to pass parameters
    //environmentId = set to create/reuse a named execution environment
    void loadScript(char[] name, char[] code, char[] environmentId = null) {
        luaProtected(mLua, {
            luaLoadChecked(name, code);
            if (environmentId.length) {
                luaGetEnvironment(environmentId);
                lua_setfenv(mLua, -2);
            }
            luaCall!(void)(mLua);
        });
    }

    //get an execution environment from the registry and push it to the stack
    //the environment is created if it doesn't exist
    //a metatable is set to forward lookups to the globals table
    //(see http://lua-users.org/lists/lua-l/2006-05/msg00121.html )
    //lua error domain
    private void luaGetEnvironment(char[] environmentId) {
        assert(environmentId.length);
        //table that maps all environments by names to table values
        lua_getfield(mLua, LUA_REGISTRYINDEX, cEnvTable.ptr);
        int envpos = lua_gettop(mLua);
        //check if the environment was defined before
        luaPush(mLua, environmentId);
        lua_rawget(mLua, -2);
        //if it was, return it on the stack; if it wasn't, create it
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

            //set environment name as variable "ENV_NAME"
            luaPush(mLua, environmentId);
            lua_setfield(mLua, -2, "ENV_NAME");

            //set environment itself as _ENV (similar to _G)
            lua_pushvalue(mLua, -1);
            lua_setfield(mLua, -2, "_ENV");

            //store for later use (Registry[cEnvTable][envId]=table)
            luaPush(mLua, environmentId);
            lua_pushvalue(mLua, -2);
            lua_settable(mLua, envpos);
        }
        lua_remove(mLua, envpos);
    }

    //Call a function defined in lua
    void call(T...)(char[] funcName, T args) {
        luaProtected(mLua, {
            luaPush(mLua, funcName);
            lua_gettable(mLua, LUA_GLOBALSINDEX);
            luaCall!(void, T)(mLua, args);
        });
    }

    //like call(), but with return value
    //(code duplicated because the static if orgy for RetType==void was fugly)
    //this tripple nesting (thx to h3) allows us to use type inference:
    //  state.callR!(int)("func", 123, "abc", 5.4);
    template callR(RetType) {
        RetType callR(T...)(char[] funcName, T args) {
            RetType res;
            luaProtected(mLua, {
                luaPush(mLua, funcName);
                lua_gettable(mLua, LUA_GLOBALSINDEX);
                res = luaCall!(RetType, T)(mLua, args);
            });
            return res;
        }
    }

    //execute a script snippet (should only be used for slow stuff like command
    //  line interpreters, or initialization code)
    void scriptExec(Args...)(char[] code, Args a) {
        luaProtected(mLua, {
            luaLoadChecked("scriptExec", code);
            luaCall!(void, Args)(mLua, a);
        });
    }

    template scriptExecR(RetType) {
        RetType scriptExecR(Args...)(char[] code, Args a) {
            RetType res;
            luaProtected(mLua, {
                luaLoadChecked("scriptExec", code);
                res = luaCall!(RetType, Args)(mLua, a);
            });
            return res;
        }
    }

    //store a value as global Lua variable
    void setGlobal(T)(char[] name, T value, char[] environmentId = null) {
        luaProtected(mLua, {
            int stackIdx = LUA_GLOBALSINDEX;
            if (environmentId.length) {
                luaGetEnvironment(environmentId);
                stackIdx = -3;
            }
            luaPush(mLua, name);
            luaPush(mLua, value);
            lua_settable(mLua, stackIdx);
            if (environmentId.length) {
                lua_pop(mLua, 1);
            }
        });
    }
    T getGlobal(T)(char[] name, char[] environmentId = null) {
        T res;
        luaProtected(mLua, {
            int stackIdx = LUA_GLOBALSINDEX;
            if (environmentId.length) {
                luaGetEnvironment(environmentId);
                stackIdx = -2;
            }
            luaPush(mLua, name);
            lua_gettable(mLua, stackIdx);
            res = luaStackValue!(T)(mLua, -1);
            lua_pop(mLua, environmentId.length ? 2 : 1);
        });
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
                for i = 1, select("#", ...) do
                    if i > 1 then
                        d_out("\t") -- like Lua's print()
                    end
                    local s = select(i, ...)
                    d_out(tostring(s))
                end
                d_out("\n")
            end
        `, cb);
    }

    //assign a lua-defined metatable tableName to a D struct type
    void addScriptType(T)(char[] tableName) {
        luaProtected(mLua, {
            //get the metatable from the global scope and write it into the
            //  registry; see luaPush()
            lua_pushlightuserdata(mLua, cast(void*)typeid(T));
            lua_getfield(mLua, LUA_GLOBALSINDEX, czstr.toStringz(tableName));
            lua_rawset(mLua, LUA_REGISTRYINDEX);
        });
    }
}

//this class is used to pin an arbitrary number of D pointers
//pinning means two things:
//- don't collect the object (if the only ptrs are on the Lua/C heap)
//- don't move it around (right now the D GC actually never does that)
private class PointerPinTable {
    //amgibuous pointer; don't know if it's a ptr or not
    //only needed in theory (no D implementation requires it)
    union AmbPtr {
        void* ptr;
        size_t _int; //will mark ptr as ambiguous (also, used for freelist)
    }
    AmbPtr[] mPinList;
    int mFreeList = -1; //point to next free entry

    //makes sure the pointer won't be free'd or relocated by the GC
    //it doesn't protect the pointer against manual free'ing
    //non-GC pointers work too
    //returns a pinID, which is used with unpinPointer (the proper way to do
    //  this is to create a hashtable, and use ptr as the key for unpinPointer,
    //  but me is too lazy and the pinID thing simply makes it easier)
    //must not pin the same pointer twice (unless it was unpinned before); this
    //  is not checked yet, but I may convert this to a hashtable
    int pinPointer(void* ptr) {
        if (mFreeList == -1) {
            extend();
        }
        auto alloc = mFreeList;
        mFreeList = mPinList[alloc]._int;
        mPinList[alloc].ptr = ptr;
        return alloc;
    }

    //undo pinPointer - pinID is the return value of pinPointer
    //xxx ptr is just passed for debugging
    void unpinPointer(int pinID, void* ptr) {
        assert(mPinList[pinID].ptr is ptr);
        mPinList[pinID] = AmbPtr.init;
        mPinList[pinID]._int = mFreeList;
        mFreeList = pinID;
    }

    //grow internal array; at least provide 1 new freelist entry
    void extend() {
        auto oldarray = mPinList;
        //doesn't make much sense but should work
        mPinList.length = mPinList.length + 10 + mPinList.length / 2;
        assert(mPinList.length > oldarray.length);
        //add new entries to freelist
        for (size_t idx = oldarray.length; idx < mPinList.length; idx++) {
            mPinList[idx]._int = mFreeList;
            mFreeList = idx;
        }
        //free old array, it would only prevent the GC from doing its job
        if (oldarray.ptr != mPinList.ptr)
            delete oldarray;
        assert(mFreeList != -1);
    }

    //in theory, would have to un-pin all references here
    ~this() {
    }
}
