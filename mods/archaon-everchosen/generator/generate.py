"""Derive Archaon's inherited mechanic assets from the installed WH3 data.

Native extracts stay outside source control. No Workshop code or prototype
assets are inputs. Refuse missing/undecoded tables and changed UI anchors.
"""
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from db_tables import read_table, write_table, run_generator

PREFIX = "everchosen_inheritance_"
HOST = "wh_main_chs_chaos"
NETWORK = "wh3_main_teleportation_network_belakor"
NODE_TEMPLATE = "wh3_main_teleportation_node_template_belakor"
PORTAL_LORDS = ("wh_main_chs_archaon", "wh3_main_dae_belakor")
BLESSINGS = {"sla": ("azazel", "色孽"), "nur": ("festus", "纳垢"),
             "kho": ("valkia", "恐虐"), "tze": ("vilitch", "奸奇")}
TABLES = [
    "campaign_groups", "campaign_group_members",
    "campaign_group_member_criteria_factions",
    "campaign_group_member_criteria_campaigns",
    "campaign_group_member_criteria_pooled_resources",
    "campaign_group_member_criteria_numeric_ranges", "pooled_resources",
    "pooled_resource_factor_junctions", "campaign_group_pooled_resources",
    "campaign_group_rituals", "campaign_group_plague_component_setup_sets",
    "campaign_group_faction_plague_setup_sets",
    "campaign_group_settlement_occupation_looted_pooled_resources",
    "campaign_group_diplomatic_manipulation_category_junctions",
    "campaign_group_streak_sets", "effects",
    "effect_bonus_value_pooled_resource_junctions", "effect_bundles",
    "effect_bundles_to_effects_junctions", "campaign_stance_effects_junctions",
    "effect_bonus_value_stance_junctions", "campaign_effect_scopes",
    "ui_features_to_factions", "factions", "rituals", "faction_sets",
    "faction_set_items", "campaign_features",
    "teleportation_networks", "teleportation_network_nodes",
    "diplomatic_relationship_effects", "campaign_effect_list_effect_junctions",
]
UI_FILES = ["hud_campaign.twui.xml", "hud_campaign_resource_bar_wh3.twui.xml",
            "great_game_rituals.twui.xml", "rifts.twui.xml"]
NATIVE_INPUTS = {
    "db.pack": [f"db/{name}_tables" for name in TABLES],
    "ui3.pack": ["ui/campaign ui/" + name for name in UI_FILES],
    "data_script.pack": ["script/campaign/wh3_campaign_nurgle_plagues.lua",
                         "script/campaign/wh3_campaign_great_game.lua"],
}


