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
  alias int   function(lua_State *L) lua_CFunction;

  /*
   ** functions that read/write blocks when loading/dumping Lua chunks
   */
  alias char* function(lua_State *L, void *ud, size_t *sz) lua_Reader;
  alias int   function(lua_State *L, void* p, size_t sz, void* ud) lua_Writer;

  /*
   ** prototype for memory-allocation functions
   */
  alias void* function(void *ud, void *ptr, size_t osize, size_t nsize) lua_Alloc;
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
  *cast(void**)&luaL_newstate = Derelict_GetProc(lib, "luaL_newstate");
  *cast(void**)&lua_newstate = Derelict_GetProc(lib, "lua_newstate");
  *cast(void**)&lua_close = Derelict_GetProc(lib, "lua_close");
  *cast(void**)&lua_newthread = Derelict_GetProc(lib, "lua_newthread");
  *cast(void**)&lua_atpanic = Derelict_GetProc(lib, "lua_atpanic");

  *cast(void**)&lua_gettop = Derelict_GetProc(lib, "lua_gettop");
  *cast(void**)&lua_settop = Derelict_GetProc(lib, "lua_settop");
  *cast(void**)&lua_pushvalue = Derelict_GetProc(lib, "lua_pushvalue");
  *cast(void**)&lua_remove = Derelict_GetProc(lib, "lua_remove");
  *cast(void**)&lua_insert = Derelict_GetProc(lib, "lua_insert");
  *cast(void**)&lua_replace = Derelict_GetProc(lib, "lua_replace");
  *cast(void**)&lua_checkstack = Derelict_GetProc(lib, "lua_checkstack");

  *cast(void**)&lua_xmove = Derelict_GetProc(lib, "lua_xmove");

  *cast(void**)&lua_isnumber = Derelict_GetProc(lib, "lua_isnumber");
  *cast(void**)&lua_isstring = Derelict_GetProc(lib, "lua_isstring");
  *cast(void**)&lua_iscfunction = Derelict_GetProc(lib, "lua_iscfunction");
  *cast(void**)&lua_isuserdata = Derelict_GetProc(lib, "lua_isuserdata");
  *cast(void**)&lua_type = Derelict_GetProc(lib, "lua_type");

  *cast(void**)&lua_typename = Derelict_GetProc(lib, "lua_typename");

  *cast(void**)&lua_equal = Derelict_GetProc(lib, "lua_equal");
  *cast(void**)&lua_rawequal = Derelict_GetProc(lib, "lua_rawequal");
  *cast(void**)&lua_lessthan = Derelict_GetProc(lib, "lua_lessthan");

  *cast(void**)&lua_tonumber = Derelict_GetProc(lib, "lua_tonumber");
  *cast(void**)&lua_tointeger = Derelict_GetProc(lib, "lua_tointeger");
  *cast(void**)&lua_toboolean = Derelict_GetProc(lib, "lua_toboolean");
  *cast(void**)&lua_tolstring = Derelict_GetProc(lib, "lua_tolstring");
  *cast(void**)&lua_objlen = Derelict_GetProc(lib, "lua_objlen");
  *cast(void**)&lua_tocfunction = Derelict_GetProc(lib, "lua_tocfunction");
  *cast(void**)&lua_touserdata = Derelict_GetProc(lib, "lua_touserdata");
  *cast(void**)&lua_tothread = Derelict_GetProc(lib, "lua_tothread");
  *cast(void**)&lua_topointer = Derelict_GetProc(lib, "lua_topointer");

  *cast(void**)&lua_pushnil = Derelict_GetProc(lib, "lua_pushnil");
  *cast(void**)&lua_pushnumber = Derelict_GetProc(lib, "lua_pushnumber");
  *cast(void**)&lua_pushinteger = Derelict_GetProc(lib, "lua_pushinteger");
  *cast(void**)&lua_pushlstring = Derelict_GetProc(lib, "lua_pushlstring");
  *cast(void**)&lua_pushstring = Derelict_GetProc(lib, "lua_pushstring");
  *cast(void**)&lua_pushvfstring = Derelict_GetProc(lib, "lua_pushvfstring");
  *cast(void**)&lua_pushfstring = Derelict_GetProc(lib, "lua_pushfstring");
  *cast(void**)&lua_pushcclosure = Derelict_GetProc(lib, "lua_pushcclosure");
  *cast(void**)&lua_pushboolean = Derelict_GetProc(lib, "lua_pushboolean");
  *cast(void**)&lua_pushlightuserdata = Derelict_GetProc(lib, "lua_pushlightuserdata");
  *cast(void**)&lua_pushthread = Derelict_GetProc(lib, "lua_pushthread");

  *cast(void**)&lua_gettable = Derelict_GetProc(lib, "lua_gettable");
  *cast(void**)&lua_getfield = Derelict_GetProc(lib, "lua_getfield");
  *cast(void**)&lua_rawget = Derelict_GetProc(lib, "lua_rawget");
  *cast(void**)&lua_rawgeti = Derelict_GetProc(lib, "lua_rawgeti");
  *cast(void**)&lua_createtable = Derelict_GetProc(lib, "lua_createtable");
  *cast(void**)&lua_newuserdata = Derelict_GetProc(lib, "lua_newuserdata");
  *cast(void**)&lua_getmetatable = Derelict_GetProc(lib, "lua_getmetatable");
  *cast(void**)&lua_getfenv = Derelict_GetProc(lib, "lua_getfenv");

  *cast(void**)&lua_settable = Derelict_GetProc(lib, "lua_settable");
  *cast(void**)&lua_setfield = Derelict_GetProc(lib, "lua_setfield");
  *cast(void**)&lua_rawset = Derelict_GetProc(lib, "lua_rawset");
  *cast(void**)&lua_rawseti = Derelict_GetProc(lib, "lua_rawseti");
  *cast(void**)&lua_setmetatable = Derelict_GetProc(lib, "lua_setmetatable");
  *cast(void**)&lua_setfenv = Derelict_GetProc(lib, "lua_setfenv");

  *cast(void**)&lua_call = Derelict_GetProc(lib, "lua_call");
  *cast(void**)&lua_pcall = Derelict_GetProc(lib, "lua_pcall");
  *cast(void**)&lua_cpcall = Derelict_GetProc(lib, "lua_cpcall");
  *cast(void**)&lua_load = Derelict_GetProc(lib, "lua_load");

  *cast(void**)&lua_dump = Derelict_GetProc(lib, "lua_dump");

  *cast(void**)&lua_yield = Derelict_GetProc(lib, "lua_yield");
  *cast(void**)&lua_resume = Derelict_GetProc(lib, "lua_resume");
  *cast(void**)&lua_status = Derelict_GetProc(lib, "lua_status");

  *cast(void**)&lua_error = Derelict_GetProc(lib, "lua_error");
  *cast(void**)&lua_next = Derelict_GetProc(lib, "lua_next");
  *cast(void**)&lua_concat = Derelict_GetProc(lib, "lua_concat");

  *cast(void**)&lua_getallocf = Derelict_GetProc(lib, "lua_getallocf");
  *cast(void**)&lua_setallocf = Derelict_GetProc(lib, "lua_setallocf");

  *cast(void**)&lua_getstack = Derelict_GetProc(lib, "lua_getstack");
  *cast(void**)&lua_getinfo = Derelict_GetProc(lib, "lua_getinfo");
  *cast(void**)&lua_getlocal = Derelict_GetProc(lib, "lua_getlocal");
  *cast(void**)&lua_setlocal = Derelict_GetProc(lib, "lua_setlocal");
  *cast(void**)&lua_getupvalue = Derelict_GetProc(lib, "lua_getupvalue");
  *cast(void**)&lua_setupvalue = Derelict_GetProc(lib, "lua_setupvalue");

  *cast(void**)&lua_sethook = Derelict_GetProc(lib, "lua_sethook");
  *cast(void**)&lua_gethook = Derelict_GetProc(lib, "lua_gethook");
  *cast(void**)&lua_gethookmask = Derelict_GetProc(lib, "lua_gethookmask");
  *cast(void**)&lua_gethookcount = Derelict_GetProc(lib, "lua_gethookcount");

  // lauxlib

  *cast(void**)&luaL_openlib = Derelict_GetProc(lib, "luaL_openlib");
  *cast(void**)&luaL_getmetafield = Derelict_GetProc(lib, "luaL_getmetafield");
  *cast(void**)&luaL_callmeta = Derelict_GetProc(lib, "luaL_callmeta");
  *cast(void**)&luaL_typerror = Derelict_GetProc(lib, "luaL_typerror");
  *cast(void**)&luaL_argerror = Derelict_GetProc(lib, "luaL_argerror");
  *cast(void**)&luaL_checklstring = Derelict_GetProc(lib, "luaL_checklstring");
  *cast(void**)&luaL_optlstring = Derelict_GetProc(lib, "luaL_optlstring");
  *cast(void**)&luaL_checknumber = Derelict_GetProc(lib, "luaL_checknumber");
  *cast(void**)&luaL_optnumber = Derelict_GetProc(lib, "luaL_optnumber");
  *cast(void**)&luaL_checkinteger = Derelict_GetProc(lib, "luaL_checkinteger");
  *cast(void**)&luaL_optinteger = Derelict_GetProc(lib, "luaL_optinteger");
  *cast(void**)&luaL_checkstack = Derelict_GetProc(lib, "luaL_checkstack");
  *cast(void**)&luaL_checktype = Derelict_GetProc(lib, "luaL_checktype");
  *cast(void**)&luaL_checkany = Derelict_GetProc(lib, "luaL_checkany");

  *cast(void**)&luaL_newmetatable = Derelict_GetProc(lib, "luaL_newmetatable");
  *cast(void**)&luaL_checkudata = Derelict_GetProc(lib, "luaL_checkudata");
  *cast(void**)&luaL_where = Derelict_GetProc(lib, "luaL_where");
  *cast(void**)&luaL_error = Derelict_GetProc(lib, "luaL_error");
  *cast(void**)&luaL_checkoption = Derelict_GetProc(lib, "luaL_checkoption");
  *cast(void**)&luaL_ref = Derelict_GetProc(lib, "luaL_ref");
  *cast(void**)&luaL_unref = Derelict_GetProc(lib, "luaL_unref");
  *cast(void**)&luaL_loadfile = Derelict_GetProc(lib, "luaL_loadfile");
  *cast(void**)&luaL_loadbuffer = Derelict_GetProc(lib, "luaL_loadbuffer");
  *cast(void**)&luaL_loadstring = Derelict_GetProc(lib, "luaL_loadstring");
  *cast(void**)&luaL_gsub = Derelict_GetProc(lib, "luaL_gsub");
  *cast(void**)&luaL_findtable = Derelict_GetProc(lib, "luaL_findtable");

  *cast(void**)&luaL_buffinit = Derelict_GetProc(lib, "luaL_buffinit");
  *cast(void**)&luaL_prepbuffer = Derelict_GetProc(lib, "luaL_prepbuffer");
  *cast(void**)&luaL_addlstring = Derelict_GetProc(lib, "luaL_addlstring");
  *cast(void**)&luaL_addstring = Derelict_GetProc(lib, "luaL_addstring");
  *cast(void**)&luaL_addvalue = Derelict_GetProc(lib, "luaL_addvalue");
  *cast(void**)&luaL_pushresult = Derelict_GetProc(lib, "luaL_pushresult");

  // lualib
  *cast(void**)&luaopen_base = Derelict_GetProc(lib, "luaopen_base");
  *cast(void**)&luaopen_table = Derelict_GetProc(lib, "luaopen_table");
  *cast(void**)&luaopen_io = Derelict_GetProc(lib, "luaopen_io");
  *cast(void**)&luaopen_os = Derelict_GetProc(lib, "luaopen_os");
  *cast(void**)&luaopen_string = Derelict_GetProc(lib, "luaopen_string");
  *cast(void**)&luaopen_math = Derelict_GetProc(lib, "luaopen_math");
  *cast(void**)&luaopen_debug = Derelict_GetProc(lib, "luaopen_debug");
  *cast(void**)&luaopen_package = Derelict_GetProc(lib, "luaopen_package");

  *cast(void**)&luaL_openlibs = Derelict_GetProc(lib, "luaL_openlibs");
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

