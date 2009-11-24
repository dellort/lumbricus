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

module derelict.lua.lualib; 

import derelict.util.loader;
import derelict.lua.lua;

//==============================================================================
// Types
//==============================================================================
const char[] LUA_FILEHANDLE  = "FILE*";

const char[] LUA_COLIBNAME	 = "coroutine";
const char[] LUA_TABLIBNAME  = "table";
const char[] LUA_IOLIBNAME   = "io";
const char[] LUA_OSLIBNAME   = "os";
const char[] LUA_STRLIBNAME  = "string";
const char[] LUA_MATHLIBNAME = "math";
const char[] LUA_DBLIBNAME   = "debug";
const char[] LUA_LOADLIBNAME = "package";

extern (C) 
{
  typedef int function(lua_State *L) pfOpen; 

  pfOpen luaopen_base; 
  pfOpen luaopen_table;
  pfOpen luaopen_io;
  pfOpen luaopen_os;
  pfOpen luaopen_string;
  pfOpen luaopen_math;
  pfOpen luaopen_debug;
  pfOpen luaopen_package;

  pfOpen luaL_openlibs;
}

// add: the following compatibility code
/* compatibility code */
alias luaopen_base      lua_baselibopen;
alias luaopen_table     lua_tablibopen;
alias luaopen_io        lua_iolibopen;
alias luaopen_string    lua_strlibopen;
alias luaopen_math      lua_mathlibopen;
alias luaopen_debug     lua_dblibopen;

