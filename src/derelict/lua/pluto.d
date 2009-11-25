module derelict.lua.pluto;

import derelict.lua.lua;
import derelict.util.loader;

extern (C) {
    alias int function(lua_State *L, lua_Writer writer, void *ud) pfpluto_persist;
    alias int function(lua_State *L, lua_Reader reader, void *ud) pfpluto_unpersist;

    pfpluto_persist pluto_persist;
    pfpluto_unpersist pluto_unpersist;
}

private void load(SharedLib lib)
{
  bindFunc(pluto_persist)("pluto_persist", lib);
  bindFunc(pluto_unpersist)("pluto_unpersist", lib);
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

