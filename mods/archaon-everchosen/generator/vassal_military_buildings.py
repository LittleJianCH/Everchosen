"""Native military recruitment buildings adapted for Archaon's fortresses."""

from db_tables import stable_id

PREFIX = "everchosen_vassal_"
AVAILABILITY = "everchosen_horde_availability"
FORTRESS_SET = "wh3_dlc20_secondary_addon_woc_dark_fortress"
CULTURE = "wh_main_chs_chaos"
HOST = "wh_main_chs_chaos"

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