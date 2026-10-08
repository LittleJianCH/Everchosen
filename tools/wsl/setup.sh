#!/usr/bin/env bash
# Run as the normal Ubuntu user: bash tools/wsl/setup.sh
set -euo pipefail
if [[ $(id -u) == 0 ]]; then
    printf 'Run this script as your normal Ubuntu user, not root.\n' >&2
    exit 1
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
packages=(lua5.1 liblua5.1-0-dev luarocks build-essential unzip ca-certificates)
missing=()
for package in "${packages[@]}"; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != 'install ok installed' ]]; then
        missing+=("$package")
    fi
done
if ((${#missing[@]})); then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi
source "$script_dir/activate.sh"
mkdir -p "$EVERCHOSEN_LUA_TREE/bin"
# Keep these commands on Lua 5.1 even if a newer system Lua is added later.
ln -sfn /usr/bin/lua5.1 "$EVERCHOSEN_LUA_TREE/bin/lua"
ln -sfn /usr/bin/luac5.1 "$EVERCHOSEN_LUA_TREE/bin/luac"
while read -r package version rest; do
    [[ -z "$package" || "$package" == \#* ]] && continue
    if ! luarocks --lua-version 5.1 --tree "$EVERCHOSEN_LUA_TREE" show "$package" "$version" >/dev/null 2>&1; then
        luarocks --lua-version 5.1 --tree "$EVERCHOSEN_LUA_TREE" install "$package" "$version" --deps-mode=one
    fi
done < "$script_dir/rocks.lock"
mkdir -p "$HOME/.config/everchosen"
cp -- "$script_dir/activate.sh" "$HOME/.config/everchosen/activate.sh"
startup_line='[ ! -f "$HOME/.config/everchosen/activate.sh" ] || . "$HOME/.config/everchosen/activate.sh"'
for startup in "$HOME/.profile" "$HOME/.bashrc"; do
    if ! grep -Fqx -- "$startup_line" "$startup" 2>/dev/null; then
        printf '\n# Everchosen Lua 5.1 development tools\n%s\n' "$startup_line" >> "$startup"
    fi
done
bash "$script_dir/check.sh"
