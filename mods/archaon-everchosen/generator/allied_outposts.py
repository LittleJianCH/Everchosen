"""Archaon's allied outpost annexes, using the native allied unit source."""
from db_tables import stable_id
from host import HOST

PREFIX = "everchosen_allied_"
SLOT_SET = PREFIX + "slots"
TEMPLATE = PREFIX + "annex"
MAIN_TEMPLATE = "wh3_main_foreign_slot_allied"
MAIN_CHAIN = "wh3_main_chs_allied_outpost"
MAIN_LEVEL = MAIN_CHAIN + "_1"
NATIVE_SET = "wh3_main_slot_set_allied_building"
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
ICON_SOURCES = {
    "infantry": "wh_main_nor_military_1",
    "ranged": "wh_main_nor_smith_1",
    "cavalry": "wh_main_nor_outpost_stables_1",
    "monsters": "wh3_dlc27_nor_creatures_0",
}
SUPPORT_EFFECT = "wh_main_effect_force_all_campaign_replenishment_rate"
COPIED_ROWS = (
    ("allied_foreign_slot_sets", {"key": "PLACEHOLDER"},
     {"key": PREFIX + "outpost", "slot_set": SLOT_SET}),
    ("slot_sets", {"key": NATIVE_SET}, {"key": SLOT_SET}),
)
TABLES = """allied_foreign_slot_sets campaign_group_allied_foreign_slot_sets
    slot_sets slot_set_items slot_templates slot_template_permitted_building_chains
    building_levels building_chains building_superchains building_instances
    building_culture_variants building_allied_units main_units campaign_groups
    building_chain_availability_sets building_effects_junction effects
    campaign_effect_scopes
    building_sets building_set_to_building_junctions
""".split()
UI_FOLDER = "ui/campaign ui/"
NATIVE_INPUTS = [UI_FOLDER + name + ".twui.xml" for name in (
    "war_coordination", "settlement_panel", "settlement_building_slot",
    "building_construction_popup")]


def rows(native):
    for table, match, changes in COPIED_ROWS:
        yield table, dict(native[table].one(**match), **changes)
    original = native["slot_set_items"].one(slot_set=NATIVE_SET)
    used = native["slot_set_items"].column("id")
    yield "slot_set_items", dict(original, id=stable_id(SLOT_SET, used),
                                 slot_set=SLOT_SET)
    for index in range(3):
        yield "slot_set_items", dict(
            original, id=stable_id(TEMPLATE + str(index), used),
            slot_set=SLOT_SET, slot_template=TEMPLATE, building_level="")
    for index, route in enumerate(ROUTES, 1):
        key = PREFIX + route
        icon = native["building_culture_variants"].one(
            building=ICON_SOURCES[route])["icon"]
        yield "building_sets", dict(
            native["building_sets"].one(
                key="wh2_dlc09_set_tomb_kings_military_support"),
            key=key + "_category", icon="ui/buildings/icons/" + icon + ".png",
            sort_order=str(index))
        yield "building_chains", dict(
            native["building_chains"].one(key=MAIN_CHAIN),
            key=key, building_superchain=key, can_be_dismantled="true",
            is_foreign_slot_chain="true")
        yield "building_levels", dict(
            native["building_levels"].one(level_name=MAIN_LEVEL),
            level_name=key + "_1", chain=key, building_instance_key=key,
            create_cost="3000", create_time="3", can_convert="false",
            primary_slot_building_building_level_requirement="1")
        yield "building_culture_variants", dict(
            native["building_culture_variants"].one(
                building=MAIN_LEVEL),
            building=key + "_1", faction=HOST, short_description=key + "_1",
            description=key + "_1", icon=icon)
        yield "building_effects_junction", dict(
            native["building_effects_junction"].one(
                building=MAIN_LEVEL, effect=SUPPORT_EFFECT),
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
    assert sum(r["slot_template"] == MAIN_TEMPLATE
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
                  if r["building_chain"].startswith(PREFIX)]
    assert {r["building_chain"] for r in categories} == {
        PREFIX + route for route in ROUTES}
    assert all(r["building_set"] == r["building_chain"] + "_category"
               for r in categories)
    variants = [r for r in generated["building_culture_variants"]
                if r["building"].startswith(PREFIX)]
    assert len(variants) == 4 and all(r["faction"] == HOST for r in variants)
    assert len({r["icon"] for r in variants}) == 4
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


def adapt_coordination(tree, native_root, native):
    root = tree.getroot()
    # Native upgrade/move controls address FirstContext. Keep those on the
    # original main slot when the manager also contains annex slots.
    for element in root.iter():
        value = element.get("context_function_id", "")
        for owner in ("PlayersFaction", "PlayerFactionContext"):
            source = f"AlliedForeignSlotList({owner}).FirstContext"
            value = value.replace(source, f"AlliedForeignSlotList({owner})."
                                  f'Filter(SlotTemplateKey == '
                                  f'"{MAIN_TEMPLATE}").FirstContext')
        if "context_function_id" in element.attrib:
            element.set("context_function_id", value)


def adapt_settlement(tree, native_root, native):
    """Keep the native two-column layout, placing the main allied slot first."""
    source = 'AlliedForeignSlotList(StoredContext("CcoCampaignFaction"))'
    targets = [element for element in tree.getroot().iter()
               if element.get("context_function_id") == source]
    if len(targets) != 1:
        raise ValueError("Native allied settlement slot list changed")
    main = f'SlotTemplateKey == "{MAIN_TEMPLATE}"'
    secondary = f'SlotTemplateKey != "{MAIN_TEMPLATE}"'
    targets[0].set("context_function_id",
                  f'GetIfElse({source}.Any(SlotTemplateKey == "{TEMPLATE}"), '
                  f'Join({source}.Filter({main}), '
                  f'{source}.Filter({secondary})), {source})')


def adapt_categories(tree, native_root, native):
    """Use native category hover and construction popups for our empty slots."""
    count = 0
    condition = (f'(ShouldShowCategoriesPopup || (SlotTemplateKey == '
                 f'"{TEMPLATE}" && PossibleBuildingSetList.Size > 1))')
    for element in tree.getroot().iter():
        value = element.get("context_function_id", "")
        if "ShouldShowCategoriesPopup" not in value:
            continue
        if element.get("context_object_id") != "CcoCampaignBuildingSlot":
            raise ValueError("Native construction category context changed")
        element.set("context_function_id",
                    value.replace("ShouldShowCategoriesPopup", condition))
        count += 1
    if count not in (1, 4):
        raise ValueError(f"Native category popup anchors changed: {count}")


UI_ADAPTATIONS = {
    UI_FOLDER + "war_coordination.twui.xml": adapt_coordination,
    UI_FOLDER + "settlement_panel.twui.xml": adapt_settlement,
    UI_FOLDER + "settlement_building_slot.twui.xml": adapt_categories,
    UI_FOLDER + "building_construction_popup.twui.xml": adapt_categories,
}
