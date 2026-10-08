# Source this file from Bash to use the Everchosen Lua 5.1 toolchain.
export EVERCHOSEN_LUA_TREE="$HOME/.local/share/everchosen/lua51"
case ":$PATH:" in
    *":$EVERCHOSEN_LUA_TREE/bin:"*) ;;
    *) export PATH="$EVERCHOSEN_LUA_TREE/bin:$PATH" ;;
esac
export LUA_PATH="$EVERCHOSEN_LUA_TREE/share/lua/5.1/?.lua;$EVERCHOSEN_LUA_TREE/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$EVERCHOSEN_LUA_TREE/lib/lua/5.1/?.so;;"
