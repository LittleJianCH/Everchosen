"""Derive lord adaptations and reuse dormant Immortal Empires factions."""
from db_tables import stable_id
import skill_slots
import blue_skills

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
    character_skill_level_to_effects_junctions character_skill_nodes_skill_locks
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


def original_tree(native, subtype):
    tree = native["character_skill_node_sets"].one(
        agent_subtype_key=subtype, faction_key="", subculture="", campaign_key="")
    members = native["character_skill_node_set_items"].where(set=tree["key"])
    nodes = [native["character_skill_nodes"].one(key=r["item"])
             for r in members if r["mod_disabled"] == "false"]
    return tree, members, nodes


def skill_mapping(native):
    levels = native["character_skill_level_to_effects_junctions"]
    result = {}
    for subtype in TARGETS.values():
        _, _, original = original_tree(native, subtype)
        pairs = []
        for row in original:
            source = row["character_skill_key"]
            if row["indent"] == "5" and source in blue_skills.ADAPTATIONS:
                maximum = max(int(r["level"]) for r in
                              levels.where(character_skill_key=source))
                pairs.append((row, dict(row, character_skill_key=blue_skills.key(source)),
                              maximum))
        result[subtype] = skill_slots.mapping(
            native, pairs, [r for r in original if r["indent"] != "5"])
    return result


def skills(native):
    yield from blue_skills.rows(native)
    nodes = native["character_skill_nodes"]
    for subtype in TARGETS.values():
        tree, members, original = original_tree(native, subtype)
        tree_key = PREFIX + subtype + "_skills"
        yield "character_skill_node_sets", dict(
            tree, key=tree_key, faction_key=HOST, campaign_key=CAMPAIGN)
        replacements = {r["key"]: PREFIX + r["key"] for r in original
                        if r["indent"] == "5" and
                        r["character_skill_key"] in blue_skills.ADAPTATIONS}
        for row in original:
            if row["key"] in replacements:
                yield nodes.name, dict(
                    row, key=replacements[row["key"]], faction_key=HOST,
                    campaign_key=CAMPAIGN, subculture="",
                    character_skill_key=blue_skills.key(row["character_skill_key"]))
        for row in members:
            yield "character_skill_node_set_items", dict(
                row, set=tree_key, item=replacements.get(row["item"], row["item"]))
        for row in native["character_skill_node_links"].rows:
            if row["parent_key"] in replacements or row["child_key"] in replacements:
                yield "character_skill_node_links", dict(
                    row, parent_key=replacements.get(row["parent_key"], row["parent_key"]),
                    child_key=replacements.get(row["child_key"], row["child_key"]))
        changed_skills = {r["character_skill_key"] for r in original
                          if r["key"] in replacements}
        if any(r["character_skill_node"] in replacements or
               r["character_skill"] in changed_skills for r in
               native["character_skill_nodes_skill_locks"].rows):
            raise ValueError("Native blue-line locks require explicit adaptation")
        authority = nodes.one(key="wh3_dlc20_skill_node_chs_lord_authority")
        authority.update(key=PREFIX + subtype + "_authority",
                         campaign_key=CAMPAIGN, faction_key=HOST, subculture="",
                         tier=str(max(int(r["tier"]) for r in original
                                      if r["indent"] == "0") + 1))
        yield nodes.name, authority
        yield "character_skill_node_set_items", {
            "set": tree_key, "item": authority["key"], "mod_disabled": "false"}
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
    native_keys = nodes.column("key")
    new_nodes = generated[nodes.name]
    keys = native_keys | {r["key"] for r in new_nodes}
    skills = native["character_skills"].column("key") | {
        r["key"] for r in generated.get("character_skills", [])}
    owners = native["character_skill_node_sets"]
    new_sets = {r["key"]: r for r in generated.get(owners.name, [])}
    for row in new_sets.values():
        if (row["faction_key"] != HOST or row["campaign_key"] != CAMPAIGN
                or row["agent_subtype_key"] not in TARGETS.values()
                or row["key"] in owners.column("key")):
            raise ValueError("Unscoped transferred skill tree")
    for row in new_nodes:
        if (row["key"] in native_keys or row["character_skill_key"] not in skills
                or row["faction_key"] != HOST or row["campaign_key"] != CAMPAIGN):
            raise ValueError("Unscoped or invalid transferred skill node")
    for row in generated["character_skill_node_links"]:
        if row["parent_key"] not in keys or row["child_key"] not in keys:
            raise ValueError(f"Missing skill-link endpoint: {row}")
    for row in generated["character_skill_node_set_items"]:
        if row["set"] not in new_sets or row["item"] not in keys:
            raise ValueError(f"Missing transferred skill membership: {row}")
    changed_nodes = {r["key"]: r for r in new_nodes}
    for subtype in TARGETS.values():
        _, members, original = original_tree(native, subtype)
        expected = {(r["item"], r["mod_disabled"]) for r in members}
        for row in original:
            if row["indent"] == "5" and row["character_skill_key"] in blue_skills.ADAPTATIONS:
                replacement = changed_nodes[PREFIX + row["key"]]
                if replacement != dict(
                        row, key=PREFIX + row["key"], faction_key=HOST,
                        campaign_key=CAMPAIGN, subculture="",
                        character_skill_key=blue_skills.key(row["character_skill_key"])):
                    raise ValueError("Adapted skill moved or changed prerequisites")
                expected.remove((row["key"], "false"))
                expected.add((replacement["key"], "false"))
        expected.add((PREFIX + subtype + "_authority", "false"))
        actual = {(r["item"], r["mod_disabled"]) for r in
                  generated["character_skill_node_set_items"]
                  if r["set"] == PREFIX + subtype + "_skills"}
        if actual != expected:
            raise ValueError("Adapted tree changed unrelated skill membership")
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
