"""Archaon's allied outpost annexes, using the native allied unit source."""
from uuid import NAMESPACE_URL, uuid5
import xml.etree.ElementTree as ET

from db_tables import stable_id
from host import HOST

PREFIX = "everchosen_allied_"
SLOT_SET = PREFIX + "slots"
TEMPLATE = PREFIX + "annex"
ROUTES = {
    "infantry": ("步兵营地", "wh_dlc08_nor_inf_marauder_champions_0",
                 "wh3_dlc23_chd_inf_infernal_ironsworn"),
    "ranged": ("远程营地", "wh_dlc08_nor_inf_marauder_hunters_1",
               "wh3_dlc23_chd_inf_chaos_dwarf_blunderbusses"),
    "cavalry": ("骑兵营地", "wh_dlc08_nor_cav_marauder_horsemasters_0",
                "wh3_dlc23_chd_cav_bull_centaurs_axe"),
    "monsters": ("怪兽营地", "wh_dlc08_nor_mon_frost_wyrm_0",
                "wh3_dlc23_chd_mon_kdaai_destroyer"),
}
GROUPS = ("wh_dlc08_feature_norsca", "wh3_dlc23_feature_chaos_dwarfs")
SUPPORT_EFFECT = "wh_main_effect_force_all_campaign_replenishment_rate"
TABLES = """allied_foreign_slot_sets campaign_group_allied_foreign_slot_sets
    slot_sets slot_set_items slot_templates slot_template_permitted_building_chains
    building_levels building_chains building_superchains building_instances
    building_culture_variants building_allied_units main_units campaign_groups
    building_chain_availability_sets building_effects_junction effects
    campaign_effect_scopes
    building_sets building_set_to_building_junctions
""".split()
UI_PATH = "ui/campaign ui/war_coordination.twui.xml"


def rows(native):
    yield "allied_foreign_slot_sets", dict(
        native["allied_foreign_slot_sets"].one(key="PLACEHOLDER"),
        key=PREFIX + "outpost", slot_set=SLOT_SET)
    yield "slot_sets", dict(
        native["slot_sets"].one(key="wh3_main_slot_set_allied_building"),
        key=SLOT_SET)
    original = native["slot_set_items"].one(
        slot_set="wh3_main_slot_set_allied_building")
    used = native["slot_set_items"].column("id")
    yield "slot_set_items", dict(original, id=stable_id(SLOT_SET, used),
                                 slot_set=SLOT_SET)
    for index in range(3):
        yield "slot_set_items", dict(
            original, id=stable_id(TEMPLATE + str(index), used),
            slot_set=SLOT_SET, slot_template=TEMPLATE, building_level="")
    for route in ROUTES:
        key = PREFIX + route
        yield "building_chains", dict(
            native["building_chains"].one(key="wh3_main_chs_allied_outpost"),
            key=key, building_superchain=key, can_be_dismantled="true",
            is_foreign_slot_chain="true")
        yield "building_levels", dict(
            native["building_levels"].one(level_name="wh3_main_chs_allied_outpost_1"),
            level_name=key + "_1", chain=key, building_instance_key=key,
            create_cost="3000", create_time="3", can_convert="false",
            primary_slot_building_building_level_requirement="1")
        yield "building_culture_variants", dict(
            native["building_culture_variants"].one(
                building="wh3_main_chs_allied_outpost_1"),
            building=key + "_1", faction=HOST, short_description=key + "_1",
            description=key + "_1")
        yield "building_effects_junction", dict(
            native["building_effects_junction"].one(
                building="wh3_main_chs_allied_outpost_1", effect=SUPPORT_EFFECT),
            building=key + "_1", value="1.0000", value_damaged="0.0000",
            value_ruined="0.0000")
        for group, unit in zip(GROUPS, ROUTES[route][1:]):
            native["main_units"].one(unit=unit)
            native["campaign_groups"].one(id=group)
            yield "building_allied_units", {
                "building": key + "_1", "campaign_group": group, "unit": unit}


