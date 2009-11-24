module derelict.lua.luaconf;

const int LUA_IDSIZE   = 60;   

/*
@@ LUA_INTEGER is the integral type used by lua_pushinteger/lua_tointeger.
** CHANGE that if ptrdiff_t is not adequate on your machine. (On most
** machines, ptrdiff_t gives a good choice between int or long.)
*/
alias int LUA_INTEGER;

/*
** {==================================================================
@@ LUA_NUMBER is the type of numbers in Lua.
** CHANGE the following definitions only if you want to build Lua
** with a number type different from double. You may also need to
** change lua_number2int & lua_number2integer.
** ===================================================================
*/

alias double LUA_NUMBER;

/*
@@ LUAL_BUFFERSIZE is the buffer size used by the lauxlib buffer system.
*/
const int BUFSIZ = 0x4000; // add (BUFSIZ)
alias BUFSIZ LUAL_BUFFERSIZE;	  