def generate(native, output):
    tables = {name: read_table(native / "db", name) for name in TABLES}
    emitted = defaultdict(list)

    def add(name, **row):
        if set(row) != set(tables[name][0]):
            raise ValueError(f"Unexpected fields for {name}: {row.keys()}")
        if row not in emitted[name]:
            emitted[name].append(row)

    def rows(name):
        return tables[name][2]

    def one(name, **match):
        found = [r for r in rows(name) if all(r[k] == v for k, v in match.items())]
        if len(found) != 1:
            raise ValueError(f"Expected one native {name}: {match}, got {len(found)}")
        return found[0].copy()

    def group(suffix, context="ACTOR", active=False):
        key = PREFIX + suffix
        add("campaign_groups", id=key)
        add("campaign_group_members", id=key, group=key, priority="0.0000")
        member(key, context, active)
        return key

    def member(key, context, active=False):
        add("campaign_group_member_criteria_factions", member=key,
            context=context, faction=HOST)
        add("campaign_group_member_criteria_campaigns", member=key,
            campaign="wh3_main_combi")
        if active:
            add("campaign_group_member_criteria_pooled_resources", member=key,
                pooled_resource=PREFIX + "unlocked_nur")
            add("campaign_group_member_criteria_numeric_ranges", member=key,
                context="VALUE", max_range="1", min_range="1")

    def clone(name, source, target, predicate=lambda r: True, **changes):
        selected = [r for r in rows(name)
                    if r["campaign_group"] == source and predicate(r)]
        if not selected:
            raise ValueError(f"Missing native configuration: {name}/{source}")
        for row in selected:
            add(name, **dict(row, campaign_group=target, **changes))
        return selected

    host = group("host")
    groups = {god: group(god, "OWNER" if god == "kho" else "ACTOR")
              for god in ("nur", "tze", "kho", "gg")}
    active = group("nur_active", active=True)
    resource = one("pooled_resources", key="wh3_main_ritual_belakor_gg_1_uses")
    resource.update(key=PREFIX + "unlocked_nur", maximum="1", minimum="0",
                    optional_icon_path="")
    add("pooled_resources", **resource)
    factor = one("pooled_resource_factor_junctions",
                 resource="wh3_main_ritual_belakor_gg_1_uses", factor="other")
    factor.update(unique_id=resource["key"], resource=resource["key"])
    add("pooled_resource_factor_junctions", **factor)
    # Resource balances exist from campaign creation; ritual access starts locked.
    sample = one("campaign_group_pooled_resources",
                 campaign_group="wh3_main_feature_belakor",
                 resource="wh3_main_ritual_belakor_gg_1_uses")
    add("campaign_group_pooled_resources",
        **dict(sample, campaign_group=host, resource=resource["key"]))
    rituals = {}
    for god, source, wanted in (
        ("nur", "wh3_dlc20_feature_festus", {"wh3_main_nur_infections"}),
        ("tze", "wh3_dlc20_feature_vilitch",
         {"wh3_main_tze_winds_of_magic_manipulation"}),
        ("gg", "wh3_main_feature_belakor",
         {f"wh3_main_ritual_belakor_gg_{i}_uses" for i in range(1, 5)}),
    ):
        selected = clone("campaign_group_rituals", source, groups[god],
                         initially_unlocked="false")
        rituals[god] = [r["ritual"] for r in selected]
        # Native starting values are not inherited rewards.
        resource_rows = clone("campaign_group_pooled_resources", source,
                              groups[god], lambda r: r["resource"] in wanted)
        for row in emitted["campaign_group_pooled_resources"]:
            if row["campaign_group"] == groups[god]:
                row["initial_amount"] = "0"
        if {r["resource"] for r in resource_rows} != wanted:
            raise ValueError(f"Missing mechanic resources: {god}")

    for table, source, target in (
        ("campaign_group_plague_component_setup_sets", "wh3_dlc20_feature_festus", groups["nur"]),
        ("campaign_group_faction_plague_setup_sets", "nurgle_plague_festus_faction", groups["nur"]),
        ("campaign_group_settlement_occupation_looted_pooled_resources", "wh3_dlc20_feature_festus", active),
        ("campaign_group_diplomatic_manipulation_category_junctions", "wh3_dlc20_feature_vilitch", groups["tze"]),
        ("campaign_group_streak_sets", "wh3_dlc20_valkia_win_streak", groups["kho"]),
    ):
        clone(table, source, target)
    captive = PREFIX + "captive"
    add("campaign_group_members", id=captive,
        group="wh3_dlc20_captive_option_kill_festus", priority="1.0000")
    member(captive, "ORIGINATOR", active=True)

    def bundle(suffix, effects, visible=False):
        key = PREFIX + suffix
        add("effect_bundles", key=key, localised_description="",
            localised_title="", bundle_target="faction",
            priority="10" if visible else "0",
            ui_icon="", is_global_effect="false", show_in_3d_space="false",
            owner_only="true")
        for effect, scope, value in effects:
            add("effect_bundles_to_effects_junctions", effect_bundle_key=key,
                effect_key=effect, effect_scope=scope, value=f"{value:.4f}",
                advancement_stage="start_turn_completed")

    blessing_keys = {}
    for god, (champion, _) in BLESSINGS.items():
        relation = one("diplomatic_relationship_effects",
                       diplomatic_stance="vassal", faction_set="all",
                       faction_set_relation_with="faction_set_" + champion)
        effects = [r for r in rows("campaign_effect_list_effect_junctions")
                   if r["effect_list"] == relation["campaign_effect_list"]]
        if not effects:
            raise ValueError(f"Missing native vassal blessing: {champion}")
        bundle("vassal_" + god,
               [(r["effect"], r["scope"], float(r["value"])) for r in effects],
               visible=True)
        blessing_keys[god] = PREFIX + "vassal_" + god

    network = one("teleportation_networks", key=NETWORK,
                  campaign="wh3_main_combi", permitted_agents="all_agents")
    permission = one("faction_set_items", faction="wh3_main_chs_shadow_legion",
                     set=network["traveller_requirements"], remove="false")
    permission_id = "1909280001"
    if any(r["id"] == permission_id or
           (r["faction"] == HOST and r["set"] == permission["set"])
           for r in rows("faction_set_items")):
        raise ValueError("Archaon portal permission overlaps a native row")
    add("faction_set_items", **dict(permission, id=permission_id, faction=HOST))
    portal_nodes = [r["key"] for r in rows("teleportation_network_nodes")
                    if r["network"] == NETWORK and r["template"] == NODE_TEMPLATE]
    if not portal_nodes or len(portal_nodes) != len(set(portal_nodes)):
        raise ValueError("Missing or ambiguous Be'lakor network nodes")

    reduction = PREFIX + "infection_reduction"
    effect = one("effects", effect="wh3_main_effect_dae_nurgle_points_percentage_multiplier_mod")
    effect.update(effect=reduction, icon="", icon_negative="", priority="0")
    add("effects", **effect)
    for bonus in ("percentage_multiplier_mod",
                  "post_battle_captivity_outcome_pooled_resource_percentage_mod"):
        junction = one("effect_bonus_value_pooled_resource_junctions",
                       effect="wh3_main_effect_dae_nurgle_points_percentage_multiplier_mod",
                       bonus_value_id=bonus)
        junction.update(effect=reduction, pooled_resource="wh3_main_nur_infections")
        add("effect_bonus_value_pooled_resource_junctions", **junction)
    bundle("infections_locked", [(reduction, "faction_to_faction_own_unseen", -100)])
    bundle("tze", [
        ("wh3_main_effect_tze_cotw_enable_break_alliance", "faction_to_faction_own_unseen", 1),
        ("wh3_main_effect_disable_stance_tunnelling_tze", "faction_to_force_own_unseen", -1),
        ("wh3_dlc26_effect_stance_availability_tunneling_enable", "faction_to_faction_own_unseen", 1),
    ])
    stance = one("campaign_stance_effects_junctions",
                 stance="MILITARY_FORCE_ACTIVE_STANCE_TYPE_TUNNELING",
                 faction="wh3_dlc20_chs_vilitch")
    add("campaign_stance_effects_junctions", **dict(stance, faction=HOST))
    for feature in ("NURGLE_PLAGUES", "CHANGING_OF_WAYS"):
        row = one("ui_features_to_factions", faction="wh3_dlc20_chs_festus"
                  if feature == "NURGLE_PLAGUES" else "wh3_dlc20_chs_vilitch",
                  ui_feature=feature)
        add("ui_features_to_factions", **dict(row, faction=HOST))

    # Validate references against current native records, not just serialization.
    effect_keys = {r["effect"] for r in rows("effects") + emitted["effects"]}
    scopes = {r[tables["campaign_effect_scopes"][0][0]] for r in rows("campaign_effect_scopes")}
    for row in emitted["effect_bundles_to_effects_junctions"]:
        if row["effect_key"] not in effect_keys or row["effect_scope"] not in scopes:
            raise ValueError(f"Invalid effect/scope: {row}")
    native_rituals = {r["key"] for r in rows("rituals")}
    if not all(r in native_rituals for values in rituals.values() for r in values):
        raise ValueError("Unknown inherited ritual")
    native_features = {r["feature"] for r in rows("campaign_features")}
    if not {"bribery", "streaks", "diplomatic_manipulation",
            "not_intercepted_on_tunneling", "tunnel_attack_is_ambush"} <= native_features:
        raise ValueError("Unknown inherited faction feature")
    for set_key, excluded in (("plague_effect_set_nurgle_positive", "false"),
                              ("plague_effect_set_nurgle_negative", "true")):
        one("faction_set_items", faction=HOST, set=set_key, remove=excluded)
    for name, new_rows in emitted.items():
        write_table(output, name, tables[name], new_rows, PREFIX + "data")
    patch_ui(native, output)
    write_blessing_loc(output, blessing_keys)
    # The Fennel adapter consumes the same ritual list as the DB generator.
    path = output / "script/campaign/mod/everchosen_inheritance_data.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    entries = [god + "={" + ",".join(json.dumps(r) for r in values) + "}"
               for god, values in rituals.items()]
    entries.append("blessings={" + ",".join(
        god + "=" + json.dumps(key) for god, key in blessing_keys.items()) + "}")
    entries.append("portals={network=" + json.dumps(NETWORK)
                   + ",template=" + json.dumps(NODE_TEMPLATE) + ",nodes={"
                   + ",".join("[" + json.dumps(key) + "]=true"
                              for key in portal_nodes) + "}}")
    path.write_text('core:add_static_object("everchosen_inheritance_data", {'
                    + ",".join(entries) + '})\n', encoding="utf-8")
    print(f"Inheritance: {sum(map(len, emitted.values()))} rows across "
          f"{len(emitted)} tables; {len(UI_FILES)} native UI adaptations")


