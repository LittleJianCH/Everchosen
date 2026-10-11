"""Derive Archaon's inherited mechanic assets from the installed WH3 data.

Only content that follows the native data is generated: DB rows copied from
native records, the adapted native UI, and the ritual and portal-node lists
the campaign script reads. Fixed rows and localization are authored under
assets/ and checked here against the native tables.

The tables below state what is copied; the functions after them hold the few
derivations that need a lookup. Native extracts stay outside source control.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MOD.parents[1] / "tools"))
from db_tables import (read_authored, read_table, run_generator, stable_id,
                       write_table)
import subjugation
import daemon_prince
import daemon_legion
import daemon_skills
import blue_skills
import skill_slots

PREFIX = "everchosen_inheritance_"
FRAGMENT = PREFIX + "data"
HOST = "wh_main_chs_chaos"

# Native owners of the inherited mechanics.
FESTUS = "wh3_dlc20_feature_festus"
VILITCH = "wh3_dlc20_feature_vilitch"
BELAKOR = "wh3_main_feature_belakor"
MANIFESTATION_USES = [f"wh3_main_ritual_belakor_gg_{i}_uses" for i in range(1, 5)]
INFECTION_INCOME = "wh3_main_effect_dae_nurgle_points_percentage_multiplier_mod"
NETWORK = "wh3_main_teleportation_network_belakor"
NODE_TEMPLATE = "wh3_main_teleportation_node_template_belakor"
PORTAL_LORDS = ("wh_main_chs_archaon", "wh3_main_dae_belakor")

# Keys this mod introduces.
NUR_UNLOCKED = PREFIX + "unlocked_nur"  # 0/1 resource read by DB criteria
INFECTION_LOCK = PREFIX + "infection_reduction"

# One native row copied with some fields replaced: table, native row, changes.
COPIED_ROWS = (
    ("pooled_resources", {"key": MANIFESTATION_USES[0]},
     {"key": NUR_UNLOCKED, "maximum": "1", "minimum": "0",
      "optional_icon_path": ""}),
    ("pooled_resource_factor_junctions",
     {"resource": MANIFESTATION_USES[0], "factor": "other"},
     {"unique_id": NUR_UNLOCKED, "resource": NUR_UNLOCKED}),
    # Resource balances exist from campaign creation; ritual access starts locked.
    ("campaign_group_pooled_resources",
     {"campaign_group": BELAKOR, "resource": MANIFESTATION_USES[0]},
     {"campaign_group": PREFIX + "host", "resource": NUR_UNLOCKED}),
    # Cancels infection income until the Nurgle mechanic is earned.
    ("effects", {"effect": INFECTION_INCOME},
     {"effect": INFECTION_LOCK, "icon": "", "icon_negative": "",
      "priority": "0"}),
    ("effect_bonus_value_pooled_resource_junctions",
     {"effect": INFECTION_INCOME, "bonus_value_id": "percentage_multiplier_mod"},
     {"effect": INFECTION_LOCK, "pooled_resource": "wh3_main_nur_infections"}),
    ("effect_bonus_value_pooled_resource_junctions",
     {"effect": INFECTION_INCOME, "bonus_value_id":
      "post_battle_captivity_outcome_pooled_resource_percentage_mod"},
     {"effect": INFECTION_LOCK, "pooled_resource": "wh3_main_nur_infections"}),
    ("campaign_stance_effects_junctions",
     {"stance": "MILITARY_FORCE_ACTIVE_STANCE_TYPE_TUNNELING",
      "faction": "wh3_dlc20_chs_vilitch"}, {"faction": HOST}),
    ("ui_features_to_factions",
     {"faction": "wh3_dlc20_chs_festus", "ui_feature": "NURGLE_PLAGUES"},
     {"faction": HOST}),
    ("ui_features_to_factions",
     {"faction": "wh3_dlc20_chs_vilitch", "ui_feature": "CHANGING_OF_WAYS"},
     {"faction": HOST}),
) + subjugation.COPIED_ROWS

# Every row of a native campaign group copied to one of ours:
# table, native group, our group, changes.
LOCKED = {"initially_unlocked": "false"}
COPIED_GROUPS = (
    ("campaign_group_rituals", FESTUS, "nur", LOCKED),
    ("campaign_group_rituals", VILITCH, "tze", LOCKED),
    ("campaign_group_rituals", BELAKOR, "gg", LOCKED),
    ("campaign_group_plague_component_setup_sets", FESTUS, "nur", {}),
    ("campaign_group_faction_plague_setup_sets",
     "nurgle_plague_festus_faction", "nur", {}),
    ("campaign_group_settlement_occupation_looted_pooled_resources",
     FESTUS, "nur_active", {}),
    ("campaign_group_diplomatic_manipulation_category_junctions",
     VILITCH, "tze", {}),
    ("campaign_group_streak_sets", "wh3_dlc20_valkia_win_streak", "kho", {}),
)

# Pooled resources each mechanic inherits, starting empty: native starting
# values are not inherited rewards.
INHERITED_RESOURCES = {
    "nur": (FESTUS, {"wh3_main_nur_infections"}),
    "tze": (VILITCH, {"wh3_main_tze_winds_of_magic_manipulation"}),
    "gg": (BELAKOR, set(MANIFESTATION_USES)),
}

# The champion whose native vassal relationship defines each god's blessing.
BLESSING_CHAMPIONS = {"sla": "azazel", "nur": "festus", "kho": "valkia",
                      "tze": "vilitch"}

# Native records the campaign script relies on without changing them.
REQUIRED_FEATURES = {"bribery", "streaks", "diplomatic_manipulation",
                     "not_intercepted_on_tunneling", "tunnel_attack_is_ambush"}
REQUIRED_PLAGUE_SETS = (("plague_effect_set_nurgle_positive", "false"),
                        ("plague_effect_set_nurgle_negative", "true"))

TABLES = sorted(set(subjugation.TABLES) | set(daemon_prince.TABLES) |
                set(daemon_skills.TABLES) | {table for table, *_ in COPIED_ROWS + COPIED_GROUPS} | set("""
    campaign_groups campaign_group_members
    campaign_group_member_criteria_factions
    campaign_group_member_criteria_campaigns
    campaign_group_member_criteria_pooled_resources
    campaign_group_member_criteria_numeric_ranges
    effect_bundles effect_bundles_to_effects_junctions
    campaign_effect_scopes campaign_features rituals faction_set_items
    teleportation_networks teleportation_network_nodes
    diplomatic_relationship_effects campaign_effect_list_effect_junctions
    campaign_payload_ui_details
