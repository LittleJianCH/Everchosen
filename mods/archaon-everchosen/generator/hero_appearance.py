"""Host-only native appearances for heroes sharing mixed-gender agent classes.

Culture-level gender defaults can differ from a permitted subtype's original
gender. Preserve its native appearance for either gender without changing the
source faction, subtype record, culture defaults, or recruitment permissions.
"""
import json
from copy import deepcopy

from db_tables import stable_id, write_table
from host import HOST
import hero_families

PREFIX = "everchosen_hero_appearance_"
FRAGMENT = "everchosen_hero_appearance"
TABLES = (*hero_families.TABLES, "campaign_character_art_sets",
          "campaign_character_arts", "agent_uniforms")
SOURCE_FACTIONS = (
    "wh_main_chs_chaos", "wh_dlc03_bst_beastmen", "wh_dlc08_nor_norsca",
    "wh3_dlc23_chd_zhatan", "wh3_main_dae_daemon_prince",
    "wh3_main_kho_exiles_of_khorne", "wh3_main_nur_poxmakers_of_nurgle",
    "wh3_main_sla_seducers_of_slaanesh",
    "wh3_main_tze_oracles_of_tzeentch",
)
# Verify the current DLC27 portraits when selecting its newer settings file.
IMAGE_INPUTS = sorted({
    f"ui/portraits/{kind}/no_culture/{family}_campaign_{number:02}_0{suffix}.png"
    for kind in ("portholes", "units")
    for family, mask in (("nor_fimir_noble", True),
                         ("sla_druchii_anointed", False))
    for number in range(1, 4)
    for suffix in (("", "_mask1") if mask else ("",))})
NATIVE_INPUTS = {
    "ui.pack": [*(f"ui/portraits/{kind}/portrait_settings__.bin"
                  for kind in ("portholes", "units")), *IMAGE_INPUTS],
    "ui_3.pack": [f"ui/portraits/{kind}/portrait_settings__3.bin"
                  for kind in ("portholes", "units")],
}


def supported_heroes(native):
    """Return ordinary source-faction permissions and native display metadata."""
    metadata = hero_families.script_data(native)
    for faction in SOURCE_FACTIONS:
        native["factions"].one(key=faction)
    heroes = {}
    for row in native["faction_agent_permitted_subtypes"].rows:
        if (row["faction"] in SOURCE_FACTIONS
                and row["mod_disabled"] == "false"
                and row["subtype"] in metadata):
            existing = heroes.setdefault(row["subtype"], row)
            if existing["agent"] != row["agent"]:
                raise ValueError("A supported hero has multiple agent classes")
    return heroes, metadata


def bridge_sets(native, heroes):
    """Pair each missing-gender host art set with its original native record."""
    host = native["factions"].one(key=HOST)
    sources = {}
    genders = {}
    for subtype, permission in sorted(heroes.items()):
        agent = permission["agent"]
        variants = [row for row in native["campaign_character_art_sets"].rows
                    if row["agent_subtype"] == subtype
                    and (not row["agent_type"] or row["agent_type"] == agent)
                    and row["is_custom"] == "false"
                    and all(not row[field] or row[field] == value
                            for field, value in (
                                ("culture", "wh_main_chs_chaos"),
                                ("subculture", host["subculture"]),
                                ("faction", HOST)))]
        if not variants:
            raise ValueError(f"Missing native supported hero art set: {subtype}")
        sources[subtype] = variants
        genders.setdefault(agent, set()).update(row["is_male"]
                                                for row in variants)
    result = []
    existing = native["campaign_character_art_sets"].column("art_set_id")
    for subtype, variants in sorted(sources.items()):
        agent = heroes[subtype]["agent"]
        missing = genders[agent] - {row["is_male"] for row in variants}
        for gender in sorted(missing):
            for source in sorted(variants, key=lambda row: row["art_set_id"]):
                key = PREFIX + source["art_set_id"] + (
                    "_male" if gender == "true" else "_female")
                if key in existing:
                    raise ValueError(f"Host appearance key already exists: {key}")
                result.append((source, dict(source, art_set_id=key,
                    agent_type=agent, faction=HOST, is_male=gender)))
    return result


def write_assets(native_root, output, native, heroes):
    """Write identical DB/portrait keys when both products cover the same hero."""
    bridges = bridge_sets(native, heroes)
    used = native["campaign_character_arts"].column("id")
    arts = []
    portraits = {}
    for source, target in bridges:
        linked = native["campaign_character_arts"].where(
            art_set_id=source["art_set_id"])
        if not linked:
            raise ValueError(f"Missing native appearance: {source['art_set_id']}")
        for original in linked:
            for field in ("uniform", "sea_uniform", "navy_uniform"):
                if original[field]:
                    native["agent_uniforms"].one(uniform_name=original[field])
            key = target["art_set_id"]
            portrait = original["portrait"] or source["art_set_id"]
            if key in portraits and portraits[key] != portrait:
                raise ValueError(f"Multiple native portraits for {key}")
            portraits[key] = portrait
            arts.append(dict(original,
                id=stable_id(key + "/" + original["id"], used),
                art_set_id=key))

    for relative in IMAGE_INPUTS:
        if not (native_root / relative).is_file():
            raise ValueError(f"Missing native hero portrait image: {relative}")
    for kind in ("portholes", "units"):
        entries = {}
        version = None
        for paths in NATIVE_INPUTS.values():
            for relative in paths:
                if not (relative.endswith(".bin")
                        and relative.split("/")[2] == kind):
                    continue
                document = json.loads((native_root / (relative + ".json"))
                                      .read_text(encoding="utf-8"))
                if version is not None and version != document["version"]:
                    raise ValueError("Native portrait versions differ")
                version = document["version"]
                for entry in document["entries"]:
                    if entry["id"] in entries:
                        raise ValueError(f"Duplicate native portrait: {entry['id']}")
                    entries[entry["id"]] = entry
        copies = []
        for key, original in sorted(portraits.items()):
            if key in entries or original not in entries:
                raise ValueError(f"Missing or conflicting native portrait: {key}")
            entry = deepcopy(entries[original])
            entry["id"] = key
            copies.append(entry)
        destination = (output / "ui/portraits" / kind
                       / "portrait_settings__everchosen_heroes.bin.json")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps({"version": version, "entries": copies},
            ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_table(output, native["campaign_character_art_sets"],
                [target for _, target in bridges], FRAGMENT)
    write_table(output, native["campaign_character_arts"], arts, FRAGMENT)
    print(f"Hero appearances: {len(bridges)} host-only gender variants, "
          f"{len(arts)} native appearance links, two portrait-setting fragments")
