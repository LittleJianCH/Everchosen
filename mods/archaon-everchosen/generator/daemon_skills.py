"""Owner-gated paths inside Daniel's existing skill tree.

A transferred character can retain the node set selected at creation. Keep
both paths in that set, using node eligibility as native cross-culture lines
do, rather than relying on selection of a different faction-specific set.
"""
import skill_slots

HOST = "wh_main_chs_chaos"
CAMPAIGN = "wh3_main_combi"
PRINCE = "wh3_main_dae_daemon_prince"
DAEMON_SUBCULTURE = "wh3_main_sc_dae_daemons"
PREFIX = "everchosen_daemon_skill_"
TREE = "everchosen_daemon_skill_tree"
NODE = "wh3_main_skill_node_dae_daemon_prince_"
REPLACED = (
    "khorne_1_4", "khorne_4", "nurgle_1_4", "nurgle_4",
    "slaanesh_1_2", "slaanesh_1_4", "slaanesh_4",
    "tzeentch_1_1", "tzeentch_1_4", "tzeentch_3_1", "tzeentch_4",
    "undivided_1_1", "undivided_1_2", "undivided_1_3", "undivided_1_4",
)
TABLES = """character_skill_level_to_effects_junctions
    character_skill_nodes_skill_locks character_skill_nodes
    character_skill_node_sets character_skill_node_set_items effects
""".split() + skill_slots.TABLES


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
    nodes = native["character_skill_nodes"]
    members = native["character_skill_node_set_items"].where(set=tree["key"])
    changed = {NODE + suffix: PREFIX + suffix for suffix in REPLACED}
    active = [nodes.one(key=r["item"]) for r in members
              if r["mod_disabled"] == "false"]
    if not set(changed) <= {r["key"] for r in active}:
        raise ValueError("Native Daniel skill membership changed")
    mapping = skill_slots.linked_nodes(native, active, changed, TREE + "_")
    for key, replacement in mapping.items():
        original = nodes.one(key=key)
        if any(original[field] for field in (
                "campaign_key", "faction_key", "subculture")):
            raise ValueError("Native Daniel skill eligibility changed: " + key)
        yield nodes.name, dict(original, subculture=DAEMON_SUBCULTURE)
        yield nodes.name, dict(
            original, key=replacement,
            character_skill_key=changed.get(key, original["character_skill_key"]),
            faction_key=HOST, campaign_key=CAMPAIGN, subculture="")
        yield "character_skill_node_set_items", dict(
            set=tree["key"], item=replacement, mod_disabled="false")
    yield from skill_slots.links(native, mapping)
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
        node = nodes[TREE + "_" + NODE + suffix]
        if (key not in skills or node["faction_key"] != HOST or
                node["character_skill_key"] != key):
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
    tree = native["character_skill_node_sets"].one(
        agent_subtype_key=PRINCE, faction_key="", subculture="", campaign_key="")
    changed = native_keys & nodes.keys()
    owners = {r["set"] for r in native["character_skill_node_set_items"].rows
              if r["item"] in changed}
    if owners != {tree["key"]}:
        raise ValueError("Adapted prince path is shared with another tree")
    for key in changed:
        original = native["character_skill_nodes"].one(key=key)
        if nodes[key] != dict(original, subculture=DAEMON_SUBCULTURE):
            raise ValueError("Unexpected native prince skill edit: " + key)
        replacement = nodes[TREE + "_" + key]
        if any(replacement[field] != original[field] for field in (
                "indent", "tier", "required_num_parents", "points_on_creation")):
            raise ValueError("Prince skill position or requirements changed")
        if (replacement["faction_key"] != HOST or
                replacement["campaign_key"] != CAMPAIGN or
                replacement["subculture"]):
            raise ValueError("Unscoped prince skill path")
    members = generated["character_skill_node_set_items"]
    if (generated.get("character_skill_node_sets") or
            {r["set"] for r in members} != {tree["key"]} or
            {r["item"] for r in members} != nodes.keys() - native_keys):
        raise ValueError("Prince rewards must belong to the existing tree")
    endpoints = native_keys | nodes.keys()
    for row in generated.get("character_skill_node_links", []):
        if row["parent_key"] not in endpoints or row["child_key"] not in endpoints:
            raise ValueError("Missing prince skill-link endpoint")
