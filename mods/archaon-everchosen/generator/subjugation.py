"""Derive lord adaptations and reuse dormant Immortal Empires factions."""
from db_tables import stable_id
import skill_slots

PREFIX = "everchosen_subjugation_"
HOST = "wh_main_chs_chaos"
CAMPAIGN = "wh3_main_combi"
DAEMON_FACTION = "wh3_main_dae_daemon_prince"
DAEMON_SUCCESSOR = "wh3_dlc20_chs_daemon_prince_undivided"
CLIENTS = {
    "nor": ("wh_dlc08_nor_norsca", "wh3_dlc20_nor_kuj",
            "wh_main_nor_marauder_chieftain", "norsca-v1.png"),
    "chd": ("wh3_dlc23_chd_chaos_dwarfs", "wh3_dlc23_chd_chaos_dwarfs_qb3",
            "wh3_dlc23_chd_overseer", "chaos-dwarfs-v1.png"),
    "bst": ("wh_dlc03_bst_beastmen", "wh_dlc03_bst_beastmen_chaos",
            "wh_dlc03_bst_beastlord", "beastmen-v1.png"),
}
HUNT_ARMY = "wh3_dlc27_qb_nor_monster_hunt_20_main"
HUNT_FACTION = "wh3_dlc23_chd_chaos_dwarfs_qb2"
# Free qb3's only native set-piece role without changing its army identity.
COPIED_ROWS = (
    ("battle_set_piece_armies",
     {"army_name": HUNT_ARMY, "faction": CLIENTS["chd"][1]},
     {"faction": HUNT_FACTION}),
    # This subtype has auto_generate=false; permission lets the retained
    # faction own its scripted successor without creating a recruitment pool.
    ("faction_agent_permitted_subtypes",
     {"faction": "wh3_dlc29_chaos_invasion_confederation_owner",
      "agent": "general", "subtype": DAEMON_SUCCESSOR},
     {"faction": DAEMON_FACTION}),
)
TARGETS = {
    "wh_dlc08_nor_norsca": "wh_dlc08_nor_wulfrik",
    "wh_dlc08_nor_wintertooth": "wh_dlc08_nor_throgg",
    "wh3_dlc27_nor_sayl": "wh3_dlc27_nor_sayl_the_faithless",
    "wh3_dlc23_chd_astragoth": "wh3_dlc23_chd_astragoth",
    "wh3_dlc23_chd_legion_of_azgorh": "wh3_dlc23_chd_drazhoath",
    "wh3_dlc23_chd_zhatan": "wh3_dlc23_chd_zhatan",
    "wh_dlc03_bst_beastmen": "wh_dlc03_bst_khazrak",
    "wh2_dlc17_bst_malagor": "wh_dlc03_bst_malagor",
    "wh_dlc05_bst_morghur_herd": "wh_dlc05_bst_morghur",
    "wh2_dlc17_bst_taurox": "wh2_dlc17_bst_taurox",
}
TABLES = """factions start_pos_factions faction_agent_permitted_subtypes agent_subtypes
    character_skill_node_sets character_skill_node_set_items
    character_skill_nodes character_skill_node_links character_skills
    character_skill_level_to_effects_junctions
    main_units dilemmas cdir_events_dilemma_choice_details
    cdir_events_dilemma_option_junctions cdir_events_dilemma_payloads
""".split()
UNIT_SLOTS = ("inf_low", "inf_low_special", "inf_high", "inf_high_special",
              "cav_low", "cav_high", "monster_low", "monster_med", "monster_high")
