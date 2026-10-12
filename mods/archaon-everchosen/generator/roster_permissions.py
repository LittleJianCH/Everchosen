"""Extend Archaon's campaign roster without changing recruitment sources."""
from host import HOST

# These factions own the native custom-battle rosters for the three races.
SOURCE_FACTIONS = (
    "wh_dlc03_bst_beastmen",
    "wh_dlc08_nor_norsca",
    "wh3_dlc23_chd_legion_of_azgorh",
)
TABLES = """factions groupings_military main_units
    units_custom_battle_permissions units_to_groupings_military_permissions
    units_to_exclusive_faction_permissions
""".split()


def campaign_units(native, faction):
    """Native military-group permissions plus explicit faction exceptions."""
    group = native["factions"].one(key=faction)["military_group"]
    native["groupings_military"].one(military_group=group)
    explicit = native["units_to_exclusive_faction_permissions"]
    permitted = {
        row["unit"] for row in native[
            "units_to_groupings_military_permissions"].where(
                military_group=group)
    } | {row["key"] for row in explicit.where(faction=faction, allowed="true")}
    denied = {row["key"] for row in explicit.where(
        faction=faction, allowed="false")}
    return permitted - denied


def regular_units(native, faction):
    """Ordinary troops and RoRs with native battle and campaign permission."""
    # Campaign-only hunt rewards, faction variants and scripted battle units
    # are not a race's ordinary roster. Encyclopedia flags cannot identify it:
    # native Jabberslythes, for example, have in_encyclopedia=false.
    battle_units = {
        row["unit"] for row in native["units_custom_battle_permissions"].where(
            faction=faction, campaign_exclusive="false", general_unit="false",
            set_piece_character="")
    }
    return {
        unit for unit in battle_units & campaign_units(native, faction)
        if native["main_units"].one(unit=unit)["caste"] not in ("lord", "hero")
    }


def permissions(native, host):
    """Yield only missing troop permissions for HOST's private native group."""
    factions = native["factions"]
    group = factions.one(key=host)["military_group"]
    owners = {row["key"] for row in factions.where(military_group=group)}
    if owners != {host}:
        raise ValueError(f"Host military group is not faction-specific: {owners}")

    available = campaign_units(native, host)
    # Preserve explicit native bans rather than competing with their priority.
    denied = {row["key"] for row in native[
        "units_to_exclusive_faction_permissions"].where(
            faction=host, allowed="false")}
    wanted = set().union(*(regular_units(native, faction)
                           for faction in SOURCE_FACTIONS))
    for unit in sorted(wanted - available - denied):
        yield "units_to_groupings_military_permissions", {
            "unit": unit, "military_group": group,
        }


def rows(native):
    yield from permissions(native, HOST)
