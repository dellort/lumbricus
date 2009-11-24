/******************************************************************************
 * Copyright (C) 1994-2004 Tecgraf, PUC-Rio.  All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 ******************************************************************************/

module derelict.lua.lua;

public
{
  import derelict.lua.luaconf;
  import derelict.lua.lualib;
  import derelict.lua.lauxlib;
}

private
{
  import derelict.util.loader;
  version (Tango) {
    import tango.stdc.stdarg : va_list;
  } else {
    import std.c.stdarg;
  }
}

//==============================================================================
// Types
//==============================================================================
// add: constants
const char[] LUA_VERSION     = "Lua 5.1";
const char[] LUA_RELEASE     = "Lua 5.1.1";
const int    LUA_VERSION_NUM = 501;
const char[] LUA_COPYRIGHT   = "Copyright (C) 1994-2006 Lua.org, PUC-Rio";
const char[] LUA_AUTHORS 	   = "R. Ierusalimschy, L. H. de Figueiredo & W.  Celes";

const char[] LUA_SIGNATURE   = "\033Lua";

/* option for multiple returns in `lua_pcall' and `lua_call' */
int LUA_MULTRET =	-1;

/*
** pseudo-indices
*/
const int LUA_REGISTRYINDEX	= -10000;
const int LUA_ENVIRONINDEX	= -10001;
const int LUA_GLOBALSINDEX	= -10002;
int lua_upvalueindex(int i) { return LUA_GLOBALSINDEX - i; }

/* error codes for `lua_load' and `lua_pcall' */
enum
{
  LUA_YIELD     = 1,
  LUA_ERRRUN    = 2,
  LUA_ERRSYNTAX = 3,
  LUA_ERRMEM    = 4,
  LUA_ERRERR    = 5
}

extern (C)
{
  //  lua_State is used as an opaque pointer
  struct lua_State { }
  typedef int   function(lua_State *L) lua_CFunction;

  /*
   ** functions that read/write blocks when loading/dumping Lua chunks
   */
  typedef char* function(lua_State *L, void *ud, size_t *sz) lua_Reader;
  typedef int   function(lua_State *L, void* p, size_t sz, void* ud) lua_Writer;

  /*
   ** prototype for memory-allocation functions
   */
  typedef void* function(void *ud, void *ptr, size_t osize, size_t nsize) lua_Alloc;
}

/*
 ** basic types
 */
enum
{
  LUA_TNONE          = -1,
  LUA_TNIL           = 0,
  LUA_TBOOLEAN       = 1,
  LUA_TLIGHTUSERDATA = 2,
  LUA_TNUMBER        = 3,
  LUA_TSTRING        = 4,
  LUA_TTABLE         = 5,
  LUA_TFUNCTION      = 6,
  LUA_TUSERDATA      = 7,
  LUA_TTHREAD        = 8
}

/* minimum Lua stack available to a C function */
const int LUA_MINSTACK = 20;

/* type of numbers in Lua */
alias LUA_NUMBER  lua_Number;

/* type for integer functions */
alias LUA_INTEGER lua_Integer;

/*
 ** {======================================================================
 ** Debug API
 ** =======================================================================
 */

/*
 ** Event codes
 */
enum
{
  LUA_HOOKCALL    = 0,
  LUA_HOOKRET     = 1,
  LUA_HOOKLINE    = 2,
  LUA_HOOKCOUNT   = 3,
  LUA_HOOKTAILRET = 4
}


/*
 ** Event masks
 */
const int LUA_MASKCALL  =	(1 << LUA_HOOKCALL);
const int LUA_MASKRET   = (1 << LUA_HOOKRET);
const int LUA_MASKLINE  =	(1 << LUA_HOOKLINE);
const int LUA_MASKCOUNT =	(1 << LUA_HOOKCOUNT);

struct lua_Debug {
  int event;
  const char *name;
  const char *namewhat;
  const char *what;
  const char *source;
  int currentline;
  int nups;
  int linedefined;
  int lastlinedefined;
  char short_src[LUA_IDSIZE];
  /* private part */
  int i_ci;  /* active function */
}

/* compatibility with ref system */

/* pre-defined references */
const int LUA_NOREF	= (-2);
const int LUA_REFNIL	= (-1);

