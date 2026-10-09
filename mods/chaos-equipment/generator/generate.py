"""Generate private ancillary eligibility sets from an extracted native DB.

Only ancillary faction_set references change. Native faction-set memberships
are copied into private sets so shared game permissions remain untouched.
Character, skill, rank, quest, and drop rules are outside this generator.
"""
import sys
import zlib
from collections import Counter, defaultdict
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from db_tables import read_table, write_table, run_generator

DB_TABLES = ("ancillaries", "faction_sets", "faction_set_items", "factions", "cultures")
NATIVE_INPUTS = {"db.pack": [f"db/{name}_tables" for name in DB_TABLES]}
FRAGMENT = "everchosen_chaos_equipment"
TARGET_CULTURE = "wh_main_chs_chaos"
TARGET_SUBCULTURE = "wh_main_sc_chs_chaos"
CATEGORIES = {"weapon", "armour", "talisman", "enchanted_item",
              "arcane_item", "mount"}
SOURCES = (
    ("wh3_main_kho_khorne", "wh3_main_sc_kho_khorne"),
    ("wh3_main_nur_nurgle", "wh3_main_sc_nur_nurgle"),
    ("wh3_main_tze_tzeentch", "wh3_main_sc_tze_tzeentch"),
    ("wh3_main_sla_slaanesh", "wh3_main_sc_sla_slaanesh"),
    ("wh_dlc08_nor_norsca", "wh_dlc08_sc_nor_norsca"),
    ("wh_dlc03_bst_beastmen", "wh_dlc03_sc_bst_beastmen"),
    ("wh3_dlc23_chd_chaos_dwarfs", "wh3_dlc23_sc_chd_chaos_dwarfs"),
)


def generate(vanilla, output):
    db = vanilla / "db"
    tables = {name: read_table(db, name, ("id" if name == "faction_set_items" else "key",))
              for name in DB_TABLES}
    cultures = {r["key"] for r in tables["cultures"][2]}
    faction_subcultures = {r["key"]: r["subculture"] for r in tables["factions"][2]}
    source_cultures = {culture for culture, _ in SOURCES}
    source_subcultures = {subculture for _, subculture in SOURCES}
    if not source_cultures | {TARGET_CULTURE} <= cultures:
        raise ValueError("Configured cultures are missing from the native DB")
    if not source_subcultures | {TARGET_SUBCULTURE} <= set(faction_subcultures.values()):
        raise ValueError("Configured subcultures are missing from the native DB")
    members = defaultdict(list)
    for row in tables["faction_set_items"][2]:
        members[row["set"]].append(row)
    native_sets = {row["key"] for row in tables["faction_sets"][2]}
    used_ids = {row["id"] for row in tables["faction_set_items"][2]}

    def is_source(row):
        return (row["culture"] in source_cultures
                or row["subculture"] in source_subcultures
                or faction_subcultures.get(row["faction"]) in source_subcultures)

    def covers_target(row):
        return (row["culture"] in ("*", TARGET_CULTURE)
                or row["subculture"] in ("*", TARGET_SUBCULTURE)
                or not any(row[k] for k in ("culture", "subculture", "faction")))

    def new_id(label):
        # Stable positive signed 32-bit IDs, checked against all native memberships.
        value = str(zlib.crc32(label.encode("utf-8")) & 0x7fffffff)
        if value in used_ids:
            raise ValueError(f"Faction-set membership ID collision: {label}")
        used_ids.add(value)
        return value

    patches, new_sets, new_members = [], [], []
    private_sets = {}
    for original in sorted(tables["ancillaries"][2], key=lambda r: r["key"]):
        if original["category"] not in CATEGORIES:
            continue
        key = original["faction_set"]
        if key not in native_sets:
            raise ValueError(f"{original['key']}: missing native faction set {key}")
        membership = members[key]
        included = [r for r in membership if r["remove"] == "false"]
        # Broad generic permissions and sets already covering WOC keep their native exclusions.
        if key == "all" or any(covers_target(r) for r in included):
            continue
        if not any(is_source(r) for r in included):
            continue
        if key not in private_sets:
            private = "everchosen_equipment_" + key
            if private in native_sets:
                raise ValueError(f"Private faction set collides with native DB: {private}")
            # A target exclusion cannot be silently defeated by adding an inclusion.
            for row in membership:
                excludes_target = (covers_target(row)
                                   or faction_subcultures.get(row["faction"]) == TARGET_SUBCULTURE)
                if row["remove"] == "true" and excludes_target:
                    raise ValueError(f"{key}: explicit WOC exclusion requires a design decision")
            private_sets[key] = private
            new_sets.append({"key": private})
            for row in sorted(membership, key=lambda r: int(r["id"])):
                copied = dict(row, id=new_id(private + ":" + row["id"]), set=private)
                new_members.append(copied)
            new_members.append({
                "id": new_id(private + ":warriors_of_chaos"),
                "culture": TARGET_CULTURE, "faction": "", "remove": "false",
                "set": private, "subculture": ""})
        patches.append(dict(original, faction_set=private_sets[key]))

    if not patches:
        raise ValueError("No equipment matched the configured source factions")
    for name, rows in (("ancillaries", patches), ("faction_sets", new_sets),
                       ("faction_set_items", new_members)):
        write_table(output, name, tables[name], rows, FRAGMENT)
    counts = Counter(row["category"] for row in patches)
    print(f"Equipment: {len(patches)} ancillary overrides, {len(new_sets)} private sets; "
          + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
