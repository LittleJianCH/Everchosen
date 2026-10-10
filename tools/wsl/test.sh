#!/usr/bin/env bash
# Gameplay rules and adapters, executed under Lua 5.1.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
source "$script_dir/activate.sh"
stage=$(mktemp -d /tmp/everchosen-rules.XXXXXXXX)
trap 'rm -f -- "$stage/"{rules,inheritance,subjugation,daemon}_spec.lua; rmdir -- "$stage"' EXIT
lua5.1 -e 'assert(_VERSION == "Lua 5.1")'
target=${1:-all}
case "$target" in
    all|archaon-everchosen|tamurkhan-chieftains) ;;
    *) printf 'Unknown gameplay test target: %s\n' "$target" >&2; exit 2 ;;
esac
if [[ "$target" != archaon-everchosen ]]; then
    fennel --add-fennel-path "$root/mods/tamurkhan-chieftains/lib/?.fnl" \
        --globals describe,it --compile \
        "$root/tests/tamurkhan-chieftains/rules_spec.fnl" > "$stage/rules_spec.lua"
    luac5.1 -p "$stage/rules_spec.lua"
    (cd "$stage" && busted rules_spec.lua)
fi
if [[ "$target" != tamurkhan-chieftains ]]; then
    export EVERCHOSEN_ROOT="$root"
    export EVERCHOSEN_VANILLA_DB="${EVERCHOSEN_VANILLA_DB:-$root/.local/vanilla}"
    for spec in inheritance subjugation daemon; do
        fennel --globals describe,it --compile \
            "$root/tests/archaon-everchosen/${spec}_spec.fnl" > "$stage/${spec}_spec.lua"
        luac5.1 -p "$stage/${spec}_spec.lua"
        busted "$stage/${spec}_spec.lua"
    done
fi
