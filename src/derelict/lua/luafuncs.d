module derelict.lua.luafuncs;

import derelict.lua.luatypes;

version (Tango) {
    import tango.stdc.stdarg : va_list;
} else {
    import std.c.stdarg;
}

//==============================================================================
// Functions
//==============================================================================
extern (C)
{
  /*
   ** state manipulation
   */
  lua_State*    function() luaL_newstate;
  lua_State*    function(lua_Alloc f, void *ud) lua_newstate;
  void          function(lua_State *L) lua_close;
  lua_State*    function(lua_State *L) lua_newthread;
  lua_CFunction function(lua_State *L, lua_CFunction panicf) lua_atpanic;

  /*
   ** basic stack manipulation
   */
  int  function(lua_State *L) lua_gettop;
  typedef void function(lua_State *L, int idx) pflua_stackmodify;
  pflua_stackmodify lua_settop;
  pflua_stackmodify lua_pushvalue;
  pflua_stackmodify lua_remove;
  pflua_stackmodify lua_insert;
  pflua_stackmodify lua_replace;
  int  function(lua_State *L, int sz) lua_checkstack;

  void function(lua_State *from, lua_State *to, int n) lua_xmove;

  /*
   ** access functions (stack -> C)
   */

  typedef int   function(lua_State *L, int idx) pflua_stackaccess;
  pflua_stackaccess lua_isnumber;
  pflua_stackaccess lua_isstring;
  pflua_stackaccess lua_iscfunction;
  pflua_stackaccess lua_isuserdata;
  pflua_stackaccess lua_type;
  char *function(lua_State *L, int tp)  lua_typename;

  typedef int function(lua_State *L, int idx1, int idx2) pflua_compare;
  pflua_compare lua_equal;
  pflua_compare lua_rawequal;
  pflua_compare lua_lessthan;

  lua_Number  function(lua_State *L, int idx) lua_tonumber;
  lua_Integer function(lua_State *L, int idx) lua_tointeger;
  int function(lua_State *L, int idx) lua_toboolean;
  char* function(lua_State *L, int idx, size_t *len) lua_tolstring;
  size_t function(lua_State *L, int idx) lua_objlen;
  lua_CFunction function(lua_State *L, int idx) lua_tocfunction;
  void *function(lua_State *L, int idx) lua_touserdata;
  lua_State *function(lua_State *L, int idx) lua_tothread;
  void *function(lua_State *L, int idx) lua_topointer;

  /*
   ** push functions (C -> stack)
   */
  void  function(lua_State *L) lua_pushnil;
  void  function(lua_State *L, lua_Number n) lua_pushnumber;
  void  function(lua_State *L, lua_Integer n) lua_pushinteger;
  void  function(lua_State *L,  char *s, size_t l) lua_pushlstring;
  void  function(lua_State *L,  char *s) lua_pushstring;
  char *function(lua_State *L,  char *fmt, va_list argp) lua_pushvfstring;
  char *function(lua_State *L,  char *fmt, ...) lua_pushfstring;
  void  function(lua_State *L, lua_CFunction fn, int n) lua_pushcclosure;
  void  function(lua_State *L, int b) lua_pushboolean;
  void  function(lua_State *L, void *p) lua_pushlightuserdata;
  int   function(lua_State *L) lua_pushthread;

  /*
   ** get functions (Lua -> stack)
   */
  void  function(lua_State *L, int idx) lua_gettable;
  void  function(lua_State *L, int idx, char *k) lua_getfield;
  void  function(lua_State *L, int idx) lua_rawget;
  void  function(lua_State *L, int idx, int n) lua_rawgeti;
  void  function(lua_State *L, int narr, int nrec) lua_createtable;
  void* function(lua_State *L, size_t sz) lua_newuserdata;
  int   function(lua_State *L, int objindex) lua_getmetatable;
  void  function(lua_State *L, int idx) lua_getfenv;

  /*
   ** set functions (stack -> Lua)
   */
  void  function(lua_State *L, int idx) lua_settable;
  void  function(lua_State *L, int idx, char *k) lua_setfield;
  void  function(lua_State *L, int idx) lua_rawset;
  void  function(lua_State *L, int idx, int n) lua_rawseti;
  int   function(lua_State *L, int objindex) lua_setmetatable;
  int   function(lua_State *L, int idx) lua_setfenv;

  /*
   ** `load' and `call' functions (load and run Lua code)
   */
  void function(lua_State *L, int nargs, int nresults) lua_call;
  int  function(lua_State *L, int nargs, int nresults, int errfunc) lua_pcall;
  int  function(lua_State *L, lua_CFunction func, void *ud) lua_cpcall;
  int  function(lua_State *L, lua_Reader reader, void *dt, char *chunkname) lua_load;
  int  function(lua_State *L, lua_Writer writer, void *data) lua_dump;

  /*
   ** coroutine functions
   */
  int  function(lua_State *L, int nresults) lua_yield;
  int  function(lua_State *L, int narg) lua_resume;
  int  function(lua_State *L) lua_status;

  /*
   ** garbage-collection function and options
   */

  int function(lua_State *L, int what, int data) lua_gc;

  /*
   ** miscellaneous functions
   */

  int  function(lua_State *L) lua_error;
  int  function(lua_State *L, int idx) lua_next;
  void function(lua_State *L, int n) lua_concat;

  lua_Alloc function(lua_State *L, void **ud) lua_getallocf;
  void      function(lua_State *L, lua_Alloc f, void *ud) lua_setallocf;

  /* Functions to be called by the debugger in specific events */

  int  function(lua_State *L, int level, lua_Debug *ar) lua_getstack;
  int  function(lua_State *L,  char *what, lua_Debug *ar) lua_getinfo;
  char * function(lua_State *L,  lua_Debug *ar, int n) lua_getlocal;
  char * function(lua_State *L,  lua_Debug *ar, int n) lua_setlocal;
  char * function(lua_State *L, int funcindex, int n) lua_getupvalue;
  char * function(lua_State *L, int funcindex, int n) lua_setupvalue;

  int  function(lua_State *L, lua_Hook func, int mask, int count) lua_sethook;
  lua_Hook  function(lua_State *L) lua_gethook;
  int  function(lua_State *L) lua_gethookmask;
  int  function(lua_State *L) lua_gethookcount;
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

