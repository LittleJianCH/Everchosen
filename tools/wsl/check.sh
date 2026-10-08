#!/usr/bin/env bash
# From PowerShell in the project: wsl -d Ubuntu -- bash tools/wsl/check.sh
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/activate.sh"
lua -v
luarocks --version
fennel --version
busted --version

# Compile and run on the Linux filesystem, outside the Mod source tree.
stage=$(mktemp -d /tmp/everchosen-toolchain.XXXXXXXX)
trap 'rm -f -- "$stage/expected" "$stage/actual" "$stage/smoke_spec.lua" "$stage/failure_spec.lua" "$stage/failure.log"; rmdir -- "$stage"' EXIT
awk 'NF && $1 !~ /^#/ {print $1 " " $2}' "$script_dir/rocks.lock" | LC_ALL=C sort > "$stage/expected"
luarocks --lua-version 5.1 --tree "$EVERCHOSEN_LUA_TREE" list --porcelain |
    awk '{print $1 " " $2}' | LC_ALL=C sort > "$stage/actual"
diff -u "$stage/expected" "$stage/actual"

fennel --globals describe,it --compile "$script_dir/smoke.fnl" > "$stage/smoke_spec.lua"
luac5.1 -p "$stage/smoke_spec.lua"
(cd "$stage" && busted smoke_spec.lua)

# Ensure that a failing test really fails the command, rather than being skipped.
printf 'describe("failure control", function() it("fails", function() assert.equals(1, 2) end) end)\n' > "$stage/failure_spec.lua"
if (cd "$stage" && busted failure_spec.lua) > "$stage/failure.log" 2>&1; then
    printf 'ERROR: Busted accepted a deliberately failing test.\n' >&2
    exit 1
fi
grep -q '1 failure' "$stage/failure.log"
printf 'PASS: locked dependencies, Fennel compilation, Lua 5.1 execution, and failure reporting.\n'