""".split()))
UI_FOLDER = "ui/campaign ui"
NATIVE_INPUTS = {
    "db.pack": [f"db/{name}_tables" for name in TABLES],
    "ui3.pack": [f"{UI_FOLDER}/{name}.twui.xml" for name in (
        "hud_campaign", "hud_campaign_resource_bar_wh3", "great_game_rituals",
        "rifts")] + [daemon_prince.ui_path(name)
                     for name in daemon_prince.UI_NAMES] +
        ["ui/templates/square_medium_text_button.twui.xml"],
    # Loaded by the adapter regressions, not by this generator.
    "data_script.pack": ["script/campaign/wh3_campaign_nurgle_plagues.lua",
                         "script/campaign/wh3_campaign_great_game.lua",
                         "script/campaign/wh3_dlc29_archaon_subjugation.lua"],
}


### DB rows

def copied_rows(native):
    for table, match, changes in COPIED_ROWS:
        yield table, dict(native[table].one(**match), **changes)


def copied_groups(native):
    for table, source, target, changes in COPIED_GROUPS:
        rows = native[table].where(campaign_group=source)
        if not rows:
            raise ValueError(f"Missing native configuration: {table}/{source}")
        for row in rows:
            yield table, dict(row, campaign_group=PREFIX + target, **changes)


def inherited_resources(native):
    table = native["campaign_group_pooled_resources"]
    for god, (source, resources) in INHERITED_RESOURCES.items():
        rows = [row for row in table.where(campaign_group=source)
                if row["resource"] in resources]
        if {row["resource"] for row in rows} != resources:
            raise ValueError(f"Missing mechanic resources: {god}")
        for row in rows:
            yield table.name, dict(row, campaign_group=PREFIX + god,
                                   initial_amount="0")


def blessing_bundle(god):
    return PREFIX + "vassal_" + god


def vassal_blessings(native):
    """Each champion's native vassal effects, as effects of our bundle."""
    for god, champion in BLESSING_CHAMPIONS.items():
        relation = native["diplomatic_relationship_effects"].one(
            diplomatic_stance="vassal", faction_set="all",
            faction_set_relation_with="faction_set_" + champion)
        effects = native["campaign_effect_list_effect_junctions"].where(
            effect_list=relation["campaign_effect_list"])
        if not effects:
            raise ValueError(f"Missing native vassal blessing: {champion}")
        for row in effects:
            yield "effect_bundles_to_effects_junctions", {
                "effect_bundle_key": blessing_bundle(god),
                "effect_key": row["effect"], "effect_scope": row["scope"],
                "value": f"{float(row['value']):.4f}",
                "advancement_stage": "start_turn_completed"}


