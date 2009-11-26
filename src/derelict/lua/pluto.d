module derelict.lua.pluto;

import derelict.lua.lua;
import derelict.util.loader;

extern (C) {
    int function(lua_State *L, lua_Writer writer, void *ud) pluto_persist;
    int function(lua_State *L, lua_Reader reader, void *ud) pluto_unpersist;
}

private void load(SharedLib lib)
{
  *cast(void**)&pluto_persist = Derelict_GetProc(lib, "pluto_persist");
  *cast(void**)&pluto_unpersist = Derelict_GetProc(lib, "pluto_unpersist");
}

GenericLoader DerelictLua_Pluto;
static this()
{
  DerelictLua_Pluto.setup(
      "pluto.dll",
      //NOTE for Linux: the pluto tar.gz doesn't do it right; be sure ldd
      //    reports that the .so is referencing the lua so, and also rename
      //    pluto.so to this
      "libpluto.so.0",
      "", // Mac
      &load
      );
}

