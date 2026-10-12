"""Army training, with reconstitution limited to native daemonic units."""
from pathlib import Path
from db_tables import read_authored

PREFIX = "everchosen_daemon_"
TABLES = """unit_sets unit_set_to_unit_junctions land_units
    unit_attributes_to_groups_junctions effect_bonus_value_ids_unit_sets
    campaign_operation_set_effect_bundle_elements campaign_operation_effect_bundles
""".split()


def nurgle_daemons(native):
    roster = {r["unit_record"] for r in native["unit_set_to_unit_junctions"].where(
        unit_set="wh3_main_nur_all", exclude="false")}
    groups = {r["attribute_group"] for r in
              native["unit_attributes_to_groups_junctions"].where(attribute="daemonic")}
    land = {r["key"] for r in native["land_units"].rows
            if r["attribute_group"] in groups}
    units = {r["unit"] for r in native["main_units"].rows
             if r["land_unit"] in land and r["unit"] in roster
             and r["caste"] not in ("lord", "hero")}
    if not units:
        raise ValueError("No native daemonic troops")
    return sorted(units)


def rows(native):
    # Ordinary training uses the native god rosters, including marked mortals.
    # Only reconstitution needs an attribute-derived daemon subset.
    key = PREFIX + "units_nurgle"
    yield "unit_sets", dict(native["unit_sets"].one(key="daemonic_units"), key=key)
    for unit in nurgle_daemons(native):
        yield "unit_set_to_unit_junctions", {
            "unit_set": key, "unit_record": unit, "unit_caste": "",
            "unit_category": "", "unit_class": "", "exclude": "false"}


def progression(native):
    authored = read_authored(Path(__file__).resolve().parents[1] / "assets/db", native)
    return {r["key"]: {"resource": r["pooled_resource_set"],
                        "minimum": int(r["lower_bound"]), "bundle": r["key"]}
            for r in authored["pooled_resource_threshold_operation_sets"]
            if r["key"].startswith(PREFIX + "legion_")}


def validate(native, generated, authored):
    effects = native["effects"].column("effect") | {
        r["effect"] for r in authored.get("effects", [])}
    bundles = {r["key"] for r in authored.get("effect_bundles", [])}
    sets = native["unit_sets"].column("key") | {
        r["key"] for r in generated.get("unit_sets", []) +
        authored.get("unit_sets", [])}
    bonuses = native["effect_bonus_value_ids_unit_sets"].column("bonus_value_id")
    for row in authored.get("effect_bonus_value_ids_unit_sets", []):
        if (row["effect"] not in effects or row["unit_set"] not in sets
                or row["bonus_value_id"] not in bonuses):
            raise ValueError(f"Invalid daemon stat binding: {row}")
    for row in authored.get("effect_bundles_to_effects_junctions", []):
        if row["effect_bundle_key"].startswith(PREFIX + "legion_"):
            if (row["effect_scope"] != "general_to_force_own"
                    or row["effect_key"] not in effects):
                raise ValueError(f"Army reward escapes the prince: {row}")
    for reward in progression(native).values():
        if reward["bundle"] not in bundles:
            raise ValueError("Missing legion bundle")