def portal_permission(native):
    """Admit the host to the faction set that may travel Be'lakor's network."""
    network = native["teleportation_networks"].one(
        key=NETWORK, campaign="wh3_main_combi", permitted_agents="all_agents")
    members = native["faction_set_items"]
    belakor = members.one(faction="wh3_main_chs_shadow_legion", remove="false",
                          set=network["traveller_requirements"])
    if members.where(faction=HOST, set=belakor["set"]):
        raise ValueError("Archaon portal permission overlaps a native row")
    new_id = stable_id(PREFIX + "portal_permission", members.column("id"))
    yield members.name, dict(belakor, faction=HOST, id=new_id)


def generated_rows(native):
    """Rows by table, without duplicates, each matching the native layout."""
    result = {}
    for derive in (copied_rows, copied_groups, inherited_resources,
                   vassal_blessings, portal_permission,
                   subjugation.client_factions,
                   subjugation.skills,
                   subjugation.dilemmas, daemon_prince.rows, daemon_legion.rows):
        for table, row in derive(native):
            if set(row) != set(native[table].header):
                raise ValueError(f"Unexpected fields for {table}: {sorted(row)}")
            rows = result.setdefault(table, [])
            if row not in rows:
                rows.append(row)
    return result


def validate(native, generated, authored):
    """Check references against current native records, not just serialization."""
    def ours(table, column):
        return {row[column] for row in
                authored.get(table, []) + generated.get(table, [])}

    effects = native["effects"].column("effect") | ours("effects", "effect")
    scope_table = native["campaign_effect_scopes"]
    scopes = scope_table.column(scope_table.header[0])
    bundles = ours("effect_bundles", "key")
    junctions = "effect_bundles_to_effects_junctions"
    for row in authored.get(junctions, []) + generated[junctions]:
        if row["effect_key"] not in effects or row["effect_scope"] not in scopes:
            raise ValueError(f"Invalid effect/scope: {row}")
        if row["effect_bundle_key"] not in bundles:
            raise ValueError(f"Effect for an unauthored bundle: {row}")
    # Authored groups and criteria must line up with the generated rows.
    groups = ours("campaign_groups", "id")
    for table, rows in generated.items():
        for row in rows:
            if "campaign_group" in row and row["campaign_group"] not in groups:
                raise ValueError(f"{table}: unauthored group {row['campaign_group']}")
    resources = ours("pooled_resources", "key")
    for row in authored.get("campaign_group_member_criteria_pooled_resources", []):
        if row["pooled_resource"] not in resources:
            raise ValueError(f"Criterion for a missing resource: {row}")
    if not ours("campaign_group_rituals", "ritual") <= (native["rituals"].column("key") | ours("rituals", "key")):
        raise ValueError("Unknown inherited ritual")
    if not REQUIRED_FEATURES <= native["campaign_features"].column("feature"):
        raise ValueError("Unknown inherited faction feature")
    for set_key, excluded in REQUIRED_PLAGUE_SETS:
        native["faction_set_items"].one(faction=HOST, set=set_key, remove=excluded)


