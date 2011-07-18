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
  import derelict.lua.luatypes;
  import derelict.lua.luafuncs;
  import derelict.lua.luaconf;
  import derelict.lua.lualib;
  import derelict.lua.lauxlib;
}

import derelict.util.loader;
import derelict.util.sharedlib;

//==============================================================================
// Loader
//==============================================================================
// private SharedLib libLua;


private void load_lua(SharedLib lib)
{
  void * Derelict_GetProc(SharedLib lib, string name) {
    return lib.loadSymbol(name);
  }
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

  *cast(void**)&lua_gc = Derelict_GetProc(lib, "lua_gc");

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

class DerelictLuaLoader : SharedLibLoader {
    this() {
        super("lua5.1.dll", "liblua5.1.so.0", "TODO: add mac");
    }

    protected override void loadSymbols() {
        load_lua(lib());
    }
}

DerelictLuaLoader DerelictLua;
static this()
{
    DerelictLua = new DerelictLuaLoader;
}
static ~this()
{
    DerelictLua.unload();
}
