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
import derelict.lua.lua;
import derelict.lua.luaconf;

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
  typedef void function(lua_State *L,  char *libname, luaL_reg *l, int nup) pfluaL_openlib;
  typedef void function(lua_State *L,  char *libname, luaL_reg *l) pfluaL_register;
  typedef int  function(lua_State *L, int obj, char *e) pfluaL_getmetafield;
  typedef int  function(lua_State *L, int obj, char *e) pfluaL_callmeta;
  typedef int  function(lua_State *L, int narg, char *tname) pfluaL_typerror;
  typedef int  function(lua_State *L, int numarg,  char *extramsg) pfluaL_argerror;
  typedef char *function(lua_State *L, int numArg, size_t *l) pfluaL_checklstring;
  typedef char *function(lua_State *L, int numArg, char *def, size_t *l) pfluaL_optlstring;
  typedef lua_Number  function(lua_State *L, int numArg) pfluaL_checknumber;
  typedef lua_Number  function(lua_State *L, int nArg, lua_Number def) pfluaL_optnumber;

  typedef lua_Integer  function(lua_State *L, int numArg) pfluaL_checkinteger;
  typedef lua_Integer  function(lua_State *L, int nArg, lua_Integer def) pfluaL_optinteger;

  typedef void  function(lua_State *L, int sz,  char *msg) pfluaL_checkstack;
  typedef void  function(lua_State *L, int narg, int t) pfluaL_checktype;
  typedef void  function(lua_State *L, int narg) pfluaL_checkany;

  typedef int  function(lua_State *L,  char *tname) pfluaL_newmetatable;
  typedef void *function(lua_State *L, int ud,  char *tname) pfluaL_checkudata;

  typedef void function(lua_State *L, int lvl) pfluaL_where;
  typedef int  function(lua_State *L,  char *fmt, ...) pfluaL_error;

  typedef int function(lua_State *L, int narg, char *def, char **lst)
    pfluaL_checkoption;

  typedef  int  function(lua_State *L, int t) pfluaL_ref;
  typedef  void function(lua_State *L, int t, int _ref) pfluaL_unref;

  typedef int function(lua_State *L,  char *filename) pfluaL_loadfile;
  typedef int function(lua_State *L,  char *buff, size_t sz, char *name) pfluaL_loadbuffer;

  typedef int function(lua_State *L, char *s) pfluaL_loadstring;

  typedef char* function(lua_State *L, char *s, char *p, char *r) pfluaL_gsub;
  typedef char* function(lua_State *L, int idx, char *fname, int szhint) pfluaL_findtable;


  pfluaL_openlib luaL_openlib;
  pfluaL_getmetafield luaL_getmetafield;
  pfluaL_callmeta luaL_callmeta;
  pfluaL_typerror luaL_typerror;
  pfluaL_argerror luaL_argerror;
  pfluaL_checklstring luaL_checklstring;
  pfluaL_optlstring luaL_optlstring;
  pfluaL_checknumber luaL_checknumber;
  pfluaL_optnumber luaL_optnumber;
  pfluaL_checkinteger luaL_checkinteger;
  pfluaL_optinteger luaL_optinteger;
  pfluaL_checkstack luaL_checkstack;
  pfluaL_checktype luaL_checktype;
  pfluaL_checkany luaL_checkany;

  pfluaL_newmetatable luaL_newmetatable;
  pfluaL_checkudata luaL_checkudata;
  pfluaL_where luaL_where;
  pfluaL_error luaL_error;
  pfluaL_checkoption luaL_checkoption;
  pfluaL_ref luaL_ref;
  pfluaL_unref luaL_unref;
  pfluaL_loadfile luaL_loadfile;
  pfluaL_loadbuffer luaL_loadbuffer;
  pfluaL_loadstring luaL_loadstring;
  pfluaL_gsub luaL_gsub;
  pfluaL_findtable luaL_findtable;

  typedef void  function(lua_State *L, luaL_Buffer *B) pfluaL_buffinit;
  typedef char *function(luaL_Buffer *B) pfluaL_prepbuffer;
  typedef void  function(luaL_Buffer *B,  char *s, size_t l) pfluaL_addlstring;
  typedef void  function(luaL_Buffer *B,  char *s) pfluaL_addstring;
  typedef void  function(luaL_Buffer *B) pfluaL_addvalue;
  typedef void  function(luaL_Buffer *B) pfluaL_pushresult;

  pfluaL_buffinit luaL_buffinit ;
  pfluaL_prepbuffer luaL_prepbuffer ;
  pfluaL_addlstring luaL_addlstring ;
  pfluaL_addstring luaL_addstring;
  pfluaL_addvalue luaL_addvalue;
  pfluaL_pushresult luaL_pushresult ;
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

