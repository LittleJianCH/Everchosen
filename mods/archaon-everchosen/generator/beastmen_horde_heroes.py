"""Native hero recruitment at Archaon's private Beastmen camp buildings.

Agent-type capacities remain shared with the host's other heroes of that type.
The camp unlocks recruitment and supplies capacity; native candidate generation,
costs, and the recruitment command are unchanged.
"""
from host import HOST
import beastmen_hordes as hordes

SOURCE_FACTION = "wh_dlc03_bst_beastmen"
HEROES = {
    "wizard": (
        "wh_dlc03_bst_bray_shaman_beasts",
        "wh_dlc03_bst_bray_shaman_death",
        "wh_dlc03_bst_bray_shaman_shadows",
        "wh_dlc03_bst_bray_shaman_wild",
    ),
    "champion": ("wh_dlc03_bst_gorebull",),
    "spy": ("wh2_dlc17_bst_wargor",),
}
# Agent type, native effect presentation/binding, and an actual native camp
# building whose capacity row supplies the scope and undamaged/damaged values.
CAPACITY_SOURCES = (
    ("wizard", "wh_dlc03_effect_agent_cap_increase_wizard_beastmen",
     "wh_main_horde_chaos_magic_2",
     "wh_main_effect_agent_cap_increase_wizard_chaos_sorcerer"),
    ("champion", "wh_dlc03_effect_agent_cap_increase_champion_beastmen",
     "wh_main_horde_chaos_warriors_2",
     "wh_main_effect_agent_cap_increase_champion_exalted_hero"),
    ("spy", "wh2_dlc17_bst_ritual_hero_capacity_wargor",
     "wh2_dlc13_horde_lizardmen_skink_chief_1",
     "wh2_main_effect_agent_cap_increase_lzd_skink_chief"),
)
TABLES = """agent_subtypes faction_agent_permitted_subtypes
    factions groupings_military main_units units_to_groupings_military_permissions
    units_to_exclusive_faction_permissions effects
    effect_bonus_value_agent_junction effect_bonus_value_agent_subtype_junctions
    building_effects_junction building_levels campaign_effect_scopes
""".split() + hordes.TABLES


def capacity_effect(agent):
    return hordes.PREFIX + "hero_capacity_" + agent


def hero_units(native):
    """Map the six ordinary native subtypes to their associated base units."""
    result = {}
    for subtypes in HEROES.values():
        for subtype in subtypes:
            record = native["agent_subtypes"].one(key=subtype)
            if any(record[key] != "true" for key in (
                    "auto_generate", "recruitable", "contributes_to_agent_cap")):
                raise ValueError(f"Native camp hero recruitment changed: {subtype}")
            unit = record["associated_unit_override"]
            if native["main_units"].one(unit=unit)["caste"] != "hero":
                raise ValueError(f"Camp hero has no native base unit: {subtype}")
            result[subtype] = unit
    return result


def host_group(native):
    group = native["factions"].one(key=HOST)["military_group"]
    native["groupings_military"].one(military_group=group)
    if {r["key"] for r in native["factions"].where(
            military_group=group)} != {HOST}:
        raise ValueError("Hero permissions require Archaon's private group")
    return group


def permission_rows(native):
    permissions = native["faction_agent_permitted_subtypes"]
    for agent, subtypes in HEROES.items():
        for subtype in subtypes:
            original = permissions.one(agent=agent, faction=SOURCE_FACTION,
                                       subtype=subtype)
            if original["mod_disabled"] != "false":
                raise ValueError(f"Native Beastmen hero permission disabled: {subtype}")
            existing = permissions.where(faction=HOST, subtype=subtype)
            expected = dict(original, faction=HOST)
            if existing and existing != [expected]:
                raise ValueError(f"Conflicting host hero permission: {subtype}")
            if not existing:
                yield permissions.name, expected
    group = host_group(native)
    military = native["units_to_groupings_military_permissions"]
    exclusive = native["units_to_exclusive_faction_permissions"]
    source_group = native["factions"].one(key=SOURCE_FACTION)["military_group"]
    for unit in sorted(set(hero_units(native).values())):
        military.one(unit=unit, military_group=source_group)
        if exclusive.where(key=unit, faction=HOST, allowed="false"):
            raise ValueError(f"Native host ban conflicts with camp hero: {unit}")
        if not military.where(unit=unit, military_group=group):
            yield military.name, {"unit": unit, "military_group": group}


