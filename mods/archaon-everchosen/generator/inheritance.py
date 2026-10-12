"""Native-derived resources, blessings, portals and UI for inherited mechanics."""
import xml.etree.ElementTree as ET

from db_tables import stable_id
import subjugation

PREFIX = "everchosen_inheritance_"
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
)

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

TABLES = """
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
""".split() + [table for table, *_ in COPIED_ROWS + COPIED_GROUPS]

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


def rows(native):
    for derive in (copied_rows, copied_groups, inherited_resources,
                   vassal_blessings, portal_permission):
        yield from derive(native)


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


def script_data(native):
    """The native-derived lists the Fennel adapter reads at campaign start."""
    nodes = [row["key"] for row in native["teleportation_network_nodes"].where(
        network=NETWORK, template=NODE_TEMPLATE)]
    if not nodes or len(nodes) != len(set(nodes)):
        raise ValueError("Missing or ambiguous Be'lakor network nodes")
    rituals = [row for table, row in copied_groups(native)
               if table == "campaign_group_rituals"]
    data = {god: [row["ritual"] for row in rituals
                  if row["campaign_group"] == PREFIX + god]
            for god in ("nur", "tze", "gg")}
    data["blessings"] = {god: blessing_bundle(god) for god in BLESSING_CHAMPIONS}
    data["portals"] = {"network": NETWORK, "template": NODE_TEMPLATE,
                       "nodes": {key: True for key in nodes}}
    return data


### Native UI
#
# Each adaptation yields (element, new expression) pairs. The portrait adapter
# also anchors its native Seafang holder; other adaptations only replace
# expressions. Missing or ambiguous anchors stop the build.

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


def raise_seafang(tree):
    """Keep Seafang above the authority dial for Archaon's Wulfrik."""
    holder = control(tree, "dlc27_seafang_teleport_holder")
    if (holder.get("offset") != "12.00,-30.00"
            or holder.get("docking") is not None):
        raise ValueError("Seafang's native portrait anchor changed")
    callbacks = holder.find("callbackwithcontextlist")
    if callbacks is None:
        raise ValueError("Seafang's native callbacks are missing")
    holder.set("docking", "Top Left")
    holder.set("dock_offset", holder.get("offset"))
    holder.set("component_anchor_point", "0.00,0.00")
    scope = (
        f'{PLAYER} == "{HOST}" && IsContextValid(SelectedCharacter) && '
        f'SelectedCharacter.FactionContext.FactionRecordContext.Key == "{HOST}" '
        f'&& SelectedCharacter.AgentSubtypeRecordContext.Key == '
        f'"{subjugation.WULFRIK}"')
    # WH3 9.0.3: the authority icons extend above their 160px holder, while
    # Seafang's frame extends 101px below its origin. Leave room for both frames.
    # Absolute dock offsets also avoid drift when selection/visibility repeats.
    expression = f'self.SetDockOffset(12, GetIfElse({scope}, -270, -30))'
    for kind in ("ContextCommandGiverOnVisibilityChanged", "ContextCommandEvent"):
        callback = ET.SubElement(callbacks, "callback_with_context",
                                 callback_id=kind)
        if kind == "ContextCommandEvent":
            properties = ET.SubElement(callback, "child_m_user_properties")
            for index, event in enumerate(("CampaignSelectionChanged",
                                           "RitualComplete")):
                ET.SubElement(properties, "property", name=f"event{index}",
                              value=event)
        yield callback, expression


_EXPRESSION_ADAPTERS = {
    "hud_campaign": lambda tree: hide_until_unlocked(tree, {
        "button_nurgle_plagues": "nur", "button_changing_of_the_ways": "tze",
        "button_great_game_rituals": "gg"}),
    "hud_campaign_resource_bar_wh3": lambda tree: hide_until_unlocked(tree, {
        "nurgle_infections_holder": "nur", "dae_ascendant_race_holder": "gg"}),
    "great_game_rituals": share_manifestations,
    "rifts": restrict_rifts,
    "character_information": raise_seafang,
}


def adapt_expressions(tree, derive):
    for element, expression in list(derive(tree)):
        element.set(EXPRESSION, expression)


UI_ADAPTATIONS = {
    f"ui/campaign ui/{name}.twui.xml":
        (lambda tree, native_root, native, derive=derive:
         adapt_expressions(tree, derive))
    for name, derive in _EXPRESSION_ADAPTERS.items()
}
