module derelict.lua.luafuncs;

import derelict.lua.luatypes;

import std.c.stdarg;

//==============================================================================
// Functions
//==============================================================================
private extern (C) {
    alias void function(lua_State *L, int idx) pflua_stackmodify;
    alias int   function(lua_State *L, int idx) pflua_stackaccess;
    alias int function(lua_State *L, int idx1, int idx2) pflua_compare;
    alias lua_State*    function() pfluaL_newstate;
    alias lua_State*    function(lua_Alloc f, void *ud) pflua_newstate;
    alias void          function(lua_State *L) pflua_close;
    alias lua_State*    function(lua_State *L) pflua_newthread;
    alias lua_CFunction function(lua_State *L, lua_CFunction panicf) pflua_atpanic;
    alias int  function(lua_State *L) pflua_gettop;
    alias int  function(lua_State *L, int sz) pflua_checkstack;
    alias void function(lua_State *from, lua_State *to, int n) pflua_xmove;
    alias char *function(lua_State *L, int tp)  pflua_typename;
    alias lua_Number  function(lua_State *L, int idx) pflua_tonumber;
    alias lua_Integer function(lua_State *L, int idx) pflua_tointeger;
    alias int function(lua_State *L, int idx) pflua_toboolean;
    alias char* function(lua_State *L, int idx, size_t *len) pflua_tolstring;
    alias size_t function(lua_State *L, int idx) pflua_objlen;
    alias lua_CFunction function(lua_State *L, int idx) pflua_tocfunction;
    alias void *function(lua_State *L, int idx) pflua_touserdata;
    alias lua_State *function(lua_State *L, int idx) pflua_tothread;
    alias void *function(lua_State *L, int idx) pflua_topointer;
    alias void  function(lua_State *L) pflua_pushnil;
    alias void  function(lua_State *L, lua_Number n) pflua_pushnumber;
    alias void  function(lua_State *L, lua_Integer n) pflua_pushinteger;
    alias void  function(lua_State *L,  const char *s, size_t l) pflua_pushlstring;
    alias void  function(lua_State *L,  const char *s) pflua_pushstring;
    alias char *function(lua_State *L,  const char *fmt, va_list argp) pflua_pushvfstring;
    alias char *function(lua_State *L,  const char *fmt, ...) pflua_pushfstring;
    alias void  function(lua_State *L, lua_CFunction fn, int n) pflua_pushcclosure;
    alias void  function(lua_State *L, int b) pflua_pushboolean;
    alias void  function(lua_State *L, void *p) pflua_pushlightuserdata;
    alias int   function(lua_State *L) pflua_pushthread;
    alias void  function(lua_State *L, int idx) pflua_gettable;
    alias void  function(lua_State *L, int idx, const char *k) pflua_getfield;
    alias void  function(lua_State *L, int idx) pflua_rawget;
    alias void  function(lua_State *L, int idx, int n) pflua_rawgeti;
    alias void  function(lua_State *L, int narr, int nrec) pflua_createtable;
    alias void* function(lua_State *L, size_t sz) pflua_newuserdata;
    alias int   function(lua_State *L, int objindex) pflua_getmetatable;
    alias void  function(lua_State *L, int idx) pflua_getfenv;
    alias void  function(lua_State *L, int idx) pflua_settable;
    alias void  function(lua_State *L, int idx, const char *k) pflua_setfield;
    alias void  function(lua_State *L, int idx) pflua_rawset;
    alias void  function(lua_State *L, int idx, int n) pflua_rawseti;
    alias int   function(lua_State *L, int objindex) pflua_setmetatable;
    alias int   function(lua_State *L, int idx) pflua_setfenv;
    alias void function(lua_State *L, int nargs, int nresults) pflua_call;
    alias int  function(lua_State *L, int nargs, int nresults, int errfunc) pflua_pcall;
    alias int  function(lua_State *L, lua_CFunction func, void *ud) pflua_cpcall;
    alias int  function(lua_State *L, lua_Reader reader, void *dt, const char *chunkname) pflua_load;
    alias int  function(lua_State *L, lua_Writer writer, void *data) pflua_dump;
    alias int  function(lua_State *L, int nresults) pflua_yield;
    alias int  function(lua_State *L, int narg) pflua_resume;
    alias int  function(lua_State *L) pflua_status;
    alias int function(lua_State *L, int what, int data) pflua_gc;
    alias int  function(lua_State *L) pflua_error;
    alias int  function(lua_State *L, int idx) pflua_next;
    alias void function(lua_State *L, int n) pflua_concat;
    alias lua_Alloc function(lua_State *L, void **ud) pflua_getallocf;
    alias void      function(lua_State *L, lua_Alloc f, void *ud) pflua_setallocf;
    alias int  function(lua_State *L, int level, lua_Debug *ar) pflua_getstack;
    alias int  function(lua_State *L,  const char *what, lua_Debug *ar) pflua_getinfo;
    alias char * function(lua_State *L,  lua_Debug *ar, int n) pflua_getlocal;
    alias char * function(lua_State *L,  lua_Debug *ar, int n) pflua_setlocal;
    alias char * function(lua_State *L, int funcindex, int n) pflua_getupvalue;
    alias char * function(lua_State *L, int funcindex, int n) pflua_setupvalue;
    alias int  function(lua_State *L, lua_Hook func, int mask, int count) pflua_sethook;
    alias lua_Hook  function(lua_State *L) pflua_gethook;
    alias int  function(lua_State *L) pflua_gethookmask;
    alias int  function(lua_State *L) pflua_gethookcount;
}