def patch_ui(native, output):
    targets = {
        UI_FILES[0]: {"button_nurgle_plagues": "nur",
                      "button_changing_of_the_ways": "tze",
                      "button_great_game_rituals": "gg"},
        UI_FILES[1]: {"nurgle_infections_holder": "nur",
                      "dae_ascendant_race_holder": "gg"},
    }
    for filename in UI_FILES:
        tree = ET.parse(native / "ui/campaign ui" / filename)
        changes = []
        for control, god in targets.get(filename, {}).items():
            matches = tree.findall(f'.//*[@id="{control}"]')
            if len(matches) != 1:
                raise ValueError(f"UI control changed: {control}")
            callbacks = matches[0].findall('.//callback_with_context[@callback_id="ContextVisibilitySetter"]')
            if not callbacks:
                raise ValueError(f"UI visibility anchor missing: {control}")
            for callback in callbacks:
                original = callback.attrib["context_function_id"]
                gate = f'ScriptObjectContext("{PREFIX}ui_{god}").NumericValue == 1'
                callback.set("context_function_id", f'({original}) && (PlayersFaction.FactionRecordContext.Key != "{HOST}" || {gate})')
                changes.append((callback, original))
        if filename == UI_FILES[2]:
            before = 'PlayersFaction.FactionRecordContext.Key == "wh3_main_chs_shadow_legion"'
            for element in tree.iter():
                original = element.get("context_function_id", "")
                if before in original:
                    element.set("context_function_id", original.replace(before,
                        f'({before} || (PlayersFaction.FactionRecordContext.Key == "{HOST}" && ScriptObjectContext("{PREFIX}ui_gg").NumericValue == 1))'))
                    changes.append((element, original))
            if len(changes) != 1:
                raise ValueError("Manifestation UI anchor changed")
        if filename == "rifts.twui.xml":
            gate = (f'(CharacterContext.FactionContext.FactionRecordContext.Key != "{HOST}"'
                    f' || InteractingNodeContext.TeleportationTemplateContext.Key != "{NODE_TEMPLATE}"'
                    + "".join(f' || CharacterContext.AgentSubtypeRecordContext.Key == "{lord}"'
                              for lord in PORTAL_LORDS) + ")")
            for control in ("button_enter_rift", "teleport_rift", "button_teleport_confirm"):
                for kind in ("ContextInactiveStateSetter", "ContextCommandLeftClick"):
                    callbacks = tree.findall(f'.//*[@id="{control}"]/callbacks_with_context/'
                                             f'callback_with_context[@callback_id="{kind}"]')
                    if len(callbacks) != 1 or callbacks[0].get("context_object_id") != "CcoCampaignCharacterTeleportationSystem":
                        raise ValueError(f"Rift callback changed: {control}/{kind}")
                    callback = callbacks[0]
                    original = callback.attrib["context_function_id"]
                    expression = (f"{gate} && ({original})" if kind == "ContextInactiveStateSetter"
                                  else f"DoIf({gate}, {original})")
                    callback.set("context_function_id", expression)
                    changes.append((callback, original))
        path = output / "ui/campaign ui" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        tree.write(path, encoding="utf-8", xml_declaration=True)
        # Reversing the edits must recover the entire original UI topology.
        for element, original in changes:
            element.set("context_function_id", original)
        original_tree = ET.parse(native / "ui/campaign ui" / filename)
        if ET.tostring(tree.getroot()) != ET.tostring(original_tree.getroot()):
            raise ValueError(f"Unintended UI change: {filename}")


def write_blessing_loc(output, keys):
    path = output / "text/db/everchosen_inheritance.loc.tsv"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(["key", "text", "tooltip"])
        writer.writerow(["#Loc;1;text/db/everchosen_inheritance.loc", "", ""])
        for god, key in keys.items():
            name = BLESSINGS[god][1]
            writer.writerow(["effect_bundles_localised_title_" + key,
                             "永世神选的赐福：" + name, "false"])
            writer.writerow(["effect_bundles_localised_description_" + key,
                             "作为永世神选的直属附庸，获得" + name + "的赐福。", "false"])


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
