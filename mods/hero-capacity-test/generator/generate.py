"""Expose ordinary native heroes at Archaon's fortresses for UI testing."""
import sys
from itertools import chain
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path[:0] = [str(ROOT / "tools"),
                str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import (read_authored, read_table, run_generator,
                       write_localisation, write_table)
import hero_appearance
import hero_capacity
from roster_permissions import campaign_units

HOST = "wh_main_chs_chaos"
BUNDLE = "everchosen_hero_capacity_test"
SCOPE = "faction_to_faction_own_unseen"
FRAGMENT = "everchosen_hero_capacity_test_generated"
MAIN_CHAIN = "wh3_dlc20_settlement_woc_dark_fortress"
RECRUIT_SCOPE = "province_to_province_own_unseen"
HOST_CONTEXT = BUNDLE + "_host"
CAP_EFFECTS = hero_capacity.CAP_EFFECTS
TABLES = sorted(set(hero_appearance.TABLES) | set(hero_capacity.TABLES) | {
    "effects", "effect_bonus_value_agent_junction", "effect_bundles",
    "effect_bundles_to_effects_junctions", "campaign_effect_scopes",
    "effect_bonus_value_agent_subtype_junctions", "building_chains",
    "building_levels", "building_upgrades_junction", "building_effects_junction",
    "building_effect_context_expressions", "groupings_military",
    "units_to_groupings_military_permissions",
    "units_to_exclusive_faction_permissions",
})
NATIVE_INPUTS = {"db.pack": [f"db/{name}_tables" for name in TABLES],
                 **hero_appearance.NATIVE_INPUTS}


def rows(native, families):
    """Give each family one opening slot, independent of other families."""
    scope = native["campaign_effect_scopes"].one(key=SCOPE)
    if (scope["source"], scope["target"]) != ("faction", "faction"):
        raise ValueError("Hero-capacity test requires a faction-wide scope")
    for record in families.values():
        yield "effect_bundles_to_effects_junctions", {
            "effect_bundle_key": BUNDLE,
            "effect_key": record["source_effect"],
            "effect_scope": SCOPE, "value": "1.0000",
            "advancement_stage": "start_turn_completed",
        }


def fortress_levels(native):
    """Include each current nonruined tier of the native Dark Fortress main."""
    native["building_chains"].one(key=MAIN_CHAIN)
    levels = sorted((row for row in native["building_levels"].where(
        chain=MAIN_CHAIN) if int(row["level"]) > 0),
        key=lambda row: int(row["level"]))
    if not levels or [int(row["level"]) for row in levels] != list(
            range(1, len(levels) + 1)):
        raise ValueError("Native Dark Fortress tiers must start at tier one")
    for previous, following in zip(levels, levels[1:]):
        native["building_upgrades_junction"].one(**{
            "from": previous["level_name"], "to": following["level_name"]})
    return [row["level_name"] for row in levels]


def recruitment_rows(native, heroes, metadata):
    """Grant only host hero permissions and host-conditioned native recruitment."""
    group = native["factions"].one(key=HOST)["military_group"]
    native["groupings_military"].one(military_group=group)
    if {row["key"] for row in native["factions"].where(
            military_group=group)} != {HOST}:
        raise ValueError("Test hero unit permissions require Archaon's own group")
    available = campaign_units(native, HOST)
    permissions = native["faction_agent_permitted_subtypes"]
    units = set()
    for subtype, original in sorted(heroes.items()):
        expected = dict(original, faction=HOST)
        existing = permissions.where(faction=HOST, subtype=subtype)
        if existing and existing != [expected]:
            raise ValueError(f"Conflicting native host hero permission: {subtype}")
        if not existing:
            yield permissions.name, expected
        unit = native["agent_subtypes"].one(key=subtype)[
            "associated_unit_override"]
        if native["main_units"].one(unit=unit)["caste"] != "hero":
            raise ValueError(f"Missing native test hero base unit: {subtype}")
        if native["units_to_exclusive_faction_permissions"].where(
                key=unit, faction=HOST, allowed="false"):
            raise ValueError(f"Native host explicitly bans test hero: {subtype}")
        units.add(unit)
    for unit in sorted(units - available):
        yield "units_to_groupings_military_permissions", {
            "unit": unit, "military_group": group}

    scope = native["campaign_effect_scopes"].one(key=RECRUIT_SCOPE)
    if (scope["source"], scope["target"]) != ("province", "province"):
        raise ValueError("Hero recruitment requires a native provincial scope")
    bindings = native["effect_bonus_value_agent_subtype_junctions"]
    class_bindings = native["effect_bonus_value_agent_junction"]
    available_effects = {
        agent: {row["effect"] for row in bindings.rows
                if row["bonus_value_id"] == "availability"
                and row["subtype"] in heroes
                and heroes[row["subtype"]]["agent"] == agent}
        for agent in CAP_EFFECTS}
    levels = fortress_levels(native)
    by_family = {}
    for subtype in heroes:
        by_family.setdefault(metadata[subtype]["family"], []).append(subtype)
    for family, subtypes in sorted(by_family.items()):
        effect = BUNDLE + "_recruit_" + family
        sources = {
            subtype: sorted(bindings.where(
                bonus_value_id="availability", subtype=subtype),
                key=lambda row: row["effect"])
            for subtype in subtypes}
        if any(not values for values in sources.values()):
            raise ValueError(f"Missing native hero availability: {family}")
        agents = {heroes[subtype]["agent"] for subtype in subtypes}
        if len(agents) != 1:
            raise ValueError(f"Hero family spans multiple agent classes: {family}")
        agent, = agents
        family_effects = {row["effect"] for values in sources.values()
                          for row in values}
        templates = [row for row in class_bindings.where(
            bonus_value_id="availability", agent=agent)
            if row["effect"] in available_effects[agent]]
        if not templates:
            raise ValueError(f"Missing native class availability: {agent}")
        # Bind this family's exact lores while retaining the native class gate.
        template = min(templates, key=lambda row: (
            row["effect"] not in family_effects, row["effect"]))
        yield "effects", dict(native["effects"].one(effect=template["effect"]),
                              effect=effect)
        yield class_bindings.name, dict(template, effect=effect)
        for subtype in sorted(subtypes):
            yield bindings.name, dict(sources[subtype][0], effect=effect)
        # Native settlement recruitment already uses this scope and 1/1/0
        # values. The context keeps these shared main buildings host-only.
        for building in levels:
            yield "building_effects_junction", {
                "building": building, "effect": effect,
                "context_requirement": HOST_CONTEXT,
                "effect_scope": RECRUIT_SCOPE, "value": "1.0000",
                "value_damaged": "1.0000", "value_ruined": "0.0000",
            }


def recruitment_localisation(heroes, metadata):
    families = {metadata[subtype]["family"]: metadata[subtype]["name_key"]
                for subtype in heroes}
    for family, name in sorted(families.items()):
        yield {"key": "effects_description_" + BUNDLE + "_recruit_" + family,
               "text": "允许招募英雄：{{tr:" + name + "}}", "tooltip": "false"}


def generate(vanilla, output):
    native = {name: read_table(vanilla / "db", name) for name in TABLES}
    authored = read_authored(MOD / "assets/db", native)
    bundle, = [row for row in authored["effect_bundles"] if row["key"] == BUNDLE]
    if bundle["key"] != BUNDLE or bundle["bundle_target"] != "faction":
        raise ValueError("Hero capacity test bundle must target a faction")
    context, = authored["building_effect_context_expressions"]
    source = native["building_effect_context_expressions"].one(
        key="AislinnBuiltInColony")
    expected = dict(source, key=HOST_CONTEXT,
        expression=source["expression"].replace(
            '"wh3_dlc27_hef_aislinn"', f'"{HOST}"'),
        display_only_active_effects="true")
    if context != expected:
        raise ValueError("Test recruitment must be active only in host regions")
    # Check an actual native settlement availability row before applying its
    # provincial recruitment convention to the five fortress main tiers.
    native["building_effects_junction"].one(
        building="wh_main_nor_chaos_1",
        effect="wh_dlc08_effect_agent_enable_recruitment_wizard_norsca",
        effect_scope=RECRUIT_SCOPE, context_requirement="",
        value="1.0000", value_damaged="1.0000", value_ruined="0.0000")
    families = hero_capacity.families(native)
    heroes, metadata = hero_capacity.recruitable_heroes(native)
    generated = {}
    for name, row in chain(rows(native, families),
                           recruitment_rows(native, heroes, metadata)):
        generated.setdefault(name, []).append(row)
    for name, values in generated.items():
        write_table(output, native[name], values, FRAGMENT)
    appearances, _ = hero_appearance.supported_heroes(native)
    hero_appearance.write_assets(vanilla, output, native, appearances)
    hero_capacity.write_assets(native, output)
    write_localisation(output, recruitment_localisation(heroes, metadata),
                       FRAGMENT)
    print(f"Hero-capacity test: {len(families)} independent families +1 each")
    print(f"Test recruitment: {len(heroes)} subtypes at "
          + ", ".join(fortress_levels(native)))


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
