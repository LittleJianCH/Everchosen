"""Native military recruitment buildings adapted for Archaon's fortresses."""

from db_tables import stable_id
from roster_permissions import campaign_units

PREFIX = "everchosen_vassal_"
AVAILABILITY = "everchosen_horde_availability"
FORTRESS_SET = "wh3_dlc20_secondary_addon_woc_dark_fortress"
CULTURE = "wh_main_chs_chaos"
HOST = "wh_main_chs_chaos"
SOURCE_FACTIONS = {
    "norsca": "wh_dlc08_nor_norsca",
    "chaos_dwarfs": "wh3_dlc23_chd_zhatan",
}

# Native recruitment chains shared by the ordinary racial settlements.
CHAINS = {
    "norsca": (
        "wh_main_NORSCA_military",
        "wh_main_NORSCA_stables",
        "wh_main_NORSCA_beasts",
        "wh_main_NORSCA_chaos",
        "wh_main_NORSCA_creatures",
        "wh_main_NORSCA_offerings",
    ),
    "chaos_dwarfs": (
        "wh3_dlc23_chd_military_hobgoblins",
        "wh3_dlc23_chd_military_chaos_dwarf_infantry",
        "wh3_dlc23_chd_military_war_machines",
        "wh3_dlc23_chd_military_beasts",
        "wh3_dlc23_chd_military_kdaai",
    ),
}

# These optional Norscan variants are faction-specific detours. The ordinary
# upgrade path reaches the same final tier without their free construction.
OMIT_LEVELS = {
    "wh3_dlc27_nor_military_3b",
    "wh_main_nor_chaos_2b",
    "wh_main_nor_creatures_2b",
    "wh3_dlc27_nor_offerings_2b",
}

# Chaos Dwarf armaments/labour costs are not available to Warriors of Chaos.
# Replace the native resource price with a gold price at comparable tiers.
GOLD_COSTS = {
    "wh3_dlc23_chd_military_war_machines": (3500, 6500, 9500),
    "wh3_dlc23_chd_military_beasts": (3000, 5500, 8500, 11500),
    "wh3_dlc23_chd_military_kdaai": (4000, 7000, 11000),
}

TABLES = """building_chains building_superchains building_instances
    building_levels building_culture_variants building_upgrades_junction
    building_units_allowed building_chain_availability_sets
    building_chain_set_items building_set_to_building_junctions
    settlement_type_to_building_chains_junctions
    building_effects_junction effect_bonus_value_agent_junction
    effect_bonus_value_agent_subtype_junctions faction_agent_permitted_subtypes
    agent_subtypes factions groupings_military main_units campaign_effect_scopes
    units_to_groupings_military_permissions units_to_exclusive_faction_permissions
""".split()


def selected(native):
    """Return source chains and levels after pruning native side branches."""
    chain_keys = set().union(*CHAINS.values())
    chains = {key: native["building_chains"].one(key=key)
              for key in chain_keys}
    levels = {row["level_name"]: row
              for row in native["building_levels"].rows
              if row["chain"] in chains and row["level_name"] not in OMIT_LEVELS}
    if not levels or OMIT_LEVELS - native["building_levels"].column("level_name"):
        raise ValueError("Norscan military building paths changed")
    for key in chain_keys:
        if not any(row["chain"] == key for row in levels.values()):
            raise ValueError(f"Missing military building levels: {key}")
    return chains, levels


def script_data(native):
    _, levels = selected(native)
    units = native["building_units_allowed"].rows
    return {
        race: {
            "levels": sorted(PREFIX + key for key, row in levels.items()
                             if row["chain"] in source_chains),
            "units": sorted({row["unit"] for row in units
                             if row["building"] in levels
                             and levels[row["building"]]["chain"]
                             in source_chains}),
        }
        for race, source_chains in CHAINS.items()
    }


def rows(native):
    """Clone only recruit paths and their display/placement relationships."""
    chains, levels = selected(native)
    placement = native["settlement_type_to_building_chains_junctions"].where(
        building_chain="wh3_dlc20_woc_dark_fortress_marauder")
    if (len(placement) != 1
            or placement[0]["settlement_type"] != "wh3_dlc29_chs_dark_fortress"
            or placement[0]["exclude"] != "false"):
        raise ValueError("Native Dark Fortress military placement changed")
    for key in sorted(chains):
        chain = chains[key]
        yield "building_superchains", {
            "key": PREFIX + key + "_super"}
        yield "building_chains", dict(
            chain, key=PREFIX + key,
            building_superchain=PREFIX + key + "_super")
        yield "building_chain_availability_sets", {
            "building_chain": PREFIX + key, "id": AVAILABILITY}
        yield "settlement_type_to_building_chains_junctions", dict(
            placement[0], building_chain=PREFIX + key)
        yield "building_chain_set_items", {
            "chain": PREFIX + key, "set": FORTRESS_SET,
            "super_chain": "", "remove": "false"}
        category = ("wh3_dlc20_set_warriors_military_recruitment"
                    if key in CHAINS["norsca"][:3]
                    or key in CHAINS["chaos_dwarfs"][:2]
                    else "wh3_dlc20_set_warriors_military_advanced")
        yield "building_set_to_building_junctions", {
            "building_chain": PREFIX + key, "building_level": "",
            "building_set": category, "exclude": "false"}

    instances = {row["building_instance_key"] for row in levels.values()}
    for key in sorted(instances - {""}):
        yield "building_instances", dict(
            native["building_instances"].one(key=key), key=PREFIX + key)

    for key, row in sorted(levels.items()):
        cost = row["create_cost"]
        if row["resource_cost"]:
            prices = GOLD_COSTS.get(row["chain"])
            if prices is None or int(row["level"]) >= len(prices):
                raise ValueError(f"Unpriced Chaos Dwarf building: {key}")
            cost = str(prices[int(row["level"])])
        yield "building_levels", dict(
            row, level_name=PREFIX + key,
            chain=PREFIX + row["chain"],
            building_instance_key=PREFIX + row["building_instance_key"],
            create_cost=cost, resource_cost="",
            resource_transaction_on_complete="")
        variant = native["building_culture_variants"].one(building=key)
        yield "building_culture_variants", dict(
            variant, building=PREFIX + key,
            culture=CULTURE, subculture="", faction=HOST)

    for row in native["building_upgrades_junction"].rows:
        if row["from"] in levels and row["to"] in levels:
            yield "building_upgrades_junction", {
                "from": PREFIX + row["from"],
                "to": PREFIX + row["to"]}

    used = native["building_units_allowed"].column("key")
    for row in native["building_units_allowed"].rows:
        if row["building"] not in levels:
            continue
        if (row["conditions"], row["faction"], row["enabled"]) != (
                "0", "", "false"):
            raise ValueError(f"Conditional native military recruit: {row}")
        yield "building_units_allowed", dict(
            row, key=stable_id(PREFIX + row["key"], used),
            building=PREFIX + row["building"])


