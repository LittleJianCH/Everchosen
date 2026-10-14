"""Bind vassal-city recruitment discounts to the adapted military rosters."""

PREFIX = "everchosen_vassal_recruit_"
UNIT_SETS = {
    "norsca": PREFIX + "units_norsca",
    "chaos_dwarfs": PREFIX + "units_chd",
}
BUNDLES = {
    "norsca": "everchosen_vassal_recruitment_norsca",
    "chaos_dwarfs": "everchosen_vassal_recruitment_chd",
}
EFFECTS = {
    "norsca": PREFIX + "cost_norsca",
    "chaos_dwarfs": PREFIX + "cost_chd",
}
TABLES = """main_units unit_sets unit_set_to_unit_junctions effects
    effect_bonus_value_ids_unit_sets effect_bundles
    effect_bundles_to_effects_junctions campaign_effect_scopes
""".split()


def rows(native, building_data):
    """Create exact unit-set membership from adapted recruitment buildings."""
    rosters = {race: set(building_data[race]["units"]) for race in UNIT_SETS}
    if any(not units for units in rosters.values()):
        raise ValueError("A vassal military recruitment roster is empty")
    if rosters["norsca"] & rosters["chaos_dwarfs"]:
        raise ValueError("Race-specific recruitment discounts overlap")
    for race, units in rosters.items():
        for unit in sorted(units):
            record = native["main_units"].one(unit=unit)
            if record["caste"] in ("lord", "hero"):
                raise ValueError(f"Non-troop in {race} recruitment roster: {unit}")
            yield "unit_set_to_unit_junctions", {
                "unit_caste": "", "unit_category": "", "unit_class": "",
                "unit_record": unit, "unit_set": UNIT_SETS[race],
                "exclude": "false",
            }


def validate(native, generated, authored, building_data):
    """Check both discounts reach only the adapted buildings' unit lists."""
    actual = generated.get("unit_set_to_unit_junctions", [])
    for race, unit_set in UNIT_SETS.items():
        expected = set(building_data[race]["units"])
        selected = {row["unit_record"] for row in actual
                    if row["unit_set"] == unit_set and row["exclude"] == "false"}
        if selected != expected:
            raise ValueError(f"Incomplete {race} recruitment discount set")
    effects = {row["effect"] for row in authored.get("effects", [])}
    bundles = {row["key"]: row for row in authored.get("effect_bundles", [])}
    sets = {row["key"] for row in authored.get("unit_sets", [])}
    scopes = native["campaign_effect_scopes"].column("key")
    for race in UNIT_SETS:
        effect = EFFECTS[race]
        bundle = BUNDLES[race]
        unit_set = UNIT_SETS[race]
        binding = [row for row in authored.get(
            "effect_bonus_value_ids_unit_sets", [])
            if row["effect"] == effect]
        junction = [row for row in authored.get(
            "effect_bundles_to_effects_junctions", [])
            if row["effect_bundle_key"] == bundle]
        if (effect not in effects or unit_set not in sets
                or bundle not in bundles
                or bundles[bundle]["bundle_target"] != "faction"
                or len(binding) != 1 or len(junction) != 1
                or binding[0]["bonus_value_id"] != "cost_mod"
                or binding[0]["unit_set"] != unit_set
                or junction[0]["effect_key"] != effect
                or junction[0]["effect_scope"] != "faction_to_force_own"
                or junction[0]["effect_scope"] not in scopes):
            raise ValueError(f"Invalid {race} recruitment discount binding")
