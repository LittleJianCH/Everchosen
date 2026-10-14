"""Private Beastmen camps and their building-controlled province stock."""
from collections import defaultdict
from pathlib import Path

from db_tables import read_authored, stable_id
from host import HOST, CAMPAIGN
from vassal_military_buildings import CHAINS as VASSAL_CHAINS
from vassal_military_buildings import PREFIX as VASSAL_PREFIX

PREFIX = "everchosen_horde_"
CULTURE = "wh_main_chs_chaos"
START_BUNDLE = PREFIX + "new_horde"
SETTLE_BUNDLE = PREFIX + "settle"
POOL_SOURCE = PREFIX + "camp_stock"
UNIT_SET = PREFIX + "warband_units"
AVAILABILITY = PREFIX + "availability"
SLOTS = {"primary": PREFIX + "primary", "secondary": PREFIX + "secondary"}
START_SET = PREFIX + "starting_buildings"
HORN_CHAIN = "wh2_dlc17_horde_beastmen_army_buffs_terror"
MAIN_CHAIN = "wh_dlc03_horde_beastmen_herd"
POOL = "wh3_dlc20_chs_province_pool"
SUBTYPES = {
    "wh_dlc03_bst_khazrak": "HORDE_KHAZRAK",
    "wh_dlc03_bst_malagor": "HORDE_MALAGOR",
    "wh_dlc05_bst_morghur": "HORDE_MORGHUR",
    "wh2_dlc17_bst_taurox": "HORDE_TAUROX",
}
CHANCE = {1: 40, 2: 30, 3: 20, 4: 12, 5: 8}
CAPACITY = {1: 4, 2: 3, 3: 2, 4: 1, 5: 1}
REMOVED_EFFECTS = {
    "wh2_dlc17_effect_pooled_resource_dread_per_turn_buildings",
    "wh_main_effect_force_all_recruitment_points",
}
TABLES = """building_chain_availability_sets building_chain_availability_set_ids
    building_chain_availabilities building_chains building_superchains
    building_instances building_levels building_culture_variants
    building_effects_junction building_upgrades_junction
    building_downgrade_junctions building_units_allowed building_sets
    building_set_to_building_junctions building_chain_sets building_chain_set_items
    slot_templates slot_template_permitted_building_chains slot_types
    military_force_types military_force_type_horde_details
    military_force_type_conversions agent_subtype_military_force_creation_overrides
    military_force_type_feature_junctions campaign_settlement_display_building_ids
    campaign_settlement_display_building_model_ids campaign_stances_composite_scenes
    campaign_groups campaign_group_members campaign_group_member_criteria_military_force_types
    campaign_group_member_criteria_factions campaign_group_member_criteria_campaigns
    campaign_group_member_criteria_agent_subtypes effects
    effect_bonus_value_building_set_junctions effect_bonus_value_stance_junctions
    effect_bundles effect_bundles_to_effects_junctions campaign_effect_scopes
    mercenary_pools mercenary_unit_groups mercenary_pool_to_groups_junctions
    main_units unit_sets unit_set_to_unit_junctions effect_bonus_value_ids_unit_sets
    factions agent_subtypes
""".split()


def expand_chain_set(native, key, visited=()):
    """Resolve native slot-set inheritance, including removals."""
    if key in visited:
        raise ValueError(f"Cyclic native building chain set: {key}")
    row = native["building_chain_sets"].one(key=key)
    chains = (expand_chain_set(native, row["parent_set"], (*visited, key))
              if row["parent_set"] else set())
    for item in native["building_chain_set_items"].where(set=key):
        values = chain_selection(native, item)
        if item["remove"] == "true":
            chains.difference_update(values)
        else:
            chains.update(values)
    return chains


def chain_selection(native, row):
    chains = {row["chain"]} if row["chain"] else set()
    if row["super_chain"]:
        chains.update(r["key"] for r in native["building_chains"].where(
            building_superchain=row["super_chain"]))
    if row.get("chain_set"):
        chains.update(expand_chain_set(native, row["chain_set"]))
    return chains


