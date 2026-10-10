"""An Archaon-only variant of Daniel's tree; native trees remain intact.

WH3 9.0.3 uses faction-specific node sets for Aislinn/Avelorn handmaidens
alongside a generic subtype set. Apply that same selection contract here.
"""
import skill_slots

HOST = "wh_main_chs_chaos"
CAMPAIGN = "wh3_main_combi"
PRINCE = "wh3_main_dae_daemon_prince"
PREFIX = "everchosen_daemon_skill_"
TREE = "everchosen_daemon_skill_tree"
NODE = "wh3_main_skill_node_dae_daemon_prince_"
REPLACED = (
    "khorne_1_4", "khorne_4", "nurgle_1_4", "nurgle_4",
    "slaanesh_1_2", "slaanesh_1_4", "slaanesh_4",
    "tzeentch_1_1", "tzeentch_1_4", "tzeentch_3_1", "tzeentch_4",
    "undivided_1_1", "undivided_1_2", "undivided_1_3", "undivided_1_4",
)
TABLES = ["character_skill_level_to_effects_junctions",
          "character_skill_nodes_skill_locks"]


def skill_mapping(native):
    pairs = []
    levels = native["character_skill_level_to_effects_junctions"]
    for suffix in REPLACED:
        old = native["character_skill_nodes"].one(key=NODE + suffix)
        new = dict(old, character_skill_key=PREFIX + suffix)
        maximum = max(int(r["level"]) for r in levels.where(
            character_skill_key=old["character_skill_key"]))
        pairs.append((old, new, maximum))
    return skill_slots.mapping(native, pairs)


def rows(native):
    tree = native["character_skill_node_sets"].one(
        agent_subtype_key=PRINCE, faction_key="", subculture="", campaign_key="")
    yield "character_skill_node_sets", dict(
        tree, key=TREE, faction_key=HOST, campaign_key=CAMPAIGN)
    nodes = native["character_skill_nodes"]
    mapping = {NODE + suffix: PREFIX + suffix for suffix in REPLACED}
    members = native["character_skill_node_set_items"].where(set=tree["key"])
    if not set(mapping) <= {r["item"] for r in members}:
        raise ValueError("Native Daniel skill membership changed")
    for member in members:
        key = member["item"]
        yield "character_skill_node_set_items", dict(
            member, set=TREE, item=mapping.get(key, key))
        if key in mapping:
            yield nodes.name, dict(
                nodes.one(key=key), key=mapping[key],
                character_skill_key=mapping[key], faction_key=HOST,
                campaign_key=CAMPAIGN, subculture="")
    for link in native["character_skill_node_links"].rows:
        if link["parent_key"] in mapping or link["child_key"] in mapping:
            yield "character_skill_node_links", dict(
                link, parent_key=mapping.get(link["parent_key"], link["parent_key"]),
                child_key=mapping.get(link["child_key"], link["child_key"]))
    # Native Daniel has no locks involving these nodes/skills in 9.0.3.
    # Fail on a new lock rather than silently dropping a future prerequisite.
    skills = {nodes.one(key=key)["character_skill_key"] for key in mapping}
    if any(r["character_skill_node"] in mapping or r["character_skill"] in skills
           for r in native["character_skill_nodes_skill_locks"].rows):
        raise ValueError("New native Daniel skill locks require adaptation")


def validate(native, generated, authored):
    nodes = {r["key"]: r for r in generated["character_skill_nodes"]}
    skills = {r["key"] for r in authored["character_skills"]}
    effects = native["effects"].column("effect") | {
        r["effect"] for r in authored["effects"]}
    levels = authored["character_skill_level_to_effects_junctions"]
    for suffix in REPLACED:
        key = PREFIX + suffix
        if key not in skills or nodes[key]["faction_key"] != HOST:
            raise ValueError("Unscoped or missing prince skill: " + key)
        original = native["character_skill_nodes"].one(key=NODE + suffix)
        old_levels = {r["level"] for r in
                      native["character_skill_level_to_effects_junctions"].where(
                          character_skill_key=original["character_skill_key"])}
        if {r["level"] for r in levels if r["character_skill_key"] == key} != old_levels:
            raise ValueError("Prince skill point cost changed: " + key)
    for row in levels:
        if row["character_skill_key"].startswith(PREFIX):
            if row["effect_key"] not in effects or row["effect_scope"] != "general_to_force_own":
                raise ValueError("Invalid prince army skill: " + str(row))
    native_keys = native["character_skill_nodes"].column("key")
    if native_keys & nodes.keys():
        raise ValueError("Prince variant unexpectedly edits native nodes")
    endpoints = native_keys | nodes.keys()
    for row in generated.get("character_skill_node_links", []):
        if row["parent_key"] not in endpoints or row["child_key"] not in endpoints:
            raise ValueError("Missing prince skill-link endpoint")