### Script data

def script_data(native, generated):
    """The native-derived lists the Fennel adapter reads at campaign start."""
    nodes = [row["key"] for row in native["teleportation_network_nodes"].where(
        network=NETWORK, template=NODE_TEMPLATE)]
    if not nodes or len(nodes) != len(set(nodes)):
        raise ValueError("Missing or ambiguous Be'lakor network nodes")
    data = {god: [row["ritual"] for row in generated["campaign_group_rituals"]
                  if row["campaign_group"] == PREFIX + god]
            for god in ("nur", "tze", "gg")}
    data["blessings"] = {god: blessing_bundle(god) for god in BLESSING_CHAMPIONS}
    data["portals"] = {"network": NETWORK, "template": NODE_TEMPLATE,
                       "nodes": {key: True for key in nodes}}
    data["subjugation"] = subjugation.script_data(native)
    data["subjugation"]["skill_slots"] = {
        **subjugation.skill_mapping(native),
        daemon_skills.PRINCE: daemon_skills.skill_mapping(native)}
    data["daemon_prince"] = daemon_prince.script_data(native)
    return data


def lua_literal(value):
    """Serialize strings, booleans, lists, and string-keyed dicts as Lua."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = (value.replace("\\", "\\\\").replace('"', '\\"')
                   .replace("\n", "\\n"))
        return f'"{escaped}"'
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua_literal(key)}]={lua_literal(item)}"
                              for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    raise TypeError(f"No Lua literal for {type(value).__name__}")


### Native UI
#
# Each adaptation yields (element, new expression) pairs. Only the
# context_function_id of those elements changes; an anchor that is missing or
# no longer unique stops the build.

EXPRESSION = "context_function_id"
PLAYER = "PlayersFaction.FactionRecordContext.Key"


def unlocked(god):
    return f'ScriptObjectContext("{PREFIX}ui_{god}").NumericValue == 1'


def control(tree, control_id):
    found = tree.findall(f'.//*[@id="{control_id}"]')
    if len(found) != 1:
        raise ValueError(f"UI control changed: {control_id}")
    return found[0]


def hide_until_unlocked(tree, controls):
    """Hide each control from the host until its god's mechanic is unlocked."""
    for control_id, god in controls.items():
        callbacks = control(tree, control_id).findall(
            './/callback_with_context[@callback_id="ContextVisibilitySetter"]')
        if not callbacks:
            raise ValueError(f"UI visibility anchor missing: {control_id}")
        for callback in callbacks:
            yield callback, (f'({callback.get(EXPRESSION)}) && '
                             f'({PLAYER} != "{HOST}" || {unlocked(god)})')


def share_manifestations(tree):
    """Show Be'lakor's manifestation panel to the host once unlocked."""
    owner = f'{PLAYER} == "wh3_main_chs_shadow_legion"'
    anchors = [element for element in tree.iter()
               if owner in element.get(EXPRESSION, "")]
    if len(anchors) != 1:
        raise ValueError("Manifestation UI anchor changed")
    shared = f'({owner} || ({PLAYER} == "{HOST}" && {unlocked("gg")}))'
    yield anchors[0], anchors[0].get(EXPRESSION).replace(owner, shared)


