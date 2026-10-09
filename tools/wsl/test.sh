#!/usr/bin/env bash
# Pure gameplay rules, compiled and executed under Lua 5.1.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
source "$script_dir/activate.sh"
stage=$(mktemp -d /tmp/everchosen-rules.XXXXXXXX)
trap 'rm -f -- "$stage/rules_spec.lua"; rmdir -- "$stage"' EXIT
lua5.1 -e 'assert(_VERSION == "Lua 5.1")'
fennel --add-fennel-path "$root/mods/tamurkhan-chieftains/lib/?.fnl" \
    --globals describe,it --compile \
    "$root/tests/tamurkhan-chieftains/rules_spec.fnl" > "$stage/rules_spec.lua"
luac5.1 -p "$stage/rules_spec.lua"
(cd "$stage" && busted rules_spec.lua)