def validate(native, generated, authored):
    own_slots = [r for r in generated.get("slot_set_items", [])
                 if r["slot_set"] == SLOT_SET]
    assert len(own_slots) == 4, "Allied outpost requires main plus three annexes"
    assert sum(r["slot_template"] == TEMPLATE for r in own_slots) == 3
    assert sum(r["slot_template"] == "wh3_main_foreign_slot_allied"
               for r in own_slots) == 1
    mapping = [r for r in authored["campaign_group_allied_foreign_slot_sets"]
               if r["slot_set"] == PREFIX + "outpost"]
    assert mapping == [{"campaign_group": "everchosen_inheritance_host",
                        "slot_set": PREFIX + "outpost"}]
    assert native["campaign_group_allied_foreign_slot_sets"].rows == [
        {"campaign_group": "wh_main_feature_all", "slot_set": "PLACEHOLDER"}]
    allowed = [r for r in authored["slot_template_permitted_building_chains"]
               if r["slot_template"] == TEMPLATE]
    assert {r["chain"] for r in allowed} == {PREFIX + route for route in ROUTES}
    assert all(not r["chain_set"] and not r["super_chain"] and
               r["remove"] == "false" for r in allowed)
    categories = [r for r in authored["building_set_to_building_junctions"]
                  if r["building_set"] == PREFIX + "category"]
    assert {r["building_chain"] for r in categories} == {
        PREFIX + route for route in ROUTES}
    variants = [r for r in generated["building_culture_variants"]
                if r["building"].startswith(PREFIX)]
    assert len(variants) == 4 and all(r["faction"] == HOST for r in variants)
    support = [r for r in generated["building_effects_junction"]
               if r["building"].startswith(PREFIX)]
    for row in support:
        native["effects"].one(effect=row["effect"])
        native["campaign_effect_scopes"].one(key=row["effect_scope"])
        assert row["effect_scope"] == "region_to_force_own_and_allied"
    for table in ("slot_set_items", "slot_sets", "allied_foreign_slot_sets"):
        keys = "id" if table == "slot_set_items" else "key"
        assert not {r[keys] for r in generated.get(table, [])
                    if r.get("slot_set") == SLOT_SET or
                    r.get("key", "").startswith(PREFIX)} & native[table].column(keys)


def guid(name):
    return str(uuid5(NAMESPACE_URL, PREFIX + name)).upper()


def adapt_ui(tree, native_root, native):
    root = tree.getroot()
    # Native upgrade/move controls address FirstContext. Keep those on the
    # original main slot when the manager also contains annex slots.
    for element in root.iter():
        value = element.get("context_function_id", "")
        for owner in ("PlayersFaction", "PlayerFactionContext"):
            source = f"AlliedForeignSlotList({owner}).FirstContext"
            value = value.replace(source, f"AlliedForeignSlotList({owner})."
                                  'Filter(SlotTemplateKey == '
                                  '"wh3_main_foreign_slot_allied").FirstContext')
        if "context_function_id" in element.attrib:
            element.set("context_function_id", value)
    parent = root.find("hierarchy/root/war_coordination/war_coordination_panel/"
                       "subpanel_outposts/constructed_options")
    assert parent is not None, "Native outpost hierarchy changed"
    name = PREFIX + "annex_list"
    ET.SubElement(parent, name, this=guid(name))
    node = ET.SubElement(root.find("components"), name, this=guid(name),
                         id=name, uniqueguid=guid(name),
                         docking="Center Right External", dock_offset="15.00,0.00",
                         component_anchor_point="0.00,0.50",
                         currentstate=guid(name + "state"),
                         defaultstate=guid(name + "state"))
    ET.SubElement(ET.SubElement(node, "states"), "default",
                  this=guid(name + "state"), uniqueguid=guid(name + "state"),
                  name="default", width="285", height="140")
    callbacks = ET.SubElement(node, "callbackwithcontextlist")
    ET.SubElement(callbacks, "callback_with_context",
                  callback_id="ContextVisibilitySetter",
                  context_object_id="CcoStaticObject",
                  context_function_id=f'PlayersFaction.FactionRecordContext.Key == "{HOST}"')
    ET.SubElement(callbacks, "callback_with_context",
                  callback_id="ContextPropagator",
                  context_function_id='StoredContextFromParent("CcoCampaignSettlement")')
    listing = ET.SubElement(callbacks, "callback_with_context",
                            callback_id="ContextList",
                            context_object_id="CcoCampaignSettlement",
                            context_function_id='AlliedForeignSlotList(PlayersFaction).'
                            f'Filter(SlotTemplateKey == "{TEMPLATE}")')
    props = ET.SubElement(listing, "child_m_user_properties")
    for key, value in {"template_layout": "ui/campaign ui/settlement_building_slot",
                       "event0": "ForeignSlotAdded", "event1": "ForeignSlotRemoved",
                       "event2": "BuildingConstructionIssuedByPlayer",
                       "refresh_when_same": ""}.items():
        ET.SubElement(props, "property", name=key, value=value)
    # Native building cards require the constructing faction as an ancestor.
    ET.SubElement(callbacks, "callback_with_context",
                  callback_id="ContextObjectStore",
                  context_object_id="CcoCampaignFaction")
    ET.SubElement(callbacks, "callback_with_context",
                  callback_id="ContextPropagator", context_function_id="PlayersFaction",
                  context_object_id="CcoCampaignSettlement")
    ET.SubElement(node, "LayoutEngine", type="HorizontalList", spacing="6.00,0.00",
                  sizetocontent="true")


UI_ADAPTATIONS = {UI_PATH: adapt_ui}