def restrict_rifts(tree):
    """In the host faction, only the portal lords may use Be'lakor's rifts."""
    exemptions = [
        f'CharacterContext.FactionContext.FactionRecordContext.Key != "{HOST}"',
        f'InteractingNodeContext.TeleportationTemplateContext.Key != "{NODE_TEMPLATE}"',
        *(f'CharacterContext.AgentSubtypeRecordContext.Key == "{lord}"'
          for lord in PORTAL_LORDS)]
    allowed = "(" + " || ".join(exemptions) + ")"
    gates = {"ContextInactiveStateSetter": "{allowed} && ({native})",
             "ContextCommandLeftClick": "DoIf({allowed}, {native})"}
    for control_id in ("button_enter_rift", "teleport_rift",
                       "button_teleport_confirm"):
        for kind, gate in gates.items():
            callbacks = control(tree, control_id).findall(
                f'callbacks_with_context/callback_with_context[@callback_id="{kind}"]')
            if (len(callbacks) != 1 or callbacks[0].get("context_object_id")
                    != "CcoCampaignCharacterTeleportationSystem"):
                raise ValueError(f"Rift callback changed: {control_id}/{kind}")
            native = callbacks[0].get(EXPRESSION)
            yield callbacks[0], gate.format(allowed=allowed, native=native)


UI_ADAPTATIONS = {
    "hud_campaign": lambda tree: hide_until_unlocked(tree, {
        "button_nurgle_plagues": "nur", "button_changing_of_the_ways": "tze",
        "button_great_game_rituals": "gg"}),
    "hud_campaign_resource_bar_wh3": lambda tree: hide_until_unlocked(tree, {
        "nurgle_infections_holder": "nur", "dae_ascendant_race_holder": "gg"}),
    "great_game_rituals": share_manifestations,
    "rifts": restrict_rifts,
}


def adapt_ui(native_root, output, native):
    for name in (*UI_ADAPTATIONS, *daemon_prince.UI_NAMES):
        relative = (daemon_prince.ui_path(name) if name in daemon_prince.UI_NAMES
                    else f"{UI_FOLDER}/{name}.twui.xml")
        tree = ET.parse(native_root / relative)
        if name in UI_ADAPTATIONS:
            for element, expression in list(UI_ADAPTATIONS[name](tree)):
                element.set(EXPRESSION, expression)
        else:
            daemon_prince.adapt(tree, name, native_root, native)
        (output / relative).parent.mkdir(parents=True, exist_ok=True)
        tree.write(output / relative, encoding="utf-8", xml_declaration=True)


### Entry point

def generate(native_root, output):
    native = {name: read_table(native_root / "db", name) for name in TABLES}
    authored = read_authored(MOD / "assets/db", native)
    generated = generated_rows(native)
    subjugation.validate(native, generated, MOD / "assets")
    blue_skills.validate(native, generated, authored)
    prince_tree = {}
    for table, row in daemon_skills.rows(native):
        prince_tree.setdefault(table, []).append(row)
    daemon_skills.validate(native, prince_tree, authored)
    for table, rows in prince_tree.items():
        generated.setdefault(table, []).extend(rows)
    skill_slots.validate_trees(native, generated)
    validate(native, generated, authored)
    daemon_legion.validate(native, generated, authored)
    for table, rows in generated.items():
        write_table(output, native[table], rows, FRAGMENT)
    adapt_ui(native_root, output, native)
    path = output / "script/campaign/mod/everchosen_inheritance_data.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('core:add_static_object("everchosen_inheritance_data", '
                    + lua_literal(script_data(native, generated)) + ")\n",
                    encoding="utf-8")
    print(f"Inheritance: {sum(map(len, generated.values()))} generated rows "
          f"across {len(generated)} tables; "
          f"{len(UI_ADAPTATIONS) + len(daemon_prince.UI_NAMES)} native UI "
          "adaptations")


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