CHALLENGE_UNITS = {
    "nor": ("wh_main_nor_inf_chaos_marauders_0", "wh_dlc08_nor_inf_marauder_berserkers_0",
            "wh_dlc08_nor_inf_marauder_champions_0", "wh_dlc08_nor_inf_marauder_champions_1",
            "wh_main_nor_cav_marauder_horsemen_0", "wh_main_nor_cav_marauder_horsemen_1",
            "wh_dlc08_nor_mon_skinwolves_0", "wh_dlc08_nor_mon_norscan_ice_trolls_0",
            "wh_dlc08_nor_mon_war_mammoth_1"),
    "chd": ("wh3_dlc23_chd_inf_hobgoblin_cutthroats", "wh3_dlc23_chd_inf_chaos_dwarf_warriors",
            "wh3_dlc23_chd_inf_infernal_guard", "wh3_dlc23_chd_inf_infernal_ironsworn",
            "wh3_dlc23_chd_cav_hobgoblin_wolf_raiders_spears", "wh3_dlc23_chd_cav_bull_centaurs_axe",
            "wh3_dlc23_chd_mon_kdaai_fireborn", "wh3_dlc23_chd_mon_great_taurus",
            "wh3_dlc23_chd_mon_kdaai_destroyer"),
    "bst": ("wh_dlc03_bst_inf_ungor_spearmen_0", "wh_dlc03_bst_inf_gor_herd_0",
            "wh_dlc03_bst_inf_gor_herd_1", "wh_dlc03_bst_inf_bestigor_herd_0",
            "wh_dlc03_bst_inf_centigors_0", "wh_dlc03_bst_inf_centigors_2",
            "wh_dlc03_bst_inf_minotaurs_0", "wh_dlc03_bst_inf_cygor_0",
            "wh2_dlc17_bst_mon_ghorgon_0"),
}


def client_key(race):
    return CLIENTS[race][1]


def identity_key(race):
    return PREFIX + race + "_vassal_owner"


def client_factions(native):
    table = native["factions"]
    for race, (_, source, general, _) in CLIENTS.items():
        native["agent_subtypes"].one(key=general)
        row = table.one(key=source)
        if row["is_rebel"] != "false" or row["is_quest_faction"] != "false":
            raise ValueError(f"Client must be an ordinary campaign faction: {source}")
        native["start_pos_factions"].one(faction=source, campaign=CAMPAIGN)
        # Preserve identity, permissions and all gameplay fields. Naming is
        # changed only after the campaign script claims the dormant faction.
        row["flags_path"] = "ui/flags/" + identity_key(race)
        yield table.name, row


def chaos_blue_line(native):
    return [native["character_skill_nodes"].one(
        key=f"wh_main_skill_node_chs_lord_campaign_{i:02d}")
        for i in range(1, 12)]


def original_tree(native, subtype):
    tree = native["character_skill_node_sets"].one(
        agent_subtype_key=subtype, faction_key="", subculture="", campaign_key="")
    members = native["character_skill_node_set_items"].where(
        set=tree["key"], mod_disabled="false")
    nodes = [native["character_skill_nodes"].one(key=r["item"])
             for r in members]
    return tree, nodes


def skill_mapping(native):
    levels = native["character_skill_level_to_effects_junctions"]
    blue = {(r["indent"], r["tier"]): r for r in chaos_blue_line(native)}
    result = {}
    for subtype in TARGETS.values():
        _, original = original_tree(native, subtype)
        old_blue = [r for r in original if r["indent"] == "5"]
        if {(r["indent"], r["tier"]) for r in old_blue} != blue.keys():
            raise ValueError(f"Native blue-line positions changed: {subtype}")
        pairs = []
        for row in old_blue:
            replacement = blue[row["indent"], row["tier"]]
            maximum = max(int(r["level"]) for r in levels.where(
                character_skill_key=replacement["character_skill_key"]))
            pairs.append((row, replacement, maximum))
        result[subtype] = skill_slots.mapping(
            native, pairs, [r for r in original if r["indent"] != "5"])
    return result