def slot_chains(native, template):
    chains = set()
    rows = native["slot_template_permitted_building_chains"].where(
        slot_template=template)
    for row in rows:
        if row["remove"] == "false":
            chains.update(chain_selection(native, row))
    for row in rows:
        if row["remove"] == "true":
            chains.difference_update(chain_selection(native, row))
    return chains


def graph(native):
    """Only native Beastmen-buildable chains from the four bound camps."""
    available = {r["building_chain"] for r in native[
        "building_chain_availability_sets"].where(id="wh_dlc03_bas_bst")}
    details = [native["military_force_type_horde_details"].one(force_type=kind)
               for kind in SUBTYPES.values()]
    by_slot = {}
    for role in SLOTS:
        candidates = [slot_chains(native, row[role + "_slot_template"])
                      & available for row in details]
        if not candidates[0] or any(c != candidates[0] for c in candidates[1:]):
            raise ValueError(f"Native bound camps disagree on {role} chains")
        by_slot[role] = candidates[0]
    if by_slot["primary"] != {MAIN_CHAIN}:
        raise ValueError("Native Beastmen main camp changed")
    chains = set().union(*by_slot.values())
    levels = {r["level_name"]: r for r in native["building_levels"].rows
              if r["chain"] in chains}
    if not levels or HORN_CHAIN not in chains:
        raise ValueError("Incomplete native Beastmen building graph")
    return by_slot, chains, levels


def script_data(native):
    _, _, levels = graph(native)
    buildings = defaultdict(set)
    tiers = {}
    for row in native["building_units_allowed"].rows:
        if row["building"] not in levels:
            continue
        if (row["faction"], row["enabled"], row["conditions"]) != (
                "", "false", "0"):
            raise ValueError(f"Conditional native camp recruitment: {row}")
        unit = row["unit"]
        native["main_units"].one(unit=unit)
        level = levels[row["building"]]
        tier = int(level["primary_slot_building_building_level_requirement"]) + 1
        if tier not in CHANCE:
            raise ValueError(f"Unsupported Beastmen recruitment tier: {tier}")
        tiers[unit] = min(tiers.get(unit, tier), tier)
        buildings[PREFIX + row["building"]].add(unit)
    horns = {PREFIX + key: 10 * (int(row["level"]) + 1)
             for key, row in levels.items() if row["chain"] == HORN_CHAIN}
    return {"subtypes": SUBTYPES.copy(), "start_bundle": START_BUNDLE,
            "settle_bundle": SETTLE_BUNDLE, "pool_source": POOL_SOURCE,
            "buildings": {key: sorted(units)
                          for key, units in sorted(buildings.items())},
            "horn_bonus": horns,
            "units": {unit: {"chance": CHANCE[tier], "cap": CAPACITY[tier]}
                      for unit, tier in sorted(tiers.items())}}


