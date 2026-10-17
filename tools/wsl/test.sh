#!/usr/bin/env bash
# Run Python tests, build current sources, then check gameplay with Lua 5.1 Busted.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
source "$script_dir/activate.sh"
stage=$(mktemp -d /tmp/everchosen-rules.XXXXXXXX)
trap 'rm -rf -- "$stage"' EXIT
lua5.1 -e 'assert(_VERSION == "Lua 5.1")'
target=${1:-all}
case "$target" in
    all|archaon-everchosen|tamurkhan-chieftains|hero-capacity-test) ;;
    *) printf 'Unknown gameplay test target: %s\n' "$target" >&2; exit 2 ;;
esac
python3 -I -m unittest discover -s "$root/tests/tools" -p 'test_*.py'
python3 -I -m unittest discover -s "$root/tests/archaon-everchosen" -p 'test_*.py'
python3 -I -m unittest discover -s "$root/tests/tamurkhan-chieftains" -p 'test_*.py'
python3 -I -m unittest discover -s "$root/tests/daemon-portal-heroes" -p 'test_*.py'
if [[ "$target" == all || "$target" == tamurkhan-chieftains ]]; then
    fennel --add-fennel-path "$root/mods/tamurkhan-chieftains/lib/?.fnl" \
        --globals describe,it --compile \
        "$root/tests/tamurkhan-chieftains/rules_spec.fnl" > "$stage/rules_spec.lua"
    luac5.1 -p "$stage/rules_spec.lua"
    (cd "$stage" && busted rules_spec.lua)
fi
if [[ "$target" == all || "$target" == archaon-everchosen ]]; then
    export EVERCHOSEN_ROOT="$root"
    export EVERCHOSEN_VANILLA_DB="${EVERCHOSEN_VANILLA_DB:-$root/.local/vanilla}"
    bash "$script_dir/build.sh" archaon-everchosen
    for spec in inheritance subjugation daemon skill_transfer hordes river_of_blood hero_recruitment hero_recruitment_adapter hero_capacity; do
        fennel --add-fennel-path "$root/mods/archaon-everchosen/lib/?.fnl" \
            --globals describe,it --compile \
            "$root/tests/archaon-everchosen/${spec}_spec.fnl" > "$stage/${spec}_spec.lua"
        luac5.1 -p "$stage/${spec}_spec.lua"
        busted "$stage/${spec}_spec.lua"
    done
fi
if [[ "$target" == hero-capacity-test ]]; then
    export EVERCHOSEN_ROOT="$root"
    bash "$script_dir/build.sh" hero-capacity-test
    for spec in campaign; do
        fennel --add-fennel-path "$root/mods/hero-capacity-test/lib/?.fnl" \
            --globals describe,it --compile \
            "$root/tests/hero-capacity-test/${spec}_spec.fnl" > "$stage/${spec}_spec.lua"
        luac5.1 -p "$stage/${spec}_spec.lua"
        busted "$stage/${spec}_spec.lua"
    done
fi
