"""Charge Archaon for Beastmen troops without changing native racial costs."""
from collections import defaultdict

from beastmen_hero_economy import FACTION_SET, NATIVE_SET
from roster_permissions import TABLES as ROSTER_TABLES, regular_units

SOURCE = "wh_dlc03_bst_beastmen"
TABLES = (*ROSTER_TABLES, "main_unit_faction_overrides")

# These equivalents have matching combat stats but separate land-unit records.
PRICE_REFERENCES = {
    "wh_dlc03_bst_mon_giant_0": "wh_main_chs_mon_giant",
    "wh_dlc05_bst_mon_harpies_0": "wh2_main_def_inf_harpies",
}


def unit_costs(native):
    """Fill zero costs from identical paid units, then native battle value."""
    units = native["main_units"]
    counterparts = defaultdict(set)
    for row in units.rows:
        recruitment = int(row["recruitment_cost"])
        upkeep = int(row["upkeep_cost"])
        if recruitment > 0 and upkeep > 0:
            counterparts[(row["land_unit"], row["caste"], row["is_renown"])].add(
                (recruitment, upkeep))
    result = {}
    for unit in sorted(regular_units(native, SOURCE)):
        row = units.one(unit=unit)
        recruitment = int(row["recruitment_cost"])
        upkeep = int(row["upkeep_cost"])
        if recruitment and upkeep:
            continue
        reference = (units.one(unit=PRICE_REFERENCES[unit])
                     if unit in PRICE_REFERENCES else row)
        comparisons = counterparts[(reference["land_unit"], reference["caste"],
                                     reference["is_renown"])]
        if len(comparisons) > 1:
            raise ValueError(f"Ambiguous native troop costs: {unit}: {comparisons}")
        value = int(row["multiplayer_cost"])
        if value <= 0:
            raise ValueError(f"Missing native troop valuation: {unit}")
        reference_recruitment, reference_upkeep = next(
            iter(comparisons), (value, (value + 2) // 4))
        result[unit] = (recruitment or reference_recruitment,
                        upkeep or reference_upkeep)
    return result


def rows(native):
    """Share the existing Archaon-only Beastmen hero economy faction set."""
    template = native["main_unit_faction_overrides"].one(
        faction_set=NATIVE_SET, unit="wh2_dlc09_tmb_cha_tomb_prince_0")
    for unit, (recruitment, upkeep) in unit_costs(native).items():
        yield "main_unit_faction_overrides", dict(
            template, faction_set=FACTION_SET, unit=unit,
            recruitment_cost=str(recruitment), upkeep_cost=str(upkeep))