def building_rows(native):
    by_slot, chains, levels = graph(native)
    for key in sorted(chains):
        chain = native["building_chains"].one(key=key)
        superchain = PREFIX + key + "_super"
        yield "building_superchains", {"key": superchain}
        yield "building_chains", dict(chain, key=PREFIX + key,
                                      building_superchain=superchain)
        yield "building_chain_availability_sets", {
            "building_chain": PREFIX + key, "id": AVAILABILITY}
    instance_keys = {r["building_instance_key"] for r in levels.values()
                     if r["building_instance_key"]}
    for key in sorted(instance_keys):
        yield "building_instances", dict(
            native["building_instances"].one(key=key), key=PREFIX + key)
    for key, row in sorted(levels.items()):
        instance = row["building_instance_key"]
        yield "building_levels", dict(row, level_name=PREFIX + key,
            chain=PREFIX + row["chain"],
            building_instance_key=PREFIX + instance if instance else "")
        variant = native["building_culture_variants"].one(
            building=key, culture="wh_dlc03_bst_beastmen", subculture="",
            faction="")
        yield "building_culture_variants", dict(
            variant, building=PREFIX + key, culture=CULTURE, faction=HOST)
    for name in ("building_upgrades_junction", "building_downgrade_junctions"):
        for row in native[name].rows:
            if row["from"] in levels:
                if row["to"] not in levels:
                    raise ValueError(f"Camp upgrade leaves private graph: {row}")
                yield name, {"from": PREFIX + row["from"],
                             "to": PREFIX + row["to"]}
    for row in native["building_effects_junction"].rows:
        if row["building"] in levels and row["effect"] not in REMOVED_EFFECTS:
            yield "building_effects_junction", dict(
                row, building=PREFIX + row["building"])
    for row in native["building_set_to_building_junctions"].rows:
        if row["building_chain"] in chains:
            yield "building_set_to_building_junctions", dict(
                row, building_chain=PREFIX + row["building_chain"])
        if row["building_set"] == "wh_dlc03_set_newhorde_beastmen":
            if row["building_level"] not in levels or row["exclude"] != "false":
                raise ValueError(f"Unknown native starting camp building: {row}")
            yield "building_set_to_building_junctions", dict(
                row, building_set=START_SET,
                building_level=PREFIX + row["building_level"])
    for row in native["campaign_settlement_display_building_ids"].rows:
        if row["building_level_key"] in levels:
            yield "campaign_settlement_display_building_ids", dict(
                row, key=PREFIX + row["key"],
                building_level_key=PREFIX + row["building_level_key"])
    # Generic horde slot sets also permit WoC main chains. Intersect with the
    # Beastmen list so imported camps cannot become dark fortresses.
    for role, selected in by_slot.items():
        for key in sorted(selected):
            for chain in (key, PREFIX + key):
                yield "slot_template_permitted_building_chains", {
                    "chain": chain, "chain_set": "", "slot_template": SLOTS[role],
                    "super_chain": "", "remove": "false"}


def access_rows(native):
    used = native["building_chain_availabilities"].column("id")
    base = native["building_chain_availabilities"].one(
        set_id="wh_main_bas_chs", faction="", campaign="")
    yield "building_chain_availabilities", dict(
        base, id=stable_id(AVAILABILITY, used), set_id=AVAILABILITY,
        faction=HOST, campaign=CAMPAIGN)
    for row in native["building_chain_availability_sets"].where(id=base["set_id"]):
        yield "building_chain_availability_sets", dict(row, id=AVAILABILITY)
    for kind in SUBTYPES.values():
        row = native["military_force_type_horde_details"].one(force_type=kind)
        yield "military_force_type_horde_details", dict(row,
            primary_slot_template=SLOTS["primary"],
            secondary_slot_template=SLOTS["secondary"])
        # Bound-horde creation uses subtype selectors, not automatic army
        # conversion. Match native ARMY -> Nakai/Malakai/ship permissions.
        source = native["military_force_type_conversions"].one(
            **{"from": "HORDE", "to": kind, "automatic": "false"})
        existing = native["military_force_type_conversions"].where(
            **{"from": "ARMY", "to": kind})
        if existing:
            if existing != [dict(source, **{"from": "ARMY"})]:
                raise ValueError(f"Native bound-horde conversion changed: {kind}")
        else:
            yield "military_force_type_conversions", dict(source, **{"from": "ARMY"})
    group = PREFIX + "stance_display"
    yield "campaign_groups", {"id": group}
    for kind in SUBTYPES.values():
        member = group + "_" + kind
        yield "campaign_group_members", {
            "id": member, "group": group, "priority": "0.0000"}
        yield "campaign_group_member_criteria_military_force_types", {
            "member": member, "force_type": kind}
        yield "campaign_group_member_criteria_factions", {
            "member": member, "context": "ORIGINATOR", "faction": HOST}
        yield "campaign_group_member_criteria_campaigns", {
            "member": member, "campaign": CAMPAIGN}
    scene = native["campaign_stances_composite_scenes"].one(
        group="wh_dlc03_stance_csc_beastmen",
        stance="MILITARY_FORCE_ACTIVE_STANCE_TYPE_SETTLE")
    yield "campaign_stances_composite_scenes", dict(scene, group=group)