def skills(native):
    nodes = native["character_skill_nodes"]
    items = native["character_skill_node_set_items"]
    blue = chaos_blue_line(native)
    blue_keys = {row["key"] for row in blue}
    links = [row for row in native["character_skill_node_links"].rows
             if row["child_key"] in blue_keys and row["parent_key"] in blue_keys]
    for faction, subtype in TARGETS.items():
        native["agent_subtypes"].one(key=subtype)
        subculture = native["factions"].one(key=faction)["subculture"]
        tree, original = original_tree(native, subtype)
        original_blue = [row for row in original if row["indent"] == "5"]
        if len(original_blue) != len(blue):
            raise ValueError(f"Native blue line changed: {subtype}")
        for row in original_blue:
            if row["subculture"] not in ("", subculture):
                raise ValueError(f"Unexpected native skill restriction: {row}")
            yield nodes.name, dict(row, subculture=subculture)
        mapping = {row["key"]: PREFIX + subtype + "_blue_" + str(index)
                   for index, row in enumerate(blue)}
        for row in blue:
            yield nodes.name, dict(row, key=mapping[row["key"]],
                                   campaign_key=CAMPAIGN, faction_key=HOST,
                                   subculture="")
            yield items.name, {"set": tree["key"], "item": mapping[row["key"]],
                               "mod_disabled": "false"}
        for row in links:
            yield "character_skill_node_links", dict(
                row, child_key=mapping[row["child_key"]],
                parent_key=mapping[row["parent_key"]])
        authority = nodes.one(key="wh3_dlc20_skill_node_chs_lord_authority")
        authority.update(key=PREFIX + subtype + "_authority",
                         campaign_key=CAMPAIGN, faction_key=HOST, subculture="",
                         tier=str(max(int(r["tier"]) for r in original
                                      if r["indent"] == "0") + 1))
        yield nodes.name, authority
        yield items.name, {"set": tree["key"], "item": authority["key"],
                           "mod_disabled": "false"}
        permission = native["faction_agent_permitted_subtypes"].one(
            faction=HOST, subtype="wh3_main_nur_kugath")
        yield "faction_agent_permitted_subtypes", dict(permission, subtype=subtype)


def dilemmas(native):
    tables = ("cdir_events_dilemma_choice_details",
              "cdir_events_dilemma_option_junctions",
              "cdir_events_dilemma_payloads")
    ids = {name: native[name].column("id") for name in tables
           if "id" in native[name].header}
    for suffix in ("", "_no_leader"):
        source = "wh3_dlc29_chs_archaon_vassalize_chaos_faction" + suffix
        target = PREFIX + "accept" + suffix
        row = native["dilemmas"].one(key=source)
        # Text is authored in the product's Loc asset, not copied from CA.
        yield "dilemmas", dict(row, key=target, localised_description="",
                               localised_title="")
        for table in tables:
            rows = native[table].where(dilemma_key=source)
            if not rows:
                raise ValueError(f"Missing dilemma records: {table}/{source}")
            for row in rows:
                copied = dict(row, dilemma_key=target)
                if "id" in row:
                    copied["id"] = stable_id(target + table + row["id"], ids[table])
                if table == "cdir_events_dilemma_payloads":
                    if row["payload_key"] != "TEXT_DISPLAY":
                        raise ValueError(f"Native dilemma has gameplay payload: {row}")
                    copied["value"] = "LOOKUP[" + PREFIX + row["choice_key"].lower() + "]"
                yield table, copied


