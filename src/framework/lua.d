module framework.lua;

import derelict.lua.lua;
import czstr = tango.stdc.stringz;
import cstdlib = tango.stdc.stdlib;
import tango.core.Traits : ParameterTupleOf, isIntegerType, isFloatingPointType,
    ElementTypeOfArray, isArrayType, isAssocArrayType, KeyTypeOfAA, ValTypeOfAA,
    ReturnTypeOf, isStaticArrayType;
import rtraits = tango.core.RuntimeTraits;
import env = tango.sys.Environment;
import tango.core.Exception;

import str = utils.string;
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
  lead to a corrupted program state, and should never be catchable by Lua
- this isn't strictly done right now; instead, there's a messy mix
  the problem is that out of memory errors could lead to both Lua errors and D
  exceptions being raised from the same place (like luaPush())
to fix this...:
- almost all Lua API functions should be called inside a lua_cpcall() (that's
  why there's a luaProtected() function in this module, although it doesn't do
  the right thing)
- make our own error raising more consistent, e.g. don't throw recoverable D
  exceptions inside luaPush() but use lua_error()
- make sure "unrecoverable" exceptions (like assertions, out of memory) never
  jump through the Lua C stack (or at least, make sure nobody is going to access
  the "corrupted" Lua state)
- doLuaCall() actually should be called inside a lua_cpcall (including argument
  marshalling/demarshalling), and shouldn't need to call the actual Lua
  function with a lua_pcall (on the other hand, I don't know how one can set
  the custom error handler function [for Lua backtraces] without lua_pcall)
- Lua 5.2 work2 deprecates lua_cpcall WELL, WTF
all this is not really important, because normal error handling works. the
problem is just with e.g. out of memory errors, but in this case, everything is
beyond repair anyway; this is just documenting that the current error handling
is a bit broken in this aspect and the code doesn't make perfect sense.
+/

//comment this to disable unsafe debug extensions
//Warning: leaving this enabled has security implications
debug version = DEBUG_UNSAFE;

//counters incremented on each function call
//doesn't include Lua builtin/stdlib calls or manually registered calls
debug int gLuaToDCalls, gDToLuaCalls;

//this alias is just so that we can pretend our scripting interface is generic
alias LuaException ScriptingException;
alias LuaState ScriptingState;

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

// Lua 5.2-work2: they introduce LUA_RIDX_*, which are reserved integer indices
//                into the Lua registry; then we have to change this
//actually, all integer keys are already reserved in Lua 5.1, oops.
const cGlobalErrorFuncIdx = 1;

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
    assert(false, "(should be) unused");
/+
    scope (exit) lua_pop(L, 1);
    char[] err = lua_todstring(L, -1);
    throw new LuaException(err);
+/
}

//if the string is going to be used after the Lua value is popped from the
//  stack, you must .dup it (Lua may GC and reuse the string memory)
//this is an optimization; if unsure, use lua_todstring()
private char[] lua_todstring_unsafe(lua_State* L, int i) {
    size_t len;
    char* s = lua_tolstring(L, i, &len);
    if (!s)
        throw new LuaError("non-string type");
    char[] res = s[0..len];
    //as long as the D program is rather fragile about utf-8 errors (anything
    //  parsing utf-8 will throw UnicodeException on invalid utf-8 => basically
    //  that exception may be thrown from random parts of the program), always
    //  disallow Lua to pass invalid utf-8
    try {
        str.validate(res);
    } catch (str.UnicodeException s) {
        //not sure if it should be this exception
        throw new LuaError("invalid utf-8 string");
    }
    return res;
}

//always allocates memory (except if string has len 0)
private char[] lua_todstring(lua_State* L, int i) {
    return lua_todstring_unsafe(L, i).dup;
}