def stock_rows(native):
    data = script_data(native)
    used = native["mercenary_pool_to_groups_junctions"].column("key")
    for unit in data["units"]:
        group = PREFIX + "stock_" + unit
        yield "mercenary_unit_groups", {
            "key": group, "chance_to_replenish": "0.0000", "max_count": "0",
            "unit_record": unit, "use_partial_replenishment": "false",
            "max_replenish_per_turn": "0.0000", "ui_order": "0"}
        yield "mercenary_pool_to_groups_junctions", {
            "key": stable_id(group, used), "group": group,
            "initial_unit_count": "0", "pool": POOL, "faction_requirement": HOST,
            "subculture_requirement": "", "tech_requirement": ""}
        yield "unit_set_to_unit_junctions", {
            "unit_caste": "", "unit_category": "", "unit_class": "",
            "unit_record": unit, "unit_set": UNIT_SET, "exclude": "false"}
    for building, bonus in data["horn_bonus"].items():
        yield "building_effects_junction", {
            "building": building, "effect": PREFIX + "horn_chance",
            "context_requirement": "", "effect_scope": "force_to_force_own",
            "value": f"{bonus:.4f}", "value_damaged": f"{bonus:.4f}",
            "value_ruined": "0.0000"}


def rows(native):
    yield from building_rows(native)
    yield from access_rows(native)
    yield from stock_rows(native)


def localisation(native):
    """Generated names refer to native translations; horn names are authored."""
    _, chains, levels = graph(native)
    for key, row in levels.items():
        if row["chain"] == HORN_CHAIN:
            continue
        source = "building_culture_variants_name_" + key + "wh_dlc03_bst_beastmen"
        target = "building_culture_variants_name_" + PREFIX + key + CULTURE + HOST
        yield {"key": target, "text": "神选兽群·{{tr:" + source + "}}",
               "tooltip": "false"}
    for chain in sorted(chains - {HORN_CHAIN}):
        row = native["building_chains"].one(key=chain)
        fields = ["chain_tooltip"]
        if row["in_encyclopedia"] == "true":
            fields.extend(("encyclopedia_name", "encyclopedia_description"))
        for field in fields:
            source = "building_chains_" + field + "_" + chain
            prefix = "" if field == "encyclopedia_description" else "神选兽群·"
            yield {"key": "building_chains_" + field + "_" + PREFIX + chain,
                   "text": prefix + "{{tr:" + source + "}}", "tooltip": "false"}


