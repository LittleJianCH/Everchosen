"""Stage native-derived assets while preserving module validation boundaries."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(Path(__file__).resolve().parent),
                str(MOD.parents[1] / "tools")]
from db_tables import (read_authored, read_table, run_generator,
                       write_localisation, write_table)
import inheritance
import subjugation
import daemon_prince
import daemon_legion
import daemon_skills
import skill_slots
import roster_permissions
import beastmen_hordes
import beastmen_horde_ui
import beastmen_horde_heroes
import allied_outposts

FRAGMENT = "everchosen_inheritance_data"
STATIC_DATA = "everchosen_core_data"
BASE_MODULES = (inheritance, roster_permissions, subjugation, daemon_prince,
                daemon_legion, beastmen_hordes, allied_outposts)
MODULES = (*BASE_MODULES, beastmen_horde_heroes, daemon_skills,
           beastmen_horde_ui)
TABLES = sorted({table for module in MODULES for table in module.TABLES})
NATIVE_INPUTS = {
    "db.pack": [f"db/{name}_tables" for name in TABLES],
    "ui3.pack": [*inheritance.UI_ADAPTATIONS, *daemon_prince.UI_ADAPTATIONS,
                 "ui/templates/square_medium_text_button.twui.xml",
                 *allied_outposts.NATIVE_INPUTS,
                 *beastmen_horde_ui.NATIVE_INPUTS],
    # Loaded by the adapter regressions, not by this generator.
    "data_script.pack": ["script/campaign/wh3_campaign_nurgle_plagues.lua",
                         "script/campaign/wh3_campaign_great_game.lua",
                         "script/campaign/wh2_dlc17_taurox_rampage.lua",
                         "script/campaign/wh3_dlc29_archaon_subjugation.lua"],
}


def generated_rows(native):
    """Rows by table, without duplicates; write_table validates their layout."""
    result = {}
    for module in BASE_MODULES:
        for table, row in module.rows(native):
            rows = result.setdefault(table, [])
            if row not in rows:
                rows.append(row)
    return result


def script_data(native):
    data = inheritance.script_data(native)
    data["subjugation"] = subjugation.script_data(native)
    data["subjugation"]["skill_slots"] = {
        **subjugation.skill_mapping(native),
        daemon_skills.PRINCE: daemon_skills.skill_mapping(native)}
    data["daemon_prince"] = daemon_prince.script_data(native)
    data["hordes"] = beastmen_hordes.script_data(native)
    return data


def lua_literal(value):
    """Serialize strings, booleans, lists, and string-keyed dicts as Lua."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = (value.replace("\\", "\\\\").replace('"', '\\"')
                   .replace("\n", "\\n"))
        return f'"{escaped}"'
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua_literal(key)}]={lua_literal(item)}"
                              for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    raise TypeError(f"No Lua literal for {type(value).__name__}")


def adapt_ui(native_root, output, native):
    adaptations = {}
    for module in MODULES:
        for relative, adapt in getattr(module, "UI_ADAPTATIONS", {}).items():
            adaptations.setdefault(relative, []).append(adapt)
    for relative, adapters in adaptations.items():
        tree = ET.parse(native_root / relative)
        # Shared panels retain each module's changes in registration order.
        for adapt in adapters:
            adapt(tree, native_root, native)
        (output / relative).parent.mkdir(parents=True, exist_ok=True)
        tree.write(output / relative, encoding="utf-8", xml_declaration=True)
    return len(adaptations)


def generate(native_root, output):
    native = {name: read_table(native_root / "db", name) for name in TABLES}
    authored = read_authored(MOD / "assets/db", native)
    generated = generated_rows(native)
    subjugation.validate(native, generated, authored)
    # Subjugation validates legendary-lord permissions before ordinary camp
    # heroes add their separate, native-derived recruitment permissions.
    for table, row in beastmen_horde_heroes.rows(native):
        generated.setdefault(table, []).append(row)
    # Prince validation requires its isolated tree; global prerequisite
    # validation below must see both that tree and the transferred lords.
    prince_tree = {}
    for table, row in daemon_skills.rows(native):
        prince_tree.setdefault(table, []).append(row)
    daemon_skills.validate(native, prince_tree, authored)
    for table, rows in prince_tree.items():
        generated.setdefault(table, []).extend(rows)
    skill_slots.validate_trees(native, generated)
    inheritance.validate(native, generated, authored)
    daemon_legion.validate(native, generated, authored)
    beastmen_hordes.validate(native, generated, authored)
    beastmen_horde_heroes.validate(native, generated, authored)
    allied_outposts.validate(native, generated, authored)
    for table, rows in generated.items():
        write_table(output, native[table], rows, FRAGMENT)
    write_localisation(output, beastmen_hordes.localisation(native),
                       "everchosen_horde_names")
    ui_count = adapt_ui(native_root, output, native)
    beastmen_horde_ui.write_cco(output, native)
    path = output / f"script/campaign/mod/{STATIC_DATA}.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f'core:add_static_object("{STATIC_DATA}", '
                    + lua_literal(script_data(native)) + ")\n",
                    encoding="utf-8")
    print(f"Inheritance: {sum(map(len, generated.values()))} generated rows "
          f"across {len(generated)} tables; "
          f"{ui_count} native UI "
          "adaptations")


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
