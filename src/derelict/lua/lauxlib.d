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

module derelict.lua.lauxlib;

import derelict.util.loader;
import derelict.lua.luatypes;
import derelict.lua.luaconf;
import derelict.lua.luafuncs;

//==============================================================================
// Types
//==============================================================================

struct luaL_reg {
  char *name;
  lua_CFunction func;
}

struct luaL_Buffer {
  char *p;
  int lvl;
  lua_State *L;
  char buffer[LUAL_BUFFERSIZE];
};

//==============================================================================
// Functions
//==============================================================================
extern (C)
{
  void function(lua_State *L,  char *libname, luaL_reg *l, int nup) luaL_openlib;
  void function(lua_State *L,  char *libname, luaL_reg *l) luaL_register;
  int  function(lua_State *L, int obj, char *e) luaL_getmetafield;
  int  function(lua_State *L, int obj, char *e) luaL_callmeta;
  int  function(lua_State *L, int narg, char *tname) luaL_typerror;
  int  function(lua_State *L, int numarg,  char *extramsg) luaL_argerror;
  char *function(lua_State *L, int numArg, size_t *l) luaL_checklstring;
  char *function(lua_State *L, int numArg, char *def, size_t *l) luaL_optlstring;
  lua_Number  function(lua_State *L, int numArg) luaL_checknumber;
  lua_Number  function(lua_State *L, int nArg, lua_Number def) luaL_optnumber;

  lua_Integer  function(lua_State *L, int numArg) luaL_checkinteger;
  lua_Integer  function(lua_State *L, int nArg, lua_Integer def) luaL_optinteger;

  void  function(lua_State *L, int sz,  char *msg) luaL_checkstack;
  void  function(lua_State *L, int narg, int t) luaL_checktype;
  void  function(lua_State *L, int narg) luaL_checkany;

  int  function(lua_State *L,  char *tname) luaL_newmetatable;
  void *function(lua_State *L, int ud,  char *tname) luaL_checkudata;

  void function(lua_State *L, int lvl) luaL_where;
  int  function(lua_State *L,  char *fmt, ...) luaL_error;

  int function(lua_State *L, int narg, char *def, char **lst) luaL_checkoption;

  int  function(lua_State *L, int t) luaL_ref;
  void function(lua_State *L, int t, int _ref) luaL_unref;

  int function(lua_State *L,  char *filename) luaL_loadfile;
  int function(lua_State *L,  char *buff, size_t sz, char *name) luaL_loadbuffer;

  int function(lua_State *L, char *s) luaL_loadstring;

  char* function(lua_State *L, char *s, char *p, char *r) luaL_gsub;
  char* function(lua_State *L, int idx, char *fname, int szhint) luaL_findtable;


  void  function(lua_State *L, luaL_Buffer *B) luaL_buffinit;
  char *function(luaL_Buffer *B) luaL_prepbuffer;
  void  function(luaL_Buffer *B,  char *s, size_t l) luaL_addlstring;
  void  function(luaL_Buffer *B,  char *s) luaL_addstring;
  void  function(luaL_Buffer *B) luaL_addvalue;
  void  function(luaL_Buffer *B) luaL_pushresult;
}

/*
 ** Compatibility macros and functions
 */
alias luaL_checklstring    luaL_check_lstr;
alias luaL_optlstring      luaL_opt_lstr;
alias luaL_checknumber     luaL_check_number;
alias luaL_optnumber       luaL_opt_number;
alias luaL_argcheck        luaL_arg_check;
alias luaL_checkstring     luaL_check_string;
alias luaL_optstring       luaL_opt_string;
alias luaL_checkint        luaL_check_int;
alias luaL_checklong       luaL_check_long;
alias luaL_optint          luaL_opt_int;
alias luaL_optlong         luaL_opt_long;
/* add: macros
 ** ===============================================================
 ** some useful macros
 ** ===============================================================
 */

//#define luaL_argcheck(L, cond,numarg,extramsg) if (!(cond)) \
//                                              luaL_argerror(L, numarg,extramsg)

void luaL_argcheck(lua_State *L, bool cond, int numarg, char* extramsg)
{
  if (!(cond))
    luaL_argerror(L, numarg, extramsg);
}

//#define luaL_checkstring(L,n)	(luaL_checklstring(L, (n), NULL))
char *luaL_checkstring(lua_State *L, int n)
{
  return luaL_checklstring(L, n, null);
}

//#define luaL_optstring(L,n,d)	(luaL_optlstring(L, (n), (d), NULL))

char* luaL_optstring(lua_State *L, int n, char *d)
{
  return luaL_optlstring(L, n, d, null);
}

//#define luaL_checkint(L,n)	((int)luaL_checknumber(L, n))
int luaL_checkint(lua_State *L, int n)
{
  return cast(int)luaL_checknumber(L, n);
}

//#define luaL_checklong(L,n)	((long)luaL_checknumber(L, n))
long luaL_checklong(lua_State *L, int n)
{
  return cast(long)luaL_checknumber(L, n);
}

//#define luaL_optint(L,n,d)	((int)luaL_optnumber(L, n,(lua_Number)(d)))
int luaL_optint(lua_State *L, int n, lua_Number d)
{
  return cast(int)luaL_optnumber(L, n, d);
}

//#define luaL_optlong(L,n,d)	((long)luaL_optnumber(L, n,(lua_Number)(d)))
long luaL_optlong(lua_State *L, int n, lua_Number d)
{
  return cast(long)luaL_optnumber(L, n, d);
}

//#define luaL_typename(L,i)      lua_typename(L, lua_type(L,(i)))
char* luaL_typename(lua_State *L, int i)
{
  return lua_typename(L, lua_type(L, i));
}

/*
#define luaL_putchar(B,c) \
((void)((B)->p < ((B)->buffer+LUAL_BUFFERSIZE) || luaL_prepbuffer(B)), \
(*(B)->p++ = (char)(c)))
 */
// someone posted online this is the translation of the macro
// i'm not so sure, but it might be right

void luaL_putchar(luaL_Buffer *B, char c)
{
  if (B.p >= &B.buffer[LUAL_BUFFERSIZE-1]) luaL_prepbuffer(B);
  B.p += c;
}

//#define luaL_addsize(B,n)	((B)->p += (n))
void luaL_addsize(luaL_Buffer *B, int n)
{
  B.p += n;
}

