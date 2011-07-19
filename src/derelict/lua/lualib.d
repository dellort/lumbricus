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
import derelict.lua.luatypes;

//==============================================================================
// Types
//==============================================================================
enum string LUA_FILEHANDLE  = "FILE*";
enum string LUA_COLIBNAME	 = "coroutine";
enum string LUA_TABLIBNAME  = "table";
enum string LUA_IOLIBNAME   = "io";
enum string LUA_OSLIBNAME   = "os";
enum string LUA_STRLIBNAME  = "string";
enum string LUA_MATHLIBNAME = "math";
enum string LUA_DBLIBNAME   = "debug";
enum string LUA_LOADLIBNAME = "package";

extern (C)
{
  private alias lua_CFunction pfOpen;
}

__gshared {
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
