"""Archaon-only prices for ordinary Beastmen heroes and their native mounts."""
from db_tables import stable_id, write_table
from host import HOST

FRAGMENT = "everchosen_beastmen_hero_economy"
FACTION_SET = FRAGMENT
NATIVE_SET = "wh3_dlc29_nag_host_of_nagash"
TABLES = (
    "agent_subtypes", "main_units", "main_unit_faction_overrides",
    "units_custom_battle_mounts", "ancillaries", "factions", "faction_sets",
    "faction_set_items",
)

# Native subtype identity, campaign recruitment price, per-turn upkeep.
# Mounted forms use the same family price and upkeep.
HERO_COSTS = {
    "wh2_dlc17_bst_wargor": (1000, 250),
    "wh_dlc03_bst_gorebull": (1500, 300),
    **{"wh_dlc03_bst_bray_shaman_" + lore: (1250, 250)
       for lore in ("beasts", "death", "shadows", "wild")},
}


def unit_costs(native):
    """Follow each native base unit to mounted units and campaign ancillaries."""
    units = native["main_units"]
    mounts = native["units_custom_battle_mounts"]
    campaign_mounts = {
        row["provided_bodyguard_unit"]
        for row in native["ancillaries"].where(category="mount")}
    result = {}
    for subtype, cost in HERO_COSTS.items():
        base = native["agent_subtypes"].one(key=subtype)[
            "associated_unit_override"]
        mounted = {row["mounted_unit"] for row in mounts.where(base_unit=base)}
        if mounted - campaign_mounts:
            raise ValueError(f"Beastmen hero mount lacks a campaign ancillary: {subtype}")
        for unit in sorted({base} | mounted):
            row = units.one(unit=unit)
            if (row["caste"] != "hero" or row["recruitment_cost"] != "0"
                    or row["upkeep_cost"] != "0"
                    or (unit != base and not row["mount"])):
                raise ValueError(f"Native free Beastmen hero unit changed: {unit}")
            if unit in result and result[unit] != cost:
                raise ValueError(f"Beastmen hero has conflicting prices: {unit}")
            result[unit] = cost
    return result


def rows(native):
    """Reuse the native rule that charges for free racial units at one host."""
    native["factions"].one(key=HOST)
    sets = native["faction_sets"]
    if FACTION_SET in sets.column("key"):
        raise ValueError("Beastmen hero economy faction set already exists")
    yield "faction_sets", dict(sets.one(key=NATIVE_SET), key=FACTION_SET)
    items = native["faction_set_items"]
    member = items.one(set=NATIVE_SET, faction=NATIVE_SET)
    if (member["culture"] or member["subculture"]
            or member["remove"] != "false"):
        raise ValueError("Native single-faction economy set changed")
    yield "faction_set_items", dict(
        member, id=stable_id(FACTION_SET, items.column("id")), faction=HOST,
        set=FACTION_SET)
    # Nagash pays for originally free Tomb Kings heroes without changing
    # their global main_units records. Reuse that same faction-set override.
    overrides = native["main_unit_faction_overrides"]
    template = overrides.one(
        faction_set=NATIVE_SET, unit="wh2_dlc09_tmb_cha_tomb_prince_0")
    if template["name_group"]:
        raise ValueError("Native hero economy override changes names")
    for unit, (recruitment, upkeep) in sorted(unit_costs(native).items()):
        yield "main_unit_faction_overrides", dict(
            template, faction_set=FACTION_SET, unit=unit,
            recruitment_cost=str(recruitment), upkeep_cost=str(upkeep))


def write_assets(native, output):
    """Use identical DB keys in the main mod and standalone hero test pack."""
    generated = {}
    for table, row in rows(native):
        generated.setdefault(table, []).append(row)
    for table, values in generated.items():
        write_table(output, native[table], values, FRAGMENT)