//==============================================================================
// Functions
//==============================================================================
extern (C)
{
  /*
   ** state manipulation
   */
  typedef lua_State*    function() pfluaL_newstate;
  typedef lua_State*    function(lua_Alloc f, void *ud) pflua_newstate;
  typedef void          function(lua_State *L) pflua_close;
  typedef lua_State*    function(lua_State *L) pflua_newthread;
  typedef lua_CFunction function(lua_State *L, lua_CFunction panicf) pflua_atpanic;

  pfluaL_newstate luaL_newstate;
  pflua_newstate  lua_newstate;
  pflua_close     lua_close;
  pflua_newthread lua_newthread;
  pflua_atpanic   lua_atpanic;

  /*
   ** basic stack manipulation
   */
  typedef int  function(lua_State *L) pflua_gettop;
  typedef void function(lua_State *L, int idx) pflua_stackmodify;
  typedef int  function(lua_State *L, int sz) pflua_checkstack;

  typedef void function(lua_State *from, lua_State *to, int n) pflua_xmove;

  pflua_gettop      lua_gettop;
  pflua_stackmodify lua_settop;
  pflua_stackmodify lua_pushvalue;
  pflua_stackmodify lua_remove;
  pflua_stackmodify lua_insert;
  pflua_stackmodify lua_replace;
  pflua_checkstack  lua_checkstack;

  pflua_xmove       lua_xmove;

  /*
   ** access functions (stack -> C)
   */

  typedef int   function(lua_State *L, int idx) pflua_stackaccess;
  typedef char *function(lua_State *L, int tp)  pflua_typename;

  pflua_stackaccess lua_isnumber;
  pflua_stackaccess lua_isstring;
  pflua_stackaccess lua_iscfunction;
  pflua_stackaccess lua_isuserdata;
  pflua_stackaccess lua_type;

  pflua_typename lua_typename;

  typedef int function(lua_State *L, int idx1, int idx2) pflua_compare;
  pflua_compare lua_equal;
  pflua_compare lua_rawequal;
  pflua_compare lua_lessthan;

  typedef lua_Number  function(lua_State *L, int idx) pflua_tonumber;
  typedef lua_Integer function(lua_State *L, int idx) pflua_tointeger;
  typedef int function(lua_State *L, int idx) pflua_toboolean;
  typedef char* function(lua_State *L, int idx, size_t *len) pflua_tolstring;
  typedef size_t function(lua_State *L, int idx) pflua_objlen;
  typedef lua_CFunction function(lua_State *L, int idx) pflua_tocfunction;
  typedef void *function(lua_State *L, int idx) pflua_touserdata;
  typedef lua_State *function(lua_State *L, int idx) pflua_tothread;
  typedef  void *function(lua_State *L, int idx) pflua_topointer;

  pflua_tonumber    lua_tonumber;
  pflua_tointeger   lua_tointeger;
  pflua_toboolean   lua_toboolean;
  pflua_tolstring   lua_tolstring;
  pflua_objlen      lua_objlen;
  pflua_tocfunction lua_tocfunction;
  pflua_touserdata  lua_touserdata;
  pflua_tothread    lua_tothread;
  pflua_topointer   lua_topointer;

  /*
   ** push functions (C -> stack)
   */
  typedef void  function(lua_State *L) pflua_pushnil;
  typedef void  function(lua_State *L, lua_Number n) pflua_pushnumber;
  typedef void  function(lua_State *L, lua_Integer n) pflua_pushinteger;
  typedef void  function(lua_State *L,  char *s, size_t l) pflua_pushlstring;
  typedef void  function(lua_State *L,  char *s) pflua_pushstring;
  typedef char *function(lua_State *L,  char *fmt, va_list argp) pflua_pushvfstring;
  typedef char *function(lua_State *L,  char *fmt, ...) pflua_pushfstring;
  typedef void  function(lua_State *L, lua_CFunction fn, int n) pflua_pushcclosure;
  typedef void  function(lua_State *L, int b) pflua_pushboolean;
  typedef void  function(lua_State *L, void *p) pflua_pushlightuserdata;
  typedef int   function(lua_State *L) pflua_pushthread;

  pflua_pushnil lua_pushnil;
  pflua_pushnumber lua_pushnumber;
  pflua_pushinteger lua_pushinteger;
  pflua_pushlstring lua_pushlstring;
  pflua_pushstring lua_pushstring;
  pflua_pushvfstring lua_pushvfstring;
  pflua_pushfstring lua_pushfstring;
  pflua_pushcclosure lua_pushcclosure;
  pflua_pushboolean lua_pushboolean;
  pflua_pushlightuserdata lua_pushlightuserdata;
  pflua_pushthread lua_pushthread;

  /*
   ** get functions (Lua -> stack)
   */
  typedef void  function(lua_State *L, int idx) pflua_gettable;
  typedef void  function(lua_State *L, int idx, char *k) pflua_getfield;
  typedef void  function(lua_State *L, int idx) pflua_rawget;
  typedef void  function(lua_State *L, int idx, int n) pflua_rawgeti;
  typedef void  function(lua_State *L, int narr, int nrec) pflua_createtable;
  typedef void* function(lua_State *L, size_t sz) pflua_newuserdata;
  typedef int   function(lua_State *L, int objindex) pflua_getmetatable;
  typedef void  function(lua_State *L, int idx) pflua_getfenv;

  /*
   ** set functions (stack -> Lua)
   */
  typedef void  function(lua_State *L, int idx) pflua_settable;
  typedef void  function(lua_State *L, int idx, char *k) pflua_setfield;
  typedef void  function(lua_State *L, int idx) pflua_rawset;
  typedef void  function(lua_State *L, int idx, int n) pflua_rawseti;
  typedef int   function(lua_State *L, int objindex) pflua_setmetatable;
  typedef int   function(lua_State *L, int idx) pflua_setfenv;

  pflua_gettable lua_gettable;
  pflua_getfield lua_getfield;
  pflua_rawget lua_rawget;
  pflua_rawgeti lua_rawgeti;
  pflua_createtable lua_createtable;
  pflua_newuserdata lua_newuserdata;
  pflua_getmetatable lua_getmetatable;
  pflua_getfenv lua_getfenv;

  pflua_settable lua_settable;
  pflua_setfield lua_setfield;
  pflua_rawset lua_rawset;
  pflua_rawseti lua_rawseti;
  pflua_setmetatable lua_setmetatable;
  pflua_setfenv lua_setfenv;

  /*
   ** `load' and `call' functions (load and run Lua code)
   */
  typedef void function(lua_State *L, int nargs, int nresults) pflua_call;
  typedef int  function(lua_State *L, int nargs, int nresults, int errfunc) pflua_pcall;
  typedef int  function(lua_State *L, lua_CFunction func, void *ud) pflua_cpcall;
  typedef int  function(lua_State *L, lua_Reader reader, void *dt, char *chunkname) pflua_load;
  typedef int  function(lua_State *L, lua_Writer writer, void *data) pflua_dump;

  pflua_call   lua_call;
  pflua_pcall  lua_pcall;
  pflua_cpcall lua_cpcall ;
  pflua_load   lua_load ;

  pflua_dump   lua_dump ;

  /*
   ** coroutine functions
   */
  typedef int  function(lua_State *L, int nresults) pflua_yield;
  typedef int  function(lua_State *L, int narg) pflua_resume;
  typedef int  function(lua_State *L) pflua_status;

  pflua_yield  lua_yield;
  pflua_resume lua_resume;
  pflua_status lua_status;

  /*
   ** garbage-collection function and options
   */
  enum
  {
    LUA_GCSTOP = 0,
    LUA_GCRESTART = 1,
    LUA_GCCOLLECT = 2,
    LUA_GCCOUNT = 3,
    LUA_GCCOUNTB = 4,
    LUA_GCSTEP = 5,
    LUA_GCSETPAUSE = 6,
    LUA_GCSETSTEPMUL = 7,
  }

  typedef int function(lua_State *L, int what, int data) pflua_gc;
  pflua_gc lua_gc;

  /*
   ** miscellaneous functions
   */
  typedef int  function(lua_State *L) pflua_error;

  typedef int  function(lua_State *L, int idx) pflua_next;

  typedef void function(lua_State *L, int n) pflua_concat;

  typedef lua_Alloc function(lua_State *L, void **ud) pflua_getallocf;
  typedef void      function(lua_State *L, lua_Alloc f, void *ud) pflua_setallocf;

  pflua_error lua_error;
  pflua_next lua_next;
  pflua_concat lua_concat;

  pflua_getallocf lua_getallocf;
  pflua_setallocf lua_setallocf;

  /* Functions to be called by the debugger in specific events */
  typedef void (*lua_Hook) (lua_State *L, lua_Debug *ar);

  typedef int  function(lua_State *L, int level, lua_Debug *ar) pflua_getstack;
  typedef int  function(lua_State *L,  char *what, lua_Debug *ar) pflua_getinfo;
  typedef  char * function(lua_State *L,  lua_Debug *ar, int n) pflua_getlocal;
  typedef  char * function(lua_State *L,  lua_Debug *ar, int n) pflua_setlocal;
  typedef  char * function(lua_State *L, int funcindex, int n) pflua_getupvalue;
  typedef  char * function(lua_State *L, int funcindex, int n) pflua_setupvalue;

  typedef int  function(lua_State *L, lua_Hook func, int mask, int count) pflua_sethook;
  typedef lua_Hook  function(lua_State *L) pflua_gethook;
  typedef int  function(lua_State *L) pflua_gethookmask;
  typedef int  function(lua_State *L) pflua_gethookcount;

  pflua_getstack lua_getstack;
  pflua_getinfo lua_getinfo;
  pflua_getlocal lua_getlocal;
  pflua_setlocal lua_setlocal;
  pflua_getupvalue lua_getupvalue;
  pflua_setupvalue lua_setupvalue;

  pflua_sethook lua_sethook;
  pflua_gethook lua_gethook;
  pflua_gethookmask lua_gethookmask;
  pflua_gethookcount lua_gethookcount;

} // extern (C)


