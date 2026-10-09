#!/usr/bin/env bash
# Compile source and stage pack contents; this does not create or install a .pack.
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
source "$script_dir/activate.sh"
cd -- "$root"
target=${1:-all}
if (($# > 1)); then
    printf 'Usage: bash tools/wsl/build.sh [all|archaon-everchosen|tamurkhan-chieftains|chaos-equipment]\n' >&2
    exit 2
fi
case "$target" in
    all) targets=(archaon-everchosen tamurkhan-chieftains chaos-equipment) ;;
    archaon-everchosen|tamurkhan-chieftains|chaos-equipment) targets=("$target") ;;
    *) printf 'Unknown mod: %s\n' "$target" >&2; exit 2 ;;
esac
command -v fennel >/dev/null
command -v luac5.1 >/dev/null
lua5.1 -e 'assert(_VERSION == "Lua 5.1")'
mkdir -p -- "$root/build"
stage=''
trap '[[ -z "$stage" ]] || rm -rf -- "$stage"' EXIT
for mod in "${targets[@]}"; do
    source_dir="$root/mods/$mod"
    stage=$(mktemp -d "$root/build/.$mod.XXXXXXXX")
    # Asset paths are relative to the pack root. Ignore directory placeholders.
    while IFS= read -r -d '' asset; do
        relative=${asset#"$source_dir/assets/"}
        mkdir -p -- "$stage/$(dirname -- "$relative")"
        cp -- "$asset" "$stage/$relative"
    done < <(find "$source_dir/assets" -type f ! -name .gitkeep -print0)
    if [[ -f "$source_dir/generator/generate.py" ]]; then
        python3 "$source_dir/generator/generate.py" --vanilla "${EVERCHOSEN_VANILLA_DB:-$root/.local/vanilla}" --output "$stage"
    fi
    count=0
    while IFS= read -r -d '' source; do
        relative=${source#"$source_dir/src/"}
        destination="$stage/${relative%.fnl}.lua"
        if [[ -e "$destination" ]]; then
            printf 'Asset conflicts with compiled source: %s\n' "$relative" >&2
            exit 1
        fi
        mkdir -p -- "$(dirname -- "$destination")"
        fennel --add-fennel-path "$source_dir/lib/?.fnl" --globals cm,core,out,common,nurgle_plagues,find_uicomponent --compile "$source" > "$destination"
        count=$((count + 1))
    done < <(find "$source_dir/src" -type f -name '*.fnl' -print0)
    # Check all Lua, including any deliberately authored Lua assets.
    while IFS= read -r -d '' compiled; do
        luac5.1 -p "$compiled"
    done < <(find "$stage" -type f -name '*.lua' -print0)
    output="$root/build/$mod"
    if [[ -L "$output" ]]; then
        printf 'Refusing to replace a symlink: %s\n' "$output" >&2
        exit 1
    fi
    rm -rf -- "$output"
    mv -- "$stage" "$output"
    stage=''
    printf '%s: %s Fennel file(s), Lua 5.1 syntax checked -> build/%s/\n' "$mod" "$count" "$mod"
done