def validate(native, generated, assets):
    """Reject new-key collisions and unintended edits to existing skill trees."""
    armies = native["battle_set_piece_armies"]
    original_owner = native["factions"].one(key=client_key("chd"))
    replacement = native["factions"].one(key=HUNT_FACTION)
    if any(replacement[key] != value for key, value in original_owner.items()
           if key not in ("key", "index")):
        raise ValueError("Hunt replacement no longer matches qb3's native faction")
    native["start_pos_factions"].one(faction=HUNT_FACTION, campaign=CAMPAIGN)
    if {row["army_name"] for row in armies.where(faction=client_key("chd"))} != {HUNT_ARMY}:
        raise ValueError("Borrowed Chaos Dwarf faction has other native battles")
    expected = dict(armies.one(army_name=HUNT_ARMY), faction=HUNT_FACTION)
    if generated[armies.name] != [expected]:
        raise ValueError("Hunt adaptation changed more than the enemy faction")
    for row in generated["factions"]:
        if row["key"] not in {client_key(race) for race in CLIENTS}:
            raise ValueError(f"Unintended borrowed faction: {row['key']}")
        original = native["factions"].one(key=row["key"])
        if any(row[key] != value for key, value in original.items()
               if key != "flags_path"):
            raise ValueError(f"Borrowing changed faction gameplay: {row['key']}")
    nodes = native["character_skill_nodes"]
    changed = {row["key"] for row in generated[nodes.name]
               if not row["key"].startswith(PREFIX)}
    sets = {row["set"] for row in native["character_skill_node_set_items"].rows
            if row["item"] in changed}
    owners = native["character_skill_node_sets"]
    if any(row["agent_subtype_key"] not in TARGETS.values()
           for row in owners.rows if row["key"] in sets):
        raise ValueError("Adapted blue line is shared with an unrelated subtype")
    keys = nodes.column("key")
    new_keys = set()
    for row in generated[nodes.name]:
        key = row["key"]
        native["character_skills"].one(key=row["character_skill_key"])
        if key in changed:
            before = nodes.one(key=key)
            if any(row[column] != value for column, value in before.items()
                   if column != "subculture"):
                raise ValueError(f"Unexpected native skill edit: {key}")
        else:
            if key in keys or key in new_keys:
                raise ValueError(f"Skill node collision: {key}")
            if row["faction_key"] != HOST or row["campaign_key"] != CAMPAIGN:
                raise ValueError(f"Unscoped transferred skill: {key}")
            new_keys.add(key)
    keys |= new_keys
    for row in generated["character_skill_node_links"]:
        if row["parent_key"] not in keys or row["child_key"] not in keys:
            raise ValueError(f"Missing skill-link endpoint: {row}")
    for row in generated["character_skill_node_set_items"]:
        owners.one(key=row["set"])
        if row["item"] not in keys:
            raise ValueError(f"Missing skill node: {row}")
    for row in generated["faction_agent_permitted_subtypes"]:
        transferred = (row["faction"] == HOST and row["subtype"] in (
            *TARGETS.values(), DAEMON_FACTION))
        successor = (row["faction"] == DAEMON_FACTION and
                     row["subtype"] == DAEMON_SUCCESSOR)
        if (not (transferred or successor) or row["agent"] != "general"
                or row["mod_disabled"] != "false"):
            raise ValueError(f"Unintended character permission: {row}")
    for race in CLIENTS:
        folder = assets / "ui/flags" / identity_key(race)
        for file in ("mon_24.png", "mon_64.png", "mon_256.png",
                     "mon_64_glow.png", "mon_icon.png", "mon_rotated.png",
                     "mon_banner.dds"):
            if not (folder / file).is_file():
                raise ValueError(f"Missing client flag asset: {folder / file}")


def script_data(native):
    factions = native["factions"]
    cultures = {culture: {"faction": client_key(race), "general": general,
                          "name": "factions_screen_name_" + identity_key(race),
                          "units": dict(zip(UNIT_SLOTS, CHALLENGE_UNITS[race]))}
                for race, (culture, _, general, _) in CLIENTS.items()}
    if not {unit for units in CHALLENGE_UNITS.values() for unit in units} <= native["main_units"].column("unit"):
        raise ValueError("Unknown native challenge unit")
    targets = {}
    for faction, subtype in TARGETS.items():
        row = factions.one(key=faction)
        template = next((culture for culture, source, _, _ in CLIENTS.values()
                         if factions.one(key=source)["subculture"] == row["subculture"]), None)
        if template is None:
            raise ValueError(f"Unsupported target subculture: {faction}")
        targets[faction] = {"subtype": subtype, "culture": template}
    prince = DAEMON_FACTION
    general = DAEMON_SUCCESSOR
    native["agent_subtypes"].one(key=general, auto_generate="false")
    native["faction_agent_permitted_subtypes"].one(
        faction="wh3_dlc29_chaos_invasion_confederation_owner",
        subtype=general, agent="general", mod_disabled="false")
    cultures["wh3_main_dae_daemons"] = {
        "faction": prince, "general": general,
        "units": dict(zip(UNIT_SLOTS, (
            "wh3_main_kho_inf_bloodletters_0", "wh3_main_nur_inf_plaguebearers_0",
            "wh3_main_kho_inf_bloodletters_1", "wh3_main_nur_inf_plaguebearers_1",
            "wh3_main_sla_cav_hellstriders_0", "wh3_main_kho_cav_bloodcrushers_0",
            "wh3_main_nur_mon_beast_of_nurgle_0", "wh3_main_kho_mon_bloodthirster_0",
            "wh3_main_tze_mon_lord_of_change_0")))}
    if not set(cultures["wh3_main_dae_daemons"]["units"].values()) <= native["main_units"].column("unit"):
        raise ValueError("Unknown Daemon Prince challenge unit")
    targets[prince] = {"subtype": prince, "culture": "wh3_main_dae_daemons",
                      "keep_faction": True}
    return {"targets": targets, "cultures": cultures,
            "dilemma": PREFIX + "accept"}