//like lua_todstring, but returns error messages in the string (never throws)
private char[] lua_todstring_protected(lua_State* L, int i) {
    try {
        return lua_todstring(L, i);
    } catch (LuaError e) {
        return '<' ~ e.msg ~ '>';
    }
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

//version of luaL_where() that rerturns the result directly (no Lua stack)
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

//call code() in a more or less "protected" environment:
//- catch Lua errors (lua_error()/error()) properly
//- if there are stray D exceptions, clean up the Lua stack
private T luaProtected(T)(lua_State* state, T delegate() code) {
    //xxx see notes at top of this file
    //    for now, just verify stack use
    int stack = lua_gettop(state);
    scope(success) assert(stack == lua_gettop(state));
    return code();
}

//internal exception that gets thrown on errors in the marshalling code
//lua_pcall's error handler will detect it and wrap it into a LuaException
//  (for the stack trace)
private class LuaError : CustomException {
    this(char[] msg) {
        super(msg);
    }
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

    //constructor for "api-level" errors where the code path did not go through
    //the lua stack (that means we can't get file/line or backtrace)
    this(char[] msg) {
        super(msg);
    }

    //state, level are passed to stackTrace
    //Important: the ONLY place where this constructor should be used is
    //  from lua_pcall's error function; the stack trace is generated there
    //  and nowhere else
    this(lua_State* state, int level, char[] msg, Exception next) {
        auto nmsg = msg;
        //Note: pure lua errors will already contain filename/linenumber
        //  (unless the user is stupid enough to call error() with a non-string)
        if (next) {
            //"level" is the D function that caused the exception,
            //  so the lua pos is at level + 1
            char[] codePos = luaWhere(state, level + 1);
            if (cast(LuaError)next) {
                nmsg = codePos ~ next.msg;
            } else {
                nmsg = codePos ~ "D " ~ className(next) ~ " [" ~ next.msg ~ "]";
            }
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

//this can be used in 2 cases:
//- Lua calls user D code, and the user raised some recoverable exception
//  => e is that (catched) exception, and it is not a LuaException
//- Lua calls D code, and the binding code detects a marshalling error
//  => e is a newly created LuaError, describing the error
//the result will always be that the exception is passed to the lua_pcall error
//  handler, where it gets wrapped in a LuaException (which generates a trace)
//there's a 3rd case, that takes a different code path: if Lua raises an error
//  via lua_error()/error(), lua_pcall's error handler will catch that and
//  create a new LuaException accordingly
private void raiseLuaError(lua_State* state, Exception e) {
    assert(!!e);
    lua_pushlightuserdata(state, cast(void*)e);
    lua_error(state);
}

//use this on errors in the wrapper code
private void raiseLuaError(lua_State* state, char[] msg) {
    //the exception marks an error in the lua wrapper code (in contrast to
    //  exceptions in unrelated D code)
    //xxx: if the backtracer isn't able to get through the Lua VM functions
    //  in all cases (Windows?), we have to think of something else
    raiseLuaError(state, new LuaError(msg));
}

//unrecoverable exception encountered
//print out trace and die on internal exceptions
private void internalError(lua_State* state, Exception e) {
    //go boom immediately to avoid confusion
    //this should also be done for other "runtime" exceptions, but at least
    //  in D1, the exception class hierarchy is too retarded and you have
    //  to catch every single specialized exception type (got fixed in D2)
    Trace.formatln("catching failing irrecoverable error instead of returning"
        " to Lua:");
    e.writeOut((char[] s) { Trace.format("{}", s); });
    Trace.formatln("responsible Lua backtrace:");
    Trace.formatln("{}", luaStackTrace(state, 1));
    Trace.formatln("done, will die now.");
    //this is really better than trying to continue the program
    //Warning: if you should change this, be aware that Lua programs are allowed
    //  to do xpcall(), and Lua programs should in no way be allowed to catch
    //  internal D errors (that would lead to cascading failures, unability to
    //  find the real error cause, etc.)
    //the best way would probably to use skip the Lua C stack with
    //  setjmp/longjmp, or unwind it via D exceptions; maybe the Lua state
    //  would then be inconsistent, but you wouldn't access it anyway
    //one reason why I don't just re-throw the D exception is because it's too
    //  easy to accidentally catch it again in user code (like with:
    //  try{}finally{}, try{}catch(...){}, scope(success) {})
    //  feel free to call me stupid and change it
    //another is that D might not be able to unwind the Lua C stack (but I don't
    //  know; would have to try with Windows, LuaJIT, etc.)
    cstdlib.abort();
}

bool isLuaRecoverableException(Exception e) {
    //recoverable exceptions
    if (cast(CustomException)e
        || cast(ParameterException)e
        || cast(LuaError)e)
        return true;
    //"internal" runtime exceptions
    //in D2, these are all derived from the same type, but not in D1
    //list of types from tango/core/Exception.d
    //add missing types as needed (e.g. I didn't find AccessViolation)
    if (cast(OutOfMemoryException)e
        || cast(SwitchException)e
        || cast(AssertException)e
        || cast(ArrayBoundsException)e
        || cast(FinalizeException)e)
        return false;
    //other exceptions
    //not sure about this *shrug*
    //apparently, we decided that only CustomExceptions are recoverable, which
    //  means all other exception types are non-recoverable
    return false;
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

private void luaExpected(lua_State* state, int stackIdx, char[] expected) {
    luaExpected(state, expected,
        czstr.fromStringz(luaL_typename(state, stackIdx)));
}
private void luaExpected(lua_State* state, char[] expected, char[] got) {
    throw new LuaError(myformat("{} expected, got {}", expected, got));
}

//if this returns a string, you can use it only until you pop the corresponding
//  Lua value from the stack (because after this, Lua may garbage collect it)
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
            return (*pconvert)(lua_todstring_unsafe(state, stackIdx))
                .unbox!(T)();
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
        try {
            if (lua_type(state, stackIdx) == LUA_TSTRING)
                return TempString(lua_todstring_unsafe(state, stackIdx));
        } catch (LuaError e) {
            //not too sure about this, but tells the user about utf-8 errors
            expected(myformat("string ({})", e.msg));
        }
        expected("string");
    } else static if (is(T == class) || is(T == interface)) {
        //allow userdata and nil, nothing else
        if (!lua_islightuserdata(state, stackIdx) && !lua_isnil(state,stackIdx))
            expected("class reference of type "~T.stringof);
        //by convention, all light userdatas are casted from Object
        //which means we can always type check it
        Object o = cast(Object)lua_touserdata(state, stackIdx);
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
        version (none) {
        //the code below works well, but it can't detect table entries that
        //  are not part of the struct (changing this would make it very
        //  inefficient)
            foreach (int idx, x; ret.tupleof) {
                //first try named access
                static assert(ret.tupleof[idx].stringof[0..4] == "ret.");
                luaPush(state, (ret.tupleof[idx].stringof)[4..$]);
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
                        static assert(ret.tupleof[sidx].stringof[0..4] == "ret.");
                        const sname = (ret.tupleof[sidx].stringof)[4..$];
                        if (sname == name) {
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
        luaL_checkstack(state, 10, "Lua stack out of memory");
        lua_pushnil(state);  //first key
        while (lua_next(state, tablepos) != 0) {
            //lua_next pushes key, then value
            static if(is_assoc) {
                auto curVal = luaStackValue!(ValTypeOfAA!(T))(state, -1);
                ret[luaStackValue!(KeyTypeOfAA!(T))(state, -2)] = curVal;
            } else {
                auto index = luaStackValue!(int)(state, -2);
                if (index < 1 || index > ret.length)
                    throw new LuaError(myformat("invalid index in lua array"
                        " table: got {} in range 1-{}", index, ret.length+1));
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
    } else static if (is(T == class) || is(T == interface)) {
        if (value is null) {
            lua_pushnil(state);
        } else {
            lua_pushlightuserdata(state, cast(void*)value);
        }
    } else static if (is(T == Time)) {
        lua_pushnumber(state, value.secsd());
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
        lua_createtable(state, 0, value.tupleof.length);
        foreach (int idx, x; value.tupleof) {
            static assert(value.tupleof[idx].stringof[0..6] == "value.");
            luaPush(state, (value.tupleof[idx].stringof)[6..$]);
            luaPush(state, value.tupleof[idx]);
            lua_rawset(state, -3);
        }
        //set the metatable for the type, if it was set by addScriptType()
        lua_getfield(state, LUA_REGISTRYINDEX, C_Mangle!(T).ptr);
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

//similar to luaPushDelegate
private void luaPushFunction(T)(lua_State* state, T fn) {
    //needing static if instead of just static assert is a syntax artefact
    static if (is(T X : X*) && is(X == function)) {
    } else { static assert(false); }

    extern(C) static int demarshal(lua_State* state) {
        T fn = cast(T)lua_touserdata(state, lua_upvalueindex(1));
        return callFromLua(fn, state, 0, "some D function");
    }

    lua_pushlightuserdata(state, cast(void*)fn);
    lua_pushcclosure(state, &demarshal, 1);
}

//holds a persistent reference to an arbitrary Lua value
private struct LuaReference {
    private {
        lua_State* mState;
        int mLuaRef = LUA_NOREF;
    }

    lua_State* state() {
        return mState;
    }

    //create a reference to the value at stackIdx; the stack is not changed
    void set(lua_State* state, int stackIdx) {
        mState = state;

        //put a "Lua ref" to the value into the reference table
        lua_pushvalue(mState, stackIdx);
        mLuaRef = luaL_ref(mState, LUA_REGISTRYINDEX);
        assert(mLuaRef != LUA_REFNIL);
    }

    //push the referenced value on the stack
    void get() {
        assert(mLuaRef != LUA_NOREF, "call .get() after .release()");
        //get ref'ed value from the reference table
        lua_rawgeti(mState, LUA_REGISTRYINDEX, mLuaRef);
    }

    void release() {
        if (mLuaRef == LUA_NOREF)
            return;
        luaL_unref(mState, LUA_REGISTRYINDEX, mLuaRef);
        mLuaRef = LUA_NOREF;
    }

    bool valid() {
        return mLuaRef != LUA_NOREF;
    }
}

//same as "Wrapper" and same idea from before
//garbage collection: maybe put all wrapper objects into a weaklist, and do
//  regular cleanups (e.g. each game frame); the weaklist would return the set
//  of dead objects free'd since the last query, and the Lua delegate table
//  entry could be removed without synchronization problems
private class LuaDelegateWrapper(T) {
    private lua_State* mState;
    private LuaReference mRef;
    alias ParameterTupleOf!(T) Params;
    alias ReturnTypeOf!(T) RetType;

    //only to be called from luaStackDelegate()
    private this(lua_State* state, int stackIdx) {
        mState = state;
        mRef.set(state, stackIdx);
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
        mRef.get();
        assert(lua_isfunction(mState, -1));
        try {
            //will pop function from the stack
            return doLuaCall!(RetType, Params)(mState, args);
        } catch (LuaException e) {
            //we could be anywhere in the code, and letting the LuaException
            //  through would most certainly cause a crash. So it is passed
            //  to the parent LuaState, which can report it back
            auto lsInst = LuaState.getInstance(mState);
            assert(!!lsInst);
            lsInst.reportDelegateError(e);
            //return default
            static if (!is(RetType == void))
                return RetType.init;
        }
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

//call D -> Lua
//call the function on top of the stack
//xxx see error handling notes at beginning of the file how this should be done
private RetType doLuaCall(RetType, T...)(lua_State* state, T args) {
    debug gDToLuaCalls++;

    lua_pushboolean(state, true); //xxx: error function key
    lua_rawget(state, LUA_REGISTRYINDEX);
    lua_insert(state, -2);
    int argc;
    foreach (int idx, x; args) {
        argc += luaPush(state, args[idx]);
    }
    const bool ret_void = is(RetType == void);
    const int retc = ret_void ? 0 : 1;
    if (lua_pcall(state, argc, retc, -argc - 2) != 0) {
        //error case
        //xxx what if lua_pcall doesn't return LUA_ERRRUN, will there also be
        //  some error message value on the stack?
        //our error handler function always returns a LuaException
        if (lua_type(state, -1) != LUA_TLIGHTUSERDATA)
            assert(false);
        Object o_e = cast(Object)(lua_touserdata(state, -1));
        LuaException e = cast(LuaException)o_e;
        assert(!!e);
        lua_pop(state, 2);
        throw e;
    }
    lua_remove(state, -retc - 1);
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
private int callFromLua(T)(T del, lua_State* state, int skipCount,
    char[] funcName)
{
    //eh static assert(is(T == delegate) || is(T == function));

    debug gLuaToDCalls++;

    void error(char[] msg) {
        throw new LuaError(msg);
    }

    try {
        int numArgs = lua_gettop(state);
        //number of arguments going to the D call
        int numRealArgs = numArgs - skipCount;

        alias ParameterTupleOf!(typeof(del)) Params;

        if (numRealArgs != Params.length) {
            error(myformat("'{}' requires {} arguments, got {}, skip={}",
                funcName, Params.length+skipCount, numArgs, skipCount));
        }

        Params p;

        foreach (int idx, x; p) {
            alias typeof(x) T;
            try {
                p[idx] = luaStackValue!(T)(state, skipCount + idx + 1);
            } catch (LuaError e) {
                error(myformat("bad argument #{} to '{}' ({})", idx + 1,
                    funcName, e.msg));
            }
        }

        static if (is(ReturnTypeOf!(del) == void)) {
            del(p);
            return 0;
        } else {
            auto ret = del(p);
            return luaPush(state, ret);
        }

    } catch (Exception e) {
        if (isLuaRecoverableException(e)) {
            raiseLuaError(state, e);
        } else {
            internalError(state, e);
        }
    }

    assert(false);
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
        char[] name;
        char[] prefix;
        char[] fname;
        lua_CFunction demarshal;
        MethodType type;
        bool inherited;
    }

    this() {
    }

    //e.g. setClassPrefix!(GameEngine)("Game"), to keep scripting names short
    //call before any method() calls
    void setClassPrefix(Class)(char[] name) {
        mPrefixes[Class.classinfo] = name;
    }

    private void registerDMethod(ClassInfo ci, char[] method,
        lua_CFunction demarshal, MethodType type, bool inherited = false)
    {
        assert(!mSealed);
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
        m.inherited = inherited;
        mMethods ~= m;
    }

    private static void methodThisError(lua_State* state, char[] name,
        ClassInfo expected, Object got)
    {
        raiseLuaError(state, myformat("method call to '{}' requires non-null "
            "this pointer of type {} as first argument, but got: {}", name,
            expected.name, got ? got.classinfo.name : "*null"));
    }

    //Register a class method
    void method(Class, char[] name)(char[] rename = null) {
        extern(C) static int demarshal(lua_State* state) {
            const methodName = Class.stringof ~ '.' ~ name;

            Object o = cast(Object)lua_touserdata(state, 1);
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
        const funcName = (&Fn).stringof[2..$];
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

    DefClass!(Class) defClass(Class)(char[] prefixname = "") {
        if (prefixname.length)
            setClassPrefix!(Class)(prefixname);
        return DefClass!(Class)(this);
    }

    void seal() {
        if (mSealed) {
            return;
        }
        fixupInheritance();
        mSealed = true;
    }

    //for every registered method/property, this function checks if there
    //are derived classes registered (which also have this method), and
    //makes the baseclass methods available under the name of the derived class
    //e.g.: GameObject_kill() is made available as Sprite_kill()
    //xxx this could be done on-the-fly while registering (would avoid sealing)
    private void fixupInheritance() {
        //scan all methods...
        foreach (ref baseMethod; mMethods) {
            //methods and properties only
            if (!(baseMethod.type == MethodType.Method
                || baseMethod.type == MethodType.Property_R
                || baseMethod.type == MethodType.Property_W))
            {
                continue;
            }
            //... and see if there is a derived class registered (that,
            //  according to inheritance, also has to provide that method)
            foreach (derivedClass, prefix; mPrefixes) {
                //conditions: implicitly castable, not the same,
                //  base not registered with same prefix
                if (rtraits.isImplicitly(derivedClass, baseMethod.classinfo)
                    && derivedClass !is baseMethod.classinfo
                    && baseMethod.prefix != prefix)
                {
                    //a class was found that can be implicitly casted to the
                    //  class of baseMethod (i.e. derivedClass is derived from
                    //  baseMethod.classinfo)
                    //-> Register baseMethod for derivedClass
                    registerDMethod(derivedClass, baseMethod.name,
                        baseMethod.demarshal, baseMethod.type, true);
                }
            }
        }
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
        const cLuaStateRegId = "D_LuaState_instance";
    }

    //called when an error outside the "normal call path" occurs
    //  (i.e. a D->Lua delegate call fails)
    void delegate(LuaException e) onError;

    const cLanguageAndVersion = LUA_VERSION;

    static bool gLibLuaLoaded = false;

    this(int stdlibFlags = LuaLib.safe) {
        if (!gLibLuaLoaded) {
            char[] libname = env.Environment.get("LUALIB");
            if (!libname.length)
                libname = null; //derelict uses "libname is null"
            DerelictLua.load(libname);
        }

        mLua = lua_newstate(&my_lua_alloc, null);
        lua_atpanic(mLua, &my_lua_panic);
        loadStdLibs(stdlibFlags);

        //this is security relevant; allow only in debug code
        version (DEBUG_UNSAFE) {
            loadStdLibs(LuaLib.debuglib);
            loadStdLibs(LuaLib.packagelib);
        }

        //set "this" reference
        luaPush(mLua, this);
        lua_setfield(mLua, LUA_REGISTRYINDEX, cLuaStateRegId.ptr);

        //own std stuff
        auto reg = new LuaRegistry();
        reg.func!(ObjectToString)();
        reg.func!(className);
        reg.func!(fullClassName);
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
        scriptExec(`_G.d_get_class_metadata = ...`, &script_get_class_metadata);
        scriptExec(`_G.d_get_class = ...`, &script_get_class);
        scriptExec(`_G.d_find_class = ...`, &script_find_class);
        scriptExec(`_G.d_is_class = ...`, &script_is_class);

        //install the pcall error handler
        //I'm using plain Lua API calls to avoid bad interactions with the
        //  marshaller code and all that
        extern (C) static int pcall_err_handler(lua_State* state) {
            //two cases for the error message value:
            //1. Lua code raised this error and may have passed any value
            //2. any Exception was passed through by other error handling code
            Exception stackEx = null;
            char[] msg;
            if (lua_islightuserdata(state, 1)) {
                //note that a Lua script could have used a random D object
                //in that case stackEx would remain null
                Object o = cast(Object)lua_touserdata(state, 1);
                stackEx = cast(Exception)o;
            } else {
                msg = lua_todstring_protected(state, 1);
            }
            //this also gets the Lua and D backtraces
            auto e = new LuaException(state, 1, msg, stackEx);
            //return e
            lua_pop(state, 1);
            lua_pushlightuserdata(state, cast(void*)e);
            return 1;
        }
        //xxx: error function key
        //  use just "true" as key, because: integers are not really allowed in
        //  the lua registry, strings would require rehashing, and booleans are
        //  the only "simple" type left
        lua_pushboolean(state, true);
        lua_pushcfunction(mLua, &pcall_err_handler);
        lua_rawset(mLua, LUA_REGISTRYINDEX);
    }

    void destroy() {
        //let the GC do the work (for now)
        mLua = null;
    }

    //return instance of LuaState from the registry
    private static LuaState getInstance(lua_State* state) {
        lua_getfield(state, LUA_REGISTRYINDEX, cLuaStateRegId.ptr);
        scope(exit) lua_pop(state, 1);
        return luaStackValue!(LuaState)(state, -1);
    }

    //hack for better error handling: delegate wrappers call this on errors
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
        return lua_gc(mLua, LUA_GCCOUNT, 0)*1024
            + lua_gc(mLua, LUA_GCCOUNTB, 0);
    }

    //return the size of the reference table (may give hints about unfree'd
    //  D delegates referencing Lua functions, and stuff)
    //return value will be some values too high, because it actually returns
    //  the size of the registry
    final int reftableSize() {
        //so yeah, need to walk the whole table
        int count = 0;
        stack0();
        lua_pushvalue(mLua, LUA_REGISTRYINDEX);
        lua_pushnil(mLua);
        while (lua_next(mLua, -2) != 0) {
            if (lua_type(mLua, -2) == LUA_TNUMBER)
                count++;
            lua_pop(mLua, 1);
        }
        lua_pop(mLua, 1);
        stack0();
        return count;
    }

    //needed by utils.lua to format userdata
    private static char[] ObjectToString(Object o) {
        return o ? o.toString() : "null";
    }

    void loadStdLibs(int stdlibFlags) {
        foreach (lib; luaLibs) {
            if (stdlibFlags & lib.flag) {
                stack0();
                lua_pushcfunction(mLua, *lib.func);
                luaCall!(void, char[])(lib.name);
                stack0();
            }
        }
    }

    void register(LuaRegistry stuff) {
        stuff.seal();
        foreach (m; stuff.mMethods) {
            auto name = czstr.toStringz(m.fname);

            lua_getglobal(mLua, name);
            bool nil = lua_isnil(mLua, -1);
            lua_pop(mLua, 1);

            if (!nil) {
                //this caused some error which took me 30 minutes of debugging
                //most likely multiple bind calls for a method
                throw new CustomException("attempting to overwrite existing name "
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
        bool inherited;     //automatically added inherited method
    }
    //return MetaData for all known bound D functions for the passed class
    //if from is null, an empty array is returned
    private MetaData[] script_get_class_metadata(ClassInfo from) {
        if (!from)
            return null;
        MetaData[] res;
        foreach (LuaRegistry.Method m; mMethods) {
            if (rtraits.isDerived(from, m.classinfo))
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
        d.lua_g_name = m.fname;
        d.inherited = m.inherited;
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
        return rtraits.isDerived(cls1, cls);
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
        foreach (m; mMethods) {
            if (m.classinfo !is ci)
                continue;
            if (m.type == LuaRegistry.MethodType.StaticMethod) //is_static)
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
            //xxx if this fails to get the message (e.g. utf8 error), there
            //    will be no line number
            char[] err = lua_todstring_protected(mLua, -1);
            throw new LuaException("Parse error: " ~ err);
        }
    }

    //prepended all very-Lua-specific functions with lua
    //functions starting with lua should be avoided in user code

    private void luaLoadAndPush(char[] name, char[] code) {
        StringChunk sc;
        sc.data = code;
        lua_loadChecked(&lua_ReadString, &sc, name);
    }

    private void luaLoadAndPush(char[] name, Stream input) {
        lua_loadChecked(&lua_ReadStream, cast(void*)input, name);
    }

    //another variation
    //load script in "code", using "name" for error messages
    //there's also scriptExec() if you need to pass parameters
    //environmentId = set to create/reuse a named execution environment
    //T = apparently either char[] or Stream for the actual source code
    void loadScript(T)(char[] name, T code, char[] environmentId = null) {
        stack0();
        luaLoadAndPush(name, code);
        if (environmentId.length) {
            luaGetEnvironment(environmentId);
            lua_setfenv(mLua, -2);
        }
        luaCall!(void)();
        stack0();
    }

    //get an execution environment from the registry and push it to the stack
    //the environment is created if it doesn't exist
    //a metatable is set to forward lookups to the globals table
    //(see http://lua-users.org/lists/lua-l/2006-05/msg00121.html )
    private void luaGetEnvironment(char[] environmentId) {
        assert(environmentId.length);
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

            //set environment name as variable "ENV_NAME"
            luaPush(mLua, environmentId);
            lua_setfield(mLua, -2, "ENV_NAME");

            //store for later use
            lua_pushvalue(mLua, -1);
            lua_setfield(mLua, LUA_REGISTRYINDEX, envMangle(environmentId));
        }
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
            scope(success)
                stack0();
            return doLuaCall!(RetType, T)(mLua, args);
        }
    }

    //execute the global scope
    private RetType luaCall(RetType, Args...)(Args args) {
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
    void setGlobal(T)(char[] name, T value, char[] environmentId = null) {
        luaProtected!(void)(mLua, {
            int stackIdx = LUA_GLOBALSINDEX;
            if (environmentId.length) {
                luaGetEnvironment(environmentId);
                stackIdx = -2;
            }
            luaPush(mLua, value);
            lua_setfield(mLua, stackIdx, czstr.toStringz(name));
            if (environmentId.length) {
                lua_pop(mLua, 1);
            }
        });
    }
    T getGlobal(T)(char[] name, char[] environmentId = null) {
        return luaProtected!(T)(mLua, {
            int stackIdx = LUA_GLOBALSINDEX;
            if (environmentId.length) {
                luaGetEnvironment(environmentId);
                stackIdx = -1;
            }
            lua_getfield(mLua, stackIdx, czstr.toStringz(name));
            T res = luaStackValue!(T)(mLua, -1);
            lua_pop(mLua, environmentId.length ? 2 : 1);
            return res;
        });
    }

/+ unneeded?
    //copy symbol name1 from env1 to the global name2 in env2
    //if env2 is null, the symbol is copied to the global environment
    void copyEnvSymbol(char[] env1, char[] name1, char[] env2, char[] name2) {
        assert(env1.length && name1.length && name2.length);
        luaProtected!(void)(mLua, {
            luaGetEnvironment(env1);
            int stackIdx = LUA_GLOBALSINDEX;
            if (env2.length) {
                luaGetEnvironment(env2);
                stackIdx = -2;
            }
            lua_getfield(mLua, -2, czstr.toStringz(name1));
            lua_setfield(mLua, stackIdx, czstr.toStringz(name2));
            lua_pop(mLua, env2.length ? 2 : 1);
        });
    }
+/

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

    void stack0() {
        int stackSize = lua_gettop(mLua);
        assert(stackSize == 0, myformat("Stack size: 0 expected, not {}",
            stackSize));
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