def validate(native, generated, authored=None):
    if authored is None:
        authored = read_authored(Path(__file__).resolve().parents[1] / "assets/db", native)
    own = {name: [row for row in generated.get(name, []) + authored.get(name, [])
                  if any(value.startswith(PREFIX) for value in row.values())]
           for name in TABLES}
    own["military_force_type_conversions"] = [
        r for r in generated.get("military_force_type_conversions", [])
        if r["to"] in SUBTYPES.values()]
    for name, entries in own.items():
        for row in entries:
            if set(row) != set(native[name].header):
                raise ValueError(f"Horde schema mismatch: {name} {row}")
            if row in native[name].rows:
                raise ValueError(f"Redundant native horde override: {name} {row}")
    references = {
        "building_chains": {"building_superchain": ("building_superchains", "key")},
        "building_levels": {"chain": ("building_chains", "key"),
                            "building_instance_key": ("building_instances", "key")},
        "building_culture_variants": {"building": ("building_levels", "level_name")},
        "building_chain_availability_sets": {
            "building_chain": ("building_chains", "key"),
            "id": ("building_chain_availability_set_ids", "id")},
        "building_chain_availabilities": {
            "set_id": ("building_chain_availability_set_ids", "id"),
            "faction": ("factions", "key")},
        "building_set_to_building_junctions": {
            "building_chain": ("building_chains", "key"),
            "building_level": ("building_levels", "level_name"),
            "building_set": ("building_sets", "key")},
        "building_effects_junction": {
            "building": ("building_levels", "level_name"),
            "effect": ("effects", "effect"),
            "effect_scope": ("campaign_effect_scopes", "key")},
        "slot_template_permitted_building_chains": {
            "chain": ("building_chains", "key"),
            "slot_template": ("slot_templates", "key")},
        "military_force_type_horde_details": {
            "force_type": ("military_force_types", "key"),
            "primary_slot_template": ("slot_templates", "key"),
            "secondary_slot_template": ("slot_templates", "key"),
            "primary_slot_type": ("slot_types", "key"),
            "secondary_slot_type": ("slot_types", "key")},
        "military_force_type_conversions": {
            "from": ("military_force_types", "key"),
            "to": ("military_force_types", "key")},
        "campaign_settlement_display_building_ids": {
            "building_level_key": ("building_levels", "level_name"),
            "building_model_id": ("campaign_settlement_display_building_model_ids", "id")},
        "campaign_stances_composite_scenes": {"group": ("campaign_groups", "id")},
        "campaign_group_members": {"group": ("campaign_groups", "id")},
        "campaign_group_member_criteria_military_force_types": {
            "member": ("campaign_group_members", "id"),
            "force_type": ("military_force_types", "key")},
        "campaign_group_member_criteria_factions": {
            "member": ("campaign_group_members", "id"), "faction": ("factions", "key")},
        "campaign_group_member_criteria_campaigns": {"member": ("campaign_group_members", "id")},
        "effect_bonus_value_building_set_junctions": {
            "effect": ("effects", "effect"), "building_set": ("building_sets", "key")},
        "effect_bonus_value_ids_unit_sets": {
            "effect": ("effects", "effect"), "unit_set": ("unit_sets", "key")},
        "effect_bundles_to_effects_junctions": {
            "effect_bundle_key": ("effect_bundles", "key"),
            "effect_key": ("effects", "effect"),
            "effect_scope": ("campaign_effect_scopes", "key")},
        "mercenary_unit_groups": {"unit_record": ("main_units", "unit")},
        "mercenary_pool_to_groups_junctions": {
            "group": ("mercenary_unit_groups", "key"), "pool": ("mercenary_pools", "key"),
            "faction_requirement": ("factions", "key")},
        "unit_set_to_unit_junctions": {
            "unit_record": ("main_units", "unit"), "unit_set": ("unit_sets", "key")},
    }
    for name in ("building_upgrades_junction", "building_downgrade_junctions"):
        references[name] = {field: ("building_levels", "level_name") for field in ("from", "to")}
    for name, fields in references.items():
        for row in own[name]:
            for field, (target, column) in fields.items():
                keys = native[target].column(column) | {
                    r[column] for r in generated.get(target, [])
                } | {r[column] for r in authored.get(target, [])}
                if row[field] and row[field] not in keys:
                    raise ValueError(f"Invalid horde reference: {name}.{field}: {row[field]}")
    validate_scope(native, own)


