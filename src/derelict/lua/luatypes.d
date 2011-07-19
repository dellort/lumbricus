module derelict.lua.luatypes;

import derelict.lua.luaconf;

//==============================================================================
// Types
//==============================================================================
// add: constants
enum string LUA_VERSION     = "Lua 5.1";
enum string LUA_RELEASE     = "Lua 5.1.1";
enum int    LUA_VERSION_NUM = 501;
enum string LUA_COPYRIGHT   = "Copyright (C) 1994-2006 Lua.org, PUC-Rio";
enum string LUA_AUTHORS 	   = "R. Ierusalimschy, L. H. de Figueiredo & W.  Celes";

enum string LUA_SIGNATURE   = "\033Lua";

/* option for multiple returns in `lua_pcall' and `lua_call' */
int LUA_MULTRET =	-1;

/*
** pseudo-indices
*/
enum int LUA_REGISTRYINDEX	= -10000;
enum int LUA_ENVIRONINDEX	= -10001;
enum int LUA_GLOBALSINDEX	= -10002;
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

  alias void function (lua_State *L, lua_Debug *ar) lua_Hook;
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
enum int LUA_MASKCALL  =	(1 << LUA_HOOKCALL);
enum int LUA_MASKRET   = (1 << LUA_HOOKRET);
enum int LUA_MASKLINE  =	(1 << LUA_HOOKLINE);
enum int LUA_MASKCOUNT =	(1 << LUA_HOOKCOUNT);

/* compatibility with ref system */

/* pre-defined references */
enum int LUA_NOREF	= (-2);
enum int LUA_REFNIL	= (-1);

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