/*
 ** ===============================================================
 ** some useful macros
 ** ===============================================================
 */

void lua_pop(lua_State *L, int n) { lua_settop(L, -n-1); }

void lua_newtable(lua_State *L) { lua_createtable(L, 0, 0); }

void lua_register(lua_State *L, char *n, lua_CFunction f)
{
  lua_pushcfunction(L, f);
  lua_setglobal(L, n);
}

void lua_pushcfunction(lua_State *L, lua_CFunction f)
{
  lua_pushcclosure(L, f, 0);
}

alias lua_objlen lua_strlen;

bool lua_isfunction(lua_State *L, int n)      { return (lua_type(L,n) == LUA_TFUNCTION); }
bool lua_istable(lua_State *L, int n)         { return (lua_type(L,n) == LUA_TTABLE); }
bool lua_islightuserdata(lua_State *L, int n)	{ return (lua_type(L,n) == LUA_TLIGHTUSERDATA); }
bool lua_isnil(lua_State *L, int n)           { return (lua_type(L,n) == LUA_TNIL); }
bool lua_isboolean(lua_State *L, int n)       { return (lua_type(L,n) == LUA_TBOOLEAN); }
bool lua_isnone(lua_State *L, int n)          { return (lua_type(L,n) == LUA_TNONE); }
bool lua_isnoneornil(lua_State *L, int n)     { return (lua_type(L,n) <= 0); }