def validate_scope(native, own):
    by_slot, chains, levels = graph(native)
    if {r["force_type"] for r in own["military_force_type_horde_details"]} != set(SUBTYPES.values()):
        raise ValueError("Camp slots must only alter the four bound Beastmen types")
    for kind in SUBTYPES.values():
        original = native["military_force_type_horde_details"].one(force_type=kind)
        changed = [r for r in own["military_force_type_horde_details"] if r["force_type"] == kind]
        expected = dict(original, primary_slot_template=SLOTS["primary"],
                        secondary_slot_template=SLOTS["secondary"])
        if changed != [expected]:
            raise ValueError(f"Horde force attributes changed: {kind}")
        for feature in ("character_bound", "general_is_irreplaceable"):
            native["military_force_type_feature_junctions"].one(force_type=kind, feature=feature)
    for subtype, kind in SUBTYPES.items():
        selectors = native["agent_subtype_military_force_creation_overrides"].where(
            military_force_type=kind)
        if len(selectors) != 1:
            raise ValueError(f"Ambiguous native bound-horde selector: {kind}")
        group = selectors[0]["valid_group"]
        members = native["campaign_group_members"].where(group=group)
        criteria = [r for m in members for r in native[
            "campaign_group_member_criteria_agent_subtypes"].where(member=m["id"])]
        if {r["agent_subtype"] for r in criteria} != {subtype}:
            raise ValueError(f"Native bound-horde subtype selector changed: {kind}")
    if any(r["from"] != "ARMY" or r["automatic"] != "false"
           for r in own["military_force_type_conversions"]):
        raise ValueError("Bound camps must not add automatic army conversion")
    for role, selected in by_slot.items():
        actual = {r["chain"] for r in own["slot_template_permitted_building_chains"]
                  if r["slot_template"] == SLOTS[role]}
        if actual != selected | {PREFIX + key for key in selected}:
            raise ValueError(f"Private camp slot escaped Beastmen chains: {role}")
    base = {r["building_chain"] for r in native[
        "building_chain_availability_sets"].where(id="wh_main_bas_chs")}
    actual = {r["building_chain"] for r in own["building_chain_availability_sets"]}
    vassal_chains = {VASSAL_PREFIX + key for keys in VASSAL_CHAINS.values()
                     for key in keys}
    if actual != base | {PREFIX + key for key in chains} | vassal_chains:
        raise ValueError("Host building availability lost native city chains")
    if own["main_units"] or own["agent_subtype_military_force_creation_overrides"]:
        raise ValueError("Private camps must preserve native units and subtype selectors")
    allowed = own["building_chain_availabilities"]
    if len(allowed) != 1 or allowed[0]["faction"] != HOST or allowed[0]["campaign"] != CAMPAIGN:
        raise ValueError("Private camp availability must stay with Archaon in IE")
    if any(r["faction"] != HOST or r["culture"] != CULTURE
           for r in own["building_culture_variants"]):
        raise ValueError("Private camp display permissions escaped the host")
    private_levels = {PREFIX + key for key in levels}
    native_effects = [dict(r, building=PREFIX + r["building"])
                      for r in native["building_effects_junction"].rows
                      if r["building"] in levels and r["effect"] not in REMOVED_EFFECTS]
    retained = [r for r in own["building_effects_junction"] if not r["effect"].startswith(PREFIX)]
    order = lambda row: (row["building"], row["effect"], row["effect_scope"])
    if sorted(native_effects, key=order) != sorted(retained, key=order):
        raise ValueError("Private camps must preserve applicable native building effects")
    if any(r["building"] not in private_levels for r in own["building_effects_junction"]):
        raise ValueError("Private camp effects must not alter native buildings")
    for row in own["building_effects_junction"]:
        if row["effect"] in REMOVED_EFFECTS:
            raise ValueError("Dread or ordinary recruitment effect leaked into private camp")
    if any(r["faction_requirement"] != HOST or r["initial_unit_count"] != "0"
           for r in own["mercenary_pool_to_groups_junctions"]):
        raise ValueError("Camp stock must start empty and stay host-specific")
    for row in own["mercenary_unit_groups"]:
        if any(float(row[k]) != 0 for k in (
                "chance_to_replenish", "max_count", "max_replenish_per_turn")):
            raise ValueError("Camp stock must have no automatic replenishment")
    data = script_data(native)
    members = own["unit_set_to_unit_junctions"]
    if ({r["unit_record"] for r in members} != set(data["units"])
            or any(r["unit_set"] != UNIT_SET or r["exclude"] != "false"
                   or r["unit_caste"] or r["unit_class"] or r["unit_category"]
                   for r in members)):
        raise ValueError("Camp capacity and tooltip set must cover exactly the stock units")
    for row in own["campaign_group_member_criteria_factions"]:
        if row["faction"] != HOST or row["context"] != "ORIGINATOR":
            raise ValueError("Camp stance visuals escaped Archaon")
    if any(r["campaign"] != CAMPAIGN for r in own["campaign_group_member_criteria_campaigns"]):
        raise ValueError("Camp stance visuals escaped Immortal Empires")
    native["effect_bonus_value_stance_junctions"].one(
        bonus_value_id="available", effect="wh3_dlc26_effect_stance_availability_settle_enable",
        stance="MILITARY_FORCE_ACTIVE_STANCE_TYPE_SETTLE")
    for table in ("effect_bonus_value_building_set_junctions", "effect_bonus_value_ids_unit_sets"):
        bonuses = native[table].column("bonus_value_id")
        if any(r["bonus_value_id"] not in bonuses for r in own[table]):
            raise ValueError(f"Unsupported native horde bonus: {table}")
