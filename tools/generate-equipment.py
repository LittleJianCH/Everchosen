"""Generate private ancillary eligibility sets from an extracted native DB.

Only ancillary faction_set references change. Native faction-set memberships
are copied into private sets so shared game permissions remain untouched.
Character, skill, rank, quest, and drop rules are outside this generator.
"""
import argparse
import csv
import json
import zlib
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FRAGMENT = "everchosen_chaos_equipment"


def read_table(db, name):
    folder = db / (name + "_tables")
    paths = sorted(folder.iterdir())
    if not paths or any(p.suffix != ".tsv" for p in paths):
        raise ValueError(f"{folder}: missing or undecoded native table")
    header, metadata, rows = None, None, []
    for path in paths:
        with path.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.reader(stream, delimiter="\t")
            columns, schema = next(reader), next(reader)[0]
            if not schema.startswith(f"#{name}_tables;"):
                raise ValueError(f"{path}: invalid schema metadata")
            if header is not None and (columns != header or schema.split(";")[:2] != metadata.split(";")[:2]):
                raise ValueError(f"{path}: inconsistent table schema")
            header, metadata = columns, schema
            for row in reader:
                if len(row) != len(header):
                    raise ValueError(f"{path}: unexpected column count")
                rows.append(dict(zip(header, row)))
    keys = [row[header[0]] for row in rows]
    if len(keys) != len(set(keys)):
        raise ValueError(f"{folder}: overlapping native fragments need explicit load-order resolution")
    return header, metadata, rows


def write_table(output, name, table, rows):
    header, metadata, _ = table
    path = output / "db" / (name + "_tables") / (FRAGMENT + ".tsv")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerow([";".join(metadata.split(";")[:2]) + f";db/{name}_tables/{FRAGMENT}"]
                        + [""] * (len(header) - 1))
        for row in rows:
            writer.writerow([row[column] for column in header])


def generate(vanilla, output):
    rules = json.loads((ROOT / "mods/chaos-equipment/eligibility.json").read_text(encoding="utf-8"))
    db = vanilla / "db"
    tables = {name: read_table(db, name) for name in
              ("ancillaries", "faction_sets", "faction_set_items", "factions", "cultures")}
    cultures = {r["key"] for r in tables["cultures"][2]}
    faction_subcultures = {r["key"]: r["subculture"] for r in tables["factions"][2]}
    sources = rules["sources"]
    if not {s["culture"] for s in sources} | {rules["target_culture"]} <= cultures:
        raise ValueError("Configured cultures are missing from the native DB")
    if not {s["subculture"] for s in sources} | {rules["target_subculture"]} <= set(faction_subcultures.values()):
        raise ValueError("Configured subcultures are missing from the native DB")
    source_cultures = {s["culture"] for s in sources}
    source_subcultures = {s["subculture"] for s in sources}
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
        return (row["culture"] in ("*", rules["target_culture"])
                or row["subculture"] in ("*", rules["target_subculture"])
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
        if original["category"] not in rules["categories"]:
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
                                   or faction_subcultures.get(row["faction"]) == rules["target_subculture"])
                if row["remove"] == "true" and excludes_target:
                    raise ValueError(f"{key}: explicit WOC exclusion requires a design decision")
            private_sets[key] = private
            new_sets.append({"key": private})
            for row in sorted(membership, key=lambda r: int(r["id"])):
                copied = dict(row, id=new_id(private + ":" + row["id"]), set=private)
                new_members.append(copied)
            new_members.append({
                "id": new_id(private + ":warriors_of_chaos"),
                "culture": rules["target_culture"], "faction": "", "remove": "false",
                "set": private, "subculture": ""})
        patches.append(dict(original, faction_set=private_sets[key]))

    if not patches:
        raise ValueError("No equipment matched the configured source factions")
    for name, rows in (("ancillaries", patches), ("faction_sets", new_sets),
                       ("faction_set_items", new_members)):
        write_table(output, name, tables[name], rows)
    counts = Counter(row["category"] for row in patches)
    print(f"Equipment: {len(patches)} ancillary overrides, {len(new_sets)} private sets; "
          + ", ".join(f"{key}={value}" for key, value in sorted(counts.items())))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vanilla", type=Path, required=True,
                        help="RPFM TSV extraction root containing db/")
    parser.add_argument("--output", type=Path, required=True,
                        help="Generated pack staging directory")
    args = parser.parse_args()
    generate(args.vanilla, args.output)
