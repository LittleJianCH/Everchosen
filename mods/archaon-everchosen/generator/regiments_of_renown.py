"""Extend Archaon's RoR pool while retaining native units and replenishment."""
from host import HOST
from roster_permissions import SOURCE_FACTIONS, campaign_units, regular_units
from roster_permissions import TABLES as ROSTER_TABLES

TABLES = (*ROSTER_TABLES, "mercenary_pools", "mercenary_unit_groups",
          "mercenary_pool_to_groups_junctions",
          "faction_to_mercenary_set_junctions")

# Native wh_dlc08_monster_hunt.lua unlocks these only after their hunts.
# Some also appear in the normal RoR pool and custom-battle roster.
HUNT_REWARDS = {
    "wh_dlc08_nor_mon_frost_wyrm_ror_0",
    "wh_dlc08_nor_mon_war_mammoth_ror_1",
    "wh3_dlc27_nor_mon_chimera_ror",
}
EXTRA_RORS = {
    "wh3_dlc20_chs_vilitch": {"wh3_dlc24_tze_inf_pink_horrors_ror"},
}


def renown_pools(native, faction):
    """RoR pools registered to FACTION, excluding its other mercenary sources."""
    return {
        row["mercenary_set"] for row in native[
            "faction_to_mercenary_set_junctions"].where(faction=faction)
        if native["mercenary_pools"].one(key=row["mercenary_set"])[
            "ui_recruitment_info"] == "renown"
    }


def pool_entries(native, faction):
    """Native RoR entries whose faction and subculture gates admit FACTION."""
    subculture = native["factions"].one(key=faction)["subculture"]
    pools = renown_pools(native, faction)
    return [row for row in native["mercenary_pool_to_groups_junctions"].rows
            if row["pool"] in pools
            and row["faction_requirement"] in ("", faction)
            and row["subculture_requirement"] in ("", subculture)]


def additions(native):
    """Select new host entries; the engine precompiles these DB links in startpos."""
    host_entries = pool_entries(native, HOST)
    pools = renown_pools(native, HOST)
    if len(pools) != 1:
        raise ValueError("Expected one native Archaon renown pool")
    pool = pools.pop()
    groups = {row["key"]: row for row in native["mercenary_unit_groups"].rows}
    available = {groups[row["group"]]["unit_record"] for row in host_entries}
    denied = native["units_to_exclusive_faction_permissions"].where(
        faction=HOST, allowed="false")
    available.update(row["key"] for row in denied)
    for faction in (*SOURCE_FACTIONS, *EXTRA_RORS):
        troops = (EXTRA_RORS[faction] if faction in EXTRA_RORS
                  else regular_units(native, faction))
        for row in pool_entries(native, faction):
            group = groups[row["group"]]
            unit = group["unit_record"]
            if (unit not in troops or unit in available or unit in HUNT_REWARDS
                    or int(group["max_count"]) <= 0
                    or native["main_units"].one(unit=unit)["is_renown"] != "true"):
                continue
            available.add(unit)
            yield dict(
                row,
                pool=pool, faction_requirement=HOST, subculture_requirement="")


def rows(native):
    """The three race rosters already supply their troop permissions."""
    extras = set().union(*EXTRA_RORS.values())
    permitted = campaign_units(native, HOST)
    for row in additions(native):
        unit = native["mercenary_unit_groups"].one(key=row["group"])["unit_record"]
        if unit in extras and unit not in permitted:
            yield "units_to_groupings_military_permissions", {
                "unit": unit,
                "military_group": native["factions"].one(key=HOST)[
                    "military_group"],
            }


def script_data(native):
    """Runtime registration uses recruitment_sources keys, not UI info keys."""
    groups = {row["key"]: row for row in native["mercenary_unit_groups"].rows}
    result = []
    for row in additions(native):
        group = groups[row["group"]]
        pool = native["mercenary_pools"].one(key=row["pool"])
        result.append({
            "unit": group["unit_record"], "group": row["group"],
            "source": pool["recruitment_source"],
            "count": int(row["initial_unit_count"]),
            "chance": float(group["chance_to_replenish"]),
            "maximum": int(group["max_count"]),
            "rate": float(group["max_replenish_per_turn"]),
            "partial": group["use_partial_replenishment"] == "true",
            "faction": row["faction_requirement"],
            "subculture": row["subculture_requirement"],
            "technology": row["tech_requirement"],
        })
    return result