__gshared {
  /*
   ** state manipulation
   */
  pfluaL_newstate luaL_newstate;
  pflua_newstate lua_newstate;
  pflua_close lua_close;
  pflua_newthread lua_newthread;
  pflua_atpanic lua_atpanic;

  /*
   ** basic stack manipulation
   */
  pflua_gettop lua_gettop;
  
  pflua_stackmodify lua_settop;
  pflua_stackmodify lua_pushvalue;
  pflua_stackmodify lua_remove;
  pflua_stackmodify lua_insert;
  pflua_stackmodify lua_replace;
  pflua_checkstack lua_checkstack;

  pflua_xmove lua_xmove;

  /*
   ** access functions (stack -> C)
   */

  
  pflua_stackaccess lua_isnumber;
  pflua_stackaccess lua_isstring;
  pflua_stackaccess lua_iscfunction;
  pflua_stackaccess lua_isuserdata;
  pflua_stackaccess lua_type;
  pflua_typename lua_typename;

  
  pflua_compare lua_equal;
  pflua_compare lua_rawequal;
  pflua_compare lua_lessthan;

  pflua_tonumber lua_tonumber;
  pflua_tointeger lua_tointeger;
  pflua_toboolean lua_toboolean;
  pflua_tolstring lua_tolstring;
  pflua_objlen lua_objlen;
  pflua_tocfunction lua_tocfunction;
  pflua_touserdata lua_touserdata;
  pflua_tothread lua_tothread;
  pflua_topointer lua_topointer;

  /*
   ** push functions (C -> stack)
   */
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
  pflua_gettable lua_gettable;
  pflua_getfield lua_getfield;
  pflua_rawget lua_rawget;
  pflua_rawgeti lua_rawgeti;
  pflua_createtable lua_createtable;
  pflua_newuserdata lua_newuserdata;
  pflua_getmetatable lua_getmetatable;
  pflua_getfenv lua_getfenv;

  /*
   ** set functions (stack -> Lua)
   */
  pflua_settable lua_settable;
  pflua_setfield lua_setfield;
  pflua_rawset lua_rawset;
  pflua_rawseti lua_rawseti;
  pflua_setmetatable lua_setmetatable;
  pflua_setfenv lua_setfenv;

  /*
   ** `load' and `call' functions (load and run Lua code)
   */
  pflua_call lua_call;
  pflua_pcall lua_pcall;
  pflua_cpcall lua_cpcall;
  pflua_load lua_load;
  pflua_dump lua_dump;

  /*
   ** coroutine functions
   */
  pflua_yield lua_yield;
  pflua_resume lua_resume;
  pflua_status lua_status;

  /*
   ** garbage-collection function and options
   */

  pflua_gc lua_gc;

  /*
   ** miscellaneous functions
   */

  pflua_error lua_error;
  pflua_next lua_next;
  pflua_concat lua_concat;

  pflua_getallocf lua_getallocf;
  pflua_setallocf lua_setallocf;

  /* Functions to be called by the debugger in specific events */

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
}


/*
 ** ===============================================================
 ** some useful macros
 ** ===============================================================
 */

void lua_pop(lua_State *L, int n) { lua_settop(L, -n-1); }

void lua_newtable(lua_State *L) { lua_createtable(L, 0, 0); }

void lua_register(lua_State *L, const char *n, lua_CFunction f)
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

void lua_pushliteral(lua_State *L, string s)
{
  lua_pushlstring(L, s.ptr, s.length);
}

void lua_setglobal(lua_State *L, const char *s) { lua_setfield(L, LUA_GLOBALSINDEX, s); }
void lua_getglobal(lua_State *L, const char *s) { lua_getfield(L, LUA_GLOBALSINDEX, s); }

char* lua_tostring(lua_State* L, int i) { return lua_tolstring(L, i, null); }

/*
 ** compatibility macros and functions
 */

alias luaL_newstate lua_open;
void  lua_getregistry(lua_State *L) { lua_pushvalue(L, LUA_REGISTRYINDEX); }
int   lua_getgccount(lua_State *L)  { return lua_gc(L, LUA_GCCOUNT, 0); }

