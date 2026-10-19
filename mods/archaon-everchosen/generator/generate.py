"""Stage native-derived assets while preserving module validation boundaries."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(Path(__file__).resolve().parent),
                str(MOD.parents[1] / "tools")]
from db_tables import (lua_literal, read_authored, read_table, run_generator,
                       write_localisation, write_table)
import inheritance
import subjugation
import daemon_prince
import daemon_legion
import daemon_skills
import skill_slots
import roster_permissions
import regiments_of_renown
import beastmen_hordes
import beastmen_horde_ui
import beastmen_horde_heroes
import recruitment_ui
import vassal_military_buildings
import vassal_recruitment_discount
import hero_recruitment_ui
import hero_families
import hero_appearance
import hero_capacity
import beastmen_hero_economy
import beastmen_troop_economy

FRAGMENT = "everchosen_inheritance_data"
STATIC_DATA = "everchosen_core_data"
BASE_MODULES = (inheritance, roster_permissions, regiments_of_renown,
                beastmen_troop_economy,
                subjugation, daemon_prince,
                daemon_legion, beastmen_hordes, vassal_military_buildings,
                recruitment_ui)
MODULES = (*BASE_MODULES, beastmen_horde_heroes, daemon_skills,
           beastmen_horde_ui, vassal_recruitment_discount, hero_recruitment_ui,
           hero_families, hero_appearance, hero_capacity, beastmen_hero_economy)
TABLES = sorted({table for module in MODULES for table in module.TABLES})
NATIVE_INPUTS = {
    "db.pack": [f"db/{name}_tables" for name in TABLES],
    **hero_appearance.NATIVE_INPUTS,
    "ui3.pack": [*inheritance.UI_ADAPTATIONS, *daemon_prince.UI_ADAPTATIONS,
                 *hero_recruitment_ui.NATIVE_INPUTS,
                 "ui/templates/square_medium_text_button.twui.xml",
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
    data["vassal_military_buildings"] = vassal_military_buildings.script_data(native)
    data["regiments_of_renown"] = regiments_of_renown.script_data(native)
    data["hero_recruitment"] = {
        "subtypes": hero_families.script_data(native),
        "icons": hero_recruitment_ui.script_data(native),
        "page_size": hero_recruitment_ui.PAGE_SIZE}
    return data


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
    building_data = vassal_military_buildings.script_data(native)
    for table, row in vassal_recruitment_discount.rows(native, building_data):
        generated.setdefault(table, []).append(row)
    subjugation.validate(native, generated, authored)
    # Subjugation validates legendary-lord permissions before ordinary camp
    # heroes add their separate, native-derived recruitment permissions.
    for table, row in beastmen_horde_heroes.rows(native):
        generated.setdefault(table, []).append(row)
    for table, row in vassal_military_buildings.hero_rows(native):
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
    capacities = {}
    for table, row in hero_capacity.rows(native):
        capacities.setdefault(table, []).append(row)
    validation = {table: generated.get(table, []) + capacities.get(table, [])
                  for table in generated.keys() | capacities.keys()}
    inheritance.validate(native, validation, authored)
    daemon_legion.validate(native, generated, authored)
    beastmen_hordes.validate(native, validation, authored)
    beastmen_horde_heroes.validate(native, validation, authored)
    vassal_recruitment_discount.validate(native, generated, authored,
                                         building_data)
    for table, rows in generated.items():
        write_table(output, native[table], rows, FRAGMENT)
    heroes, _ = hero_appearance.supported_heroes(native)
    hero_appearance.write_assets(native_root, output, native, heroes)
    hero_capacity.write_assets(native, output)
    beastmen_hero_economy.write_assets(native, output)
    recruitment_ui.write_culture_override(native_root, output, native)
    write_localisation(output, beastmen_hordes.localisation(native),
                       "everchosen_horde_names")
    write_localisation(output, vassal_military_buildings.localisation(native),
                       "everchosen_vassal_buildings")
    ui_count = adapt_ui(native_root, output, native)
    ui_count += hero_recruitment_ui.write_ui(native_root, output)
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