def recruitment_buildings(native):
    """One (building, agent type) per native camp recruitment unlock.

The four magic lores share one wizard capacity. Hidden upgrade effects still
grant availability and must retain that capacity when their building upgrades.
"""
    _, _, levels = hordes.graph(native)
    types = {subtype: agent for agent, subtypes in HEROES.items()
             for subtype in subtypes}
    availability = {}
    for row in native["effect_bonus_value_agent_subtype_junctions"].rows:
        if row["bonus_value_id"] == "availability" and row["subtype"] in types:
            availability.setdefault(row["effect"], set()).add(types[row["subtype"]])
    result = set()
    for row in native["building_effects_junction"].rows:
        if row["building"] in levels and row["effect"] in availability:
            if (row["effect_scope"] != "force_to_force_own"
                    or row["context_requirement"] or float(row["value"]) != 1):
                raise ValueError("Native camp hero availability requires review")
            result.update((row["building"], agent)
                          for agent in availability[row["effect"]])
    if {agent for _, agent in result} != HEROES.keys():
        raise ValueError("Missing native camp hero recruitment chain")
    return result


def capacity_templates(native):
    result = {}
    for agent, _, building, effect in CAPACITY_SOURCES:
        template = native["building_effects_junction"].one(
            building=building, effect=effect)
        native["effect_bonus_value_agent_junction"].one(
            effect=effect, bonus_value_id="cap", agent=agent)
        native["campaign_effect_scopes"].one(key=template["effect_scope"])
        if (template["context_requirement"]
                or template["effect_scope"] != "faction_to_faction_own_unseen"
                or [float(template[k]) for k in (
                    "value", "value_damaged", "value_ruined")] != [1, 1, 0]):
            raise ValueError(f"Native horde hero-capacity rule changed: {building}")
        result[agent] = template
    return result


def rows(native):
    yield from permission_rows(native)
    for agent, effect, _, _ in CAPACITY_SOURCES:
        yield "effects", dict(native["effects"].one(effect=effect),
                              effect=capacity_effect(agent))
        binding = native["effect_bonus_value_agent_junction"].one(
            effect=effect, bonus_value_id="cap", agent=agent)
        yield "effect_bonus_value_agent_junction", dict(
            binding, effect=capacity_effect(agent))
    templates = capacity_templates(native)
    for building, agent in sorted(recruitment_buildings(native)):
        yield "building_effects_junction", dict(
            templates[agent], building=hordes.PREFIX + building,
            effect=capacity_effect(agent))


def validate(native, generated, authored):
    """Check actual host permissions and private capacity references/scope."""
    def additions(table):
        return generated.get(table, []) + authored.get(table, [])

    units = hero_units(native)
    group = host_group(native)
    for agent, subtypes in HEROES.items():
        for subtype in subtypes:
            changed = [r for r in additions("faction_agent_permitted_subtypes")
                       if r["subtype"] == subtype]
            if any(r["faction"] != HOST or r["agent"] != agent
                   or r["mod_disabled"] != "false" for r in changed):
                raise ValueError("Camp hero permission escaped Archaon")
            rows = native["faction_agent_permitted_subtypes"].rows + changed
            if not any(r["subtype"] == subtype and r["faction"] == HOST
                       and r["agent"] == agent and r["mod_disabled"] == "false"
                       for r in rows):
                raise ValueError(f"Missing camp hero permission: {subtype}")
    for unit in units.values():
        changed = [r for r in additions("units_to_groupings_military_permissions")
                   if r["unit"] == unit]
        if any(r["military_group"] != group for r in changed):
            raise ValueError("Camp hero unit permission escaped Archaon")
        existing = native["units_to_groupings_military_permissions"].where(
            unit=unit, military_group=group)
        if not existing and not changed:
            raise ValueError(f"Missing camp hero base-unit permission: {unit}")
    if any(r["key"] in units for r in additions("agent_subtypes")):
        raise ValueError("Camp heroes must retain native costs and generation")
    if any(r["unit"] in units.values() for r in additions("main_units")):
        raise ValueError("Camp heroes must retain native unit attributes")
    effects = {capacity_effect(agent): agent for agent in HEROES}
    known_effects = native["effects"].column("effect") | {
        r["effect"] for r in additions("effects")}
    levels = native["building_levels"].column("level_name") | {
        r["level_name"] for r in additions("building_levels")}
    for effect, agent in effects.items():
        if effect not in known_effects:
            raise ValueError(f"Missing private hero-capacity effect: {effect}")
        bindings = [r for r in additions("effect_bonus_value_agent_junction")
                    if r["effect"] == effect]
        if bindings != [{"effect": effect, "bonus_value_id": "cap", "agent": agent}]:
            raise ValueError(f"Incorrect shared hero-capacity binding: {effect}")
    actual = [r for r in additions("building_effects_junction")
              if r["effect"] in effects]
    expected = {(hordes.PREFIX + building, capacity_effect(agent))
                for building, agent in recruitment_buildings(native)}
    if (len(actual) != len(expected)
            or {(r["building"], r["effect"]) for r in actual} != expected):
        raise ValueError("Camp capacity must follow native hero unlocks and upgrades")
    for row in actual:
        if (row["building"] not in levels
                or row["effect_scope"] != "faction_to_faction_own_unseen"
                or row["context_requirement"]
                or [float(row[k]) for k in (
                    "value", "value_damaged", "value_ruined")] != [1, 1, 0]):
            raise ValueError("Camp hero capacity changed native scope or amount")