void lua_pushliteral(lua_State *L, char[] s)
{
  lua_pushlstring(L, s.ptr, s.length);
}

void lua_setglobal(lua_State *L, char *s) { lua_setfield(L, LUA_GLOBALSINDEX, s); }
void lua_getglobal(lua_State *L, char *s) { lua_getfield(L, LUA_GLOBALSINDEX, s); }

char* lua_tostring(lua_State* L, int i) { return lua_tolstring(L, i, null); }
char[] lua_todstring(lua_State* L, int i) {
    size_t len;
    char* s = lua_tolstring(L, i, &len);
    return s[0..len];
}

/*
 ** compatibility macros and functions
 */

alias luaL_newstate lua_open;
void  lua_getregistry(lua_State *L) { lua_pushvalue(L, LUA_REGISTRYINDEX); }
int   lua_getgccount(lua_State *L)  { return lua_gc(L, LUA_GCCOUNT, 0); }

//==============================================================================
// Loader
//==============================================================================
// private SharedLib libLua;


private void load(SharedLib lib)
{
  bindFunc(luaL_newstate)("luaL_newstate", lib);
  bindFunc(lua_newstate)("lua_newstate", lib);
  bindFunc(lua_close)("lua_close", lib);
  bindFunc(lua_newthread)("lua_newthread", lib);
  bindFunc(lua_atpanic)("lua_atpanic", lib);

  bindFunc(lua_gettop)("lua_gettop", lib);
  bindFunc(lua_settop)("lua_settop", lib);
  bindFunc(lua_pushvalue)("lua_pushvalue", lib);
  bindFunc(lua_remove)("lua_remove", lib);
  bindFunc(lua_insert)("lua_insert", lib);
  bindFunc(lua_replace)("lua_replace", lib);
  bindFunc(lua_checkstack)("lua_checkstack", lib);

  bindFunc(lua_xmove)("lua_xmove", lib);

  bindFunc(lua_isnumber)("lua_isnumber", lib);
  bindFunc(lua_isstring)("lua_isstring", lib);
  bindFunc(lua_iscfunction)("lua_iscfunction", lib);
  bindFunc(lua_isuserdata)("lua_isuserdata", lib);
  bindFunc(lua_type)("lua_type", lib);

  bindFunc(lua_typename)("lua_typename", lib);

  bindFunc(lua_equal)("lua_equal", lib);
  bindFunc(lua_rawequal)("lua_rawequal", lib);
  bindFunc(lua_lessthan)("lua_lessthan", lib);

  bindFunc(lua_tonumber)("lua_tonumber", lib);
  bindFunc(lua_tointeger)("lua_tointeger", lib);
  bindFunc(lua_toboolean)("lua_toboolean", lib);
  bindFunc(lua_tolstring)("lua_tolstring", lib);
  bindFunc(lua_objlen)("lua_objlen", lib);
  bindFunc(lua_tocfunction)("lua_tocfunction", lib);
  bindFunc(lua_touserdata)("lua_touserdata", lib);
  bindFunc(lua_tothread)("lua_tothread", lib);
  bindFunc(lua_topointer)("lua_topointer", lib);

  bindFunc(lua_pushnil)("lua_pushnil", lib);
  bindFunc(lua_pushnumber)("lua_pushnumber", lib);
  bindFunc(lua_pushinteger)("lua_pushinteger", lib);
  bindFunc(lua_pushlstring)("lua_pushlstring", lib);
  bindFunc(lua_pushstring)("lua_pushstring", lib);
  bindFunc(lua_pushvfstring)("lua_pushvfstring", lib);
  bindFunc(lua_pushfstring)("lua_pushfstring", lib);
  bindFunc(lua_pushcclosure)("lua_pushcclosure", lib);
  bindFunc(lua_pushboolean)("lua_pushboolean", lib);
  bindFunc(lua_pushlightuserdata)("lua_pushlightuserdata", lib);
  bindFunc(lua_pushthread)("lua_pushthread", lib);

  bindFunc(lua_gettable)("lua_gettable", lib);
  bindFunc(lua_getfield)("lua_getfield", lib);
  bindFunc(lua_rawget)("lua_rawget", lib);
  bindFunc(lua_rawgeti)("lua_rawgeti", lib);
  bindFunc(lua_createtable)("lua_createtable", lib);
  bindFunc(lua_newuserdata)("lua_newuserdata", lib);
  bindFunc(lua_getmetatable)("lua_getmetatable", lib);
  bindFunc(lua_getfenv)("lua_getfenv", lib);

  bindFunc(lua_settable)("lua_settable", lib);
  bindFunc(lua_setfield)("lua_setfield", lib);
  bindFunc(lua_rawset)("lua_rawset", lib);
  bindFunc(lua_rawseti)("lua_rawseti", lib);
  bindFunc(lua_setmetatable)("lua_setmetatable", lib);
  bindFunc(lua_setfenv)("lua_setfenv", lib);

  bindFunc(lua_call)("lua_call", lib);
  bindFunc(lua_pcall)("lua_pcall", lib);
  bindFunc(lua_cpcall)("lua_cpcall", lib);
  bindFunc(lua_load)("lua_load", lib);

  bindFunc(lua_dump)("lua_dump", lib);

  bindFunc(lua_yield)("lua_yield", lib);
  bindFunc(lua_resume)("lua_resume", lib);
  bindFunc(lua_status)("lua_status", lib);

  bindFunc(lua_error)("lua_error", lib);
  bindFunc(lua_next)("lua_next", lib);
  bindFunc(lua_concat)("lua_concat", lib);

  bindFunc(lua_getallocf)("lua_getallocf", lib);
  bindFunc(lua_setallocf)("lua_setallocf", lib);

  bindFunc(lua_getstack)("lua_getstack", lib);
  bindFunc(lua_getinfo)("lua_getinfo", lib);
  bindFunc(lua_getlocal)("lua_getlocal", lib);
  bindFunc(lua_setlocal)("lua_setlocal", lib);
  bindFunc(lua_getupvalue)("lua_getupvalue", lib);
  bindFunc(lua_setupvalue)("lua_setupvalue", lib);

  bindFunc(lua_sethook)("lua_sethook", lib);
  bindFunc(lua_gethook)("lua_gethook", lib);
  bindFunc(lua_gethookmask)("lua_gethookmask", lib);
  bindFunc(lua_gethookcount)("lua_gethookcount", lib);

  // lauxlib

  bindFunc(luaL_openlib)("luaL_openlib", lib);
  bindFunc(luaL_getmetafield)("luaL_getmetafield", lib);
  bindFunc(luaL_callmeta)("luaL_callmeta", lib);
  bindFunc(luaL_typerror)("luaL_typerror", lib);
  bindFunc(luaL_argerror)("luaL_argerror", lib);
  bindFunc(luaL_checklstring)("luaL_checklstring", lib);
  bindFunc(luaL_optlstring)("luaL_optlstring", lib);
  bindFunc(luaL_checknumber)("luaL_checknumber", lib);
  bindFunc(luaL_optnumber)("luaL_optnumber", lib);
  bindFunc(luaL_checkinteger)("luaL_checkinteger", lib);
  bindFunc(luaL_optinteger)("luaL_optinteger", lib);
  bindFunc(luaL_checkstack)("luaL_checkstack", lib);
  bindFunc(luaL_checktype)("luaL_checktype", lib);
  bindFunc(luaL_checkany)("luaL_checkany", lib);

  bindFunc(luaL_newmetatable)("luaL_newmetatable", lib);
  bindFunc(luaL_checkudata)("luaL_checkudata", lib);
  bindFunc(luaL_where)("luaL_where", lib);
  bindFunc(luaL_error)("luaL_error", lib);
  bindFunc(luaL_checkoption)("luaL_checkoption", lib);
  bindFunc(luaL_ref)("luaL_ref", lib);
  bindFunc(luaL_unref)("luaL_unref", lib);
  bindFunc(luaL_loadfile)("luaL_loadfile", lib);
  bindFunc(luaL_loadbuffer)("luaL_loadbuffer", lib);
  bindFunc(luaL_loadstring)("luaL_loadstring", lib);
  bindFunc(luaL_gsub)("luaL_gsub", lib);
  bindFunc(luaL_findtable)("luaL_findtable", lib);

  bindFunc(luaL_buffinit)("luaL_buffinit", lib);
  bindFunc(luaL_prepbuffer)("luaL_prepbuffer", lib);
  bindFunc(luaL_addlstring)("luaL_addlstring", lib);
  bindFunc(luaL_addstring)("luaL_addstring", lib);
  bindFunc(luaL_addvalue)("luaL_addvalue", lib);
  bindFunc(luaL_pushresult)("luaL_pushresult", lib);

  // lualib
  bindFunc(luaopen_base)("luaopen_base", lib);
  bindFunc(luaopen_table)("luaopen_table", lib);
  bindFunc(luaopen_io)("luaopen_io", lib);
  bindFunc(luaopen_os)("luaopen_os", lib);
  bindFunc(luaopen_string)("luaopen_string", lib);
  bindFunc(luaopen_math)("luaopen_math", lib);
  bindFunc(luaopen_debug)("luaopen_debug", lib);
  bindFunc(luaopen_package)("luaopen_package", lib);

  bindFunc(luaL_openlibs)("luaL_openlibs", lib);
}

GenericLoader DerelictLua;
static this()
{
  DerelictLua.setup(
      "lua5.1.dll",
      "liblua5.1.so.0", // XXX linux lib list
      "", // Mac
      &load
      );
}

