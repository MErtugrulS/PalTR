#include <iostream>

#include <lua.hpp>

int main(int argc, char** argv)
{
    if (argc != 2)
    {
        std::cerr << "usage: PalTRLuaTestRunner <test-script.lua>\n";
        return 2;
    }

    lua_State* state = luaL_newstate();
    if (state == nullptr)
    {
        std::cerr << "failed to create Lua state\n";
        return 2;
    }

    luaL_openlibs(state);
    const int result = luaL_dofile(state, argv[1]);
    if (result != LUA_OK)
    {
        const char* message = lua_tostring(state, -1);
        std::cerr << (message != nullptr ? message : "unknown Lua error") << '\n';
        lua_close(state);
        return 1;
    }

    lua_close(state);
    return 0;
}