def hero_rows(native):
    """Keep native hero unlocks/caps, supplying at least one at each unlock.

    Capacities use the native agent classes and remain shared with other heroes
    of those classes. Only the host receives character and base-unit access.
    """
    _, levels = selected(native)
    race_by_chain = {chain: race for race, chains in CHAINS.items()
                     for chain in chains}
    availability = {}
    for row in native["effect_bonus_value_agent_subtype_junctions"].rows:
        if row["bonus_value_id"] == "availability":
            availability.setdefault(row["effect"], set()).add(row["subtype"])
    caps = {row["effect"]: row["agent"]
            for row in native["effect_bonus_value_agent_junction"].rows
            if row["bonus_value_id"] == "cap"}
    permissions = native["faction_agent_permitted_subtypes"]
    heroes = {}
    unlocks = set()
    capacities = set()
    templates = {}
    for row in native["building_effects_junction"].rows:
        building, effect = row["building"], row["effect"]
        if building not in levels or not (
                effect in availability or effect in caps):
            continue
        if row["context_requirement"]:
            raise ValueError(f"Conditional military hero effect: {row}")
        native["campaign_effect_scopes"].one(key=row["effect_scope"])
        chain = levels[building]["chain"]
        for subtype in sorted(availability.get(effect, ())):
            source = SOURCE_FACTIONS[race_by_chain[chain]]
            permission = permissions.one(faction=source, subtype=subtype)
            record = native["agent_subtypes"].one(key=subtype)
            if (permission["mod_disabled"] != "false"
                    or any(record[key] != "true" for key in (
                        "auto_generate", "recruitable",
                        "contributes_to_agent_cap"))):
                raise ValueError(f"Not an ordinary recruitable hero: {subtype}")
            heroes[subtype] = permission
            unlocks.add((building, permission["agent"]))
        if effect in caps:
            agent = caps[effect]
            capacities.add((building, agent))
            templates.setdefault((chain, agent), row)
        yield "building_effects_junction", dict(row, building=PREFIX + building)

    for building, agent in sorted(unlocks - capacities):
        # The source factions can have base capacity that Archaon does not.
        # Give the first recruitment tier an explicit, building-owned point.
        template = templates[(levels[building]["chain"], agent)]
        yield "building_effects_junction", dict(
            template, building=PREFIX + building, value="1.0000",
            value_damaged="1.0000", value_ruined="0.0000")

    group = native["factions"].one(key=HOST)["military_group"]
    native["groupings_military"].one(military_group=group)
    if {row["key"] for row in native["factions"].where(
            military_group=group)} != {HOST}:
        raise ValueError("Military hero access requires Archaon's private group")
    available = campaign_units(native, HOST)
    units = set()
    for subtype, permission in sorted(heroes.items()):
        expected = dict(permission, faction=HOST)
        existing = permissions.where(faction=HOST, subtype=subtype)
        if existing and existing != [expected]:
            raise ValueError(f"Conflicting host hero permission: {subtype}")
        if not existing:
            yield "faction_agent_permitted_subtypes", expected
        unit = native["agent_subtypes"].one(key=subtype)[
            "associated_unit_override"]
        if (native["main_units"].one(unit=unit)["caste"] != "hero"
                or unit not in campaign_units(native, permission["faction"])):
            raise ValueError(f"Missing native hero unit permission: {subtype}")
        if native["units_to_exclusive_faction_permissions"].where(
                key=unit, faction=HOST, allowed="false"):
            raise ValueError(f"Host explicitly bans military hero: {unit}")
        units.add(unit)
    for unit in sorted(units - available):
        yield "units_to_groupings_military_permissions", {
            "unit": unit, "military_group": group}


def localisation(native):
    """Reuse the game's current translations for the cloned building cards."""
    chains, levels = selected(native)
    for key in sorted(levels):
        variant = native["building_culture_variants"].one(building=key)
        source = ("building_culture_variants_name_" + key
                  + variant["culture"] + variant["faction"])
        target = ("building_culture_variants_name_" + PREFIX + key
                  + CULTURE + HOST)
        yield {"key": target, "text": "{{tr:" + source + "}}",
               "tooltip": "false"}
    for key in sorted(chains):
        row = chains[key]
        fields = ["chain_tooltip"]
        if row["in_encyclopedia"] == "true":
            fields.extend(("encyclopedia_name", "encyclopedia_description"))
        for field in fields:
            source = "building_chains_" + field + "_" + key
            yield {"key": "building_chains_" + field + "_" + PREFIX + key,
                   "text": "{{tr:" + source + "}}", "tooltip": "false"}
