"""Daemon-only unit sets derived from current land-unit attributes."""
from pathlib import Path
from db_tables import read_authored

PREFIX = "everchosen_daemon_"
GODS = {"khorne": "kho", "nurgle": "nur", "slaanesh": "sla",
        "tzeentch": "tze", "undivided": None}
TABLES = """unit_sets unit_set_to_unit_junctions land_units
    unit_attributes_to_groups_junctions effect_bonus_value_ids_unit_sets
    campaign_operation_set_effect_bundle_elements campaign_operation_effect_bundles
""".split()


def daemon_units(native):
    groups = {r["attribute_group"] for r in
              native["unit_attributes_to_groups_junctions"].where(attribute="daemonic")}
    land = {r["key"] for r in native["land_units"].rows
            if r["attribute_group"] in groups}
    units = {r["unit"] for r in native["main_units"].rows
             if r["land_unit"] in land and r["caste"] not in ("lord", "hero")}
    if not units:
        raise ValueError("No native daemonic troops")
    return {god: sorted(k for k in units if short is None or f"_{short}_" in k)
            for god, short in GODS.items()}


def rows(native):
    for god, units in daemon_units(native).items():
        key = PREFIX + "units_" + god
        if not units:
            raise ValueError("Empty daemon roster: " + god)
        yield "unit_sets", dict(native["unit_sets"].one(key="daemonic_units"), key=key)
        for unit in units:
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
        r["key"] for r in generated.get("unit_sets", [])}
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
