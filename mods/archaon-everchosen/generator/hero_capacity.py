"""Faction-scoped sources for independent ordinary hero-family capacities."""
from host import HOST
from db_tables import lua_literal, write_localisation, write_table
import hero_appearance
import hero_families

PREFIX = "everchosen_hero_capacity_"
BUNDLE = PREFIX + "limits"
STATIC_DATA = "everchosen_hero_capacity_data"
FRAGMENT = "everchosen_hero_capacity"
HOST_CONTEXT = PREFIX + "host"
SCOPE = "faction_to_faction_own_unseen"
CAP_EFFECTS = {
    "champion": "wh_main_effect_agent_cap_increase_champion_exalted_hero",
    "wizard": "wh_main_effect_agent_cap_increase_wizard_chaos_sorcerer",
    "dignitary": "wh3_main_effect_agent_cap_increase_nur_cultist",
    "engineer": "wh3_main_effect_agent_cap_increase_sla_alluress",
    "runesmith": "wh3_main_effect_agent_cap_increase_tze_iridescent_horror",
    "spy": "wh3_main_effect_agent_cap_increase_nur_plagueridden",
}
NATIVE_FAMILIES = {
    "champion": ("wh_main_chs_exalted_hero",),
    "wizard": ("wh_main_chs_chaos_sorcerer",),
}
# Dedicated heroes are promotion forms, never an extra direct recruit source.
PROMOTED_FAMILIES = {
    "wh3_dlc20_chs_exalted_hero_mkho": "wh_main_chs_exalted_hero",
    "wh3_dlc20_chs_exalted_hero_mnur": "wh_main_chs_exalted_hero",
    "wh3_dlc24_chs_exalted_hero_mtze": "wh_main_chs_exalted_hero",
    "wh3_dlc27_chs_exalted_hero_msla": "wh_main_chs_exalted_hero",
    "wh3_dlc25_chs_sorcerer_mnur": "wh_main_chs_chaos_sorcerer",
    "wh3_dlc20_chs_sorcerer_msla": "wh_main_chs_chaos_sorcerer",
    "wh3_dlc20_chs_sorcerer_mtze": "wh_main_chs_chaos_sorcerer",
}
NATIVE_BUILDINGS = {
    "champion": tuple("wh3_dlc20_woc_dark_fortress_warriors_" + str(tier)
                      for tier in (1, 2, 3)),
    "wizard": tuple("wh3_dlc20_woc_dark_fortress_shrine_" + str(tier)
                    for tier in (1, 2, 3)),
}
# These are optional pack building keys, never database foreign-key references.
PORTAL_FAMILIES = {
    "khorne": "wh3_main_kho_bloodreaper",
    "nurgle": "wh3_main_nur_plagueridden",
    "tzeentch": "wh3_main_tze_iridescent_horror",
    "slaanesh": "wh3_main_sla_alluress",
}
CULTIST_SOURCES = (
    ("wh3_main_kho_cultist", "warriors_2", "kho"),
    ("wh3_main_kho_cultist", "warriors_3", "kho"),
    ("wh3_main_nur_cultist", "chaos_monsters_2", "nur"),
    ("wh3_main_tze_cultist", "shrine_2", "tze"),
    ("wh3_main_tze_cultist", "shrine_3", "tze"),
    ("wh3_main_sla_cultist", "marauder_3", "sla"),
)
# Native one-level skill effects retained after the relevant lord transfers.
# The value and on-map scope are read from the current native skill record.
SKILL_SOURCES = (
    ("wh_dlc08_skill_chs_lord_unique_archaon_4",
     CAP_EFFECTS["champion"], NATIVE_FAMILIES["champion"]),
    ("wh3_dlc20_skill_daemon_prince_tzeentch_special_2",
     CAP_EFFECTS["wizard"], NATIVE_FAMILIES["wizard"]),
    ("wh3_dlc23_skill_chd_astragoth_infernal_lord",
     "wh2_main_effect_agent_cap_increase_all_heroes", ()),
    ("wh3_dlc23_skill_innate_chd_convoy_overseer_retired_daemonsmither",
     "wh3_dlc23_effect_agent_cap_increase_champion_chaos_dwarfs",
     ("wh3_dlc23_chd_bull_centaur_taurruk",)),
    ("wh3_dlc27_skill_nor_sayl_unique_4",
     "wh_dlc08_effect_agent_cap_increase_wizard",
     ("wh_dlc08_nor_shaman_sorcerer",)),
    ("wh3_dlc27_skill_nor_sayl_unique_9",
     "wh3_dlc27_effect_agent_cap_increase_runesmith_fimir_noble",
     ("wh3_dlc27_nor_fimir_noble",)),
    ("wh3_main_skill_nur_kugath_self_2",
     "wh3_main_effect_agent_cap_increase_nur_plagueridden",
     ("wh3_main_nur_plagueridden",)),
    ("wh_dlc08_skill_nor_throgg_campaign_masters_of_the_fen",
     "wh_dlc08_effect_agent_cap_increase_dignitary_fimir_balefiend",
     ("wh_dlc08_nor_fimir_balefiend",)),
    ("wh_dlc08_skill_nor_wulfrik_campaign_devourers_of_flesh",
     "wh_dlc08_effect_skill_agent_cap_increase_champion_skin_wolf_werekin",
     ("wh_dlc08_nor_skin_wolf_werekin",)),
)
TABLES = sorted(set(hero_families.TABLES) | {
    "effects", "effect_bonus_value_agent_junction",
    "effect_bonus_value_agent_subtype_junctions", "effect_bundles",
    "building_levels", "building_effects_junction", "campaign_effect_scopes",
    "building_effect_context_expressions",
    "character_skill_level_to_effects_junctions",
})


def source_effect(family):
    return PREFIX + "source_" + family


def recruitable_heroes(native):
    """Keep dedicated Chaos heroes on their native soul-promotion path."""
    heroes, metadata = hero_appearance.supported_heroes(native)
    return ({subtype: record for subtype, record in heroes.items()
             if metadata[subtype]["family"] not in PROMOTED_FAMILIES}, metadata)


def families(native):
    """Group direct recruits; promotion forms use their original hero slot."""
    heroes, metadata = recruitable_heroes(native)
    result = {}
    for subtype, permission in sorted(heroes.items()):
        family = metadata[subtype]["family"]
        record = result.setdefault(family, {
            "agent": permission["agent"],
            "name_key": metadata[subtype]["name_key"], "subtypes": [],
            "promoted_subtypes": [],
            "source_effect": source_effect(family)})
        if record["agent"] != permission["agent"]:
            raise ValueError(f"Hero family spans agent classes: {family}")
        record["subtypes"].append(subtype)
    all_heroes, _ = hero_appearance.supported_heroes(native)
    for subtype in sorted(all_heroes):
        original = PROMOTED_FAMILIES.get(metadata[subtype]["family"])
        if original:
            result[original]["promoted_subtypes"].append(subtype)
    return result


def script_data(native):
    grouped = families(native)
    agents = native["agent_subtypes"]
    # Unique heroes and chieftains can occupy the native parent class too.
    # Ignore globally ambiguous classes instead of assigning one arbitrarily.
    contributed = {row["key"] for row in agents.rows
                   if row["contributes_to_agent_cap"] == "true"}
    classes = {}
    for row in native["faction_agent_permitted_subtypes"].rows:
        if (row["subtype"] in contributed and row["agent"] in CAP_EFFECTS
                and row["mod_disabled"] == "false"):
            classes.setdefault(row["subtype"], set()).add(row["agent"])
    counted = {subtype: next(iter(values))
               for subtype, values in sorted(classes.items())
               if len(values) == 1}
    skills = []
    for skill, effect, targets in SKILL_SOURCES:
        row = native["character_skill_level_to_effects_junctions"].one(
            character_skill_key=skill, effect_key=effect)
        if (row["level"] != "1" or row["effect_scope"] not in (
                "character_to_faction_unseen",
                "character_to_faction_when_on_map_unseen")):
            raise ValueError(f"Native hero-capacity skill changed: {skill}")
        selected = list(targets) if targets else sorted(grouped)
        if set(selected) - grouped.keys():
            raise ValueError(f"Missing capacity skill hero family: {skill}")
        skills.append({"key": skill, "families": selected,
                       "value": float(row["value"]),
                       "on_map": row["effect_scope"] ==
                       "character_to_faction_when_on_map_unseen"})
    external = {
        "marker_path": "db/building_effect_context_expressions_tables/woc_hp",
        "portals": [{"building": "cf_building_level_" + god
                     + "_daemon_portal_" + str(tier), "family": family,
                     "value": 2 if tier == 5 else 1}
                    for god, family in PORTAL_FAMILIES.items()
                    for tier in (3, 4, 5)],
        "cultists": [{"building": "wh3_dlc20_woc_dark_fortress_" + building,
                      "family": family,
                      "technology": "wh3_dlc20_chs_" + god
                      + "_shared_gift_upgrade_authority", "value": 1}
                     for family, building, god in CULTIST_SOURCES],
        "anointed": {
            "building": "wh3_dlc20_woc_dark_fortress_warriors_3",
            "family": "wh3_dlc27_sla_druchii_anointed", "value": 1,
            "product": "TW_WH3_TIDES_OF_TORMENT_SLA"},
    }
    return {
        "bundle": BUNDLE, "families": grouped,
        "subtypes": {
            subtype: {"family": family, "agent": record["agent"],
                      "effect": PREFIX + "limit_" + subtype,
                      "base": int(agents.one(key=subtype)["cap"])}
            for family, record in grouped.items()
            for subtype in record["subtypes"]},
        "classes": {agent: PREFIX + "parent_" + agent for agent in CAP_EFFECTS},
        "native_families": NATIVE_FAMILIES,
        "counted_subtypes": counted, "external": external, "skills": skills,
    }


def rows(native):
    config = script_data(native)
    template = native["effect_bonus_value_agent_subtype_junctions"].one(
        bonus_value_id="cap", effect="wh2_main_effect_agent_cap_increase_lzd_slann",
        subtype="wh2_main_lzd_slann_mage_priest")
    hidden = dict(native["effects"].one(effect=template["effect"]), priority="0")
    for family, record in config["families"].items():
        effect = record["source_effect"]
        display = native["effects"].one(effect=CAP_EFFECTS[record["agent"]])
        yield "effects", dict(display, effect=effect, priority="1")
        for subtype in record["subtypes"]:
            yield "effect_bonus_value_agent_subtype_junctions", dict(
                template, effect=effect, subtype=subtype)
    for subtype, record in config["subtypes"].items():
        yield "effects", dict(hidden, effect=record["effect"])
        yield "effect_bonus_value_agent_subtype_junctions", dict(
            template, effect=record["effect"], subtype=subtype)
    for agent, effect in config["classes"].items():
        original = CAP_EFFECTS[agent]
        binding = native["effect_bonus_value_agent_junction"].one(
            effect=original, bonus_value_id="cap", agent=agent)
        yield "effects", dict(hidden, effect=effect)
        yield "effect_bonus_value_agent_junction", dict(binding, effect=effect)
    native["campaign_effect_scopes"].one(key=SCOPE)
    bundle = native["effect_bundles"].one(
        key="wh2_dlc09_books_of_nagash_reward_1")
    yield "effect_bundles", dict(
        bundle, key=BUNDLE, localised_description="", localised_title="",
        bundle_target="faction", priority="0", ui_icon="agent.png")
    context = native["building_effect_context_expressions"].one(
        key="AislinnBuiltInColony")
    campaign = native["building_effect_context_expressions"].one(
        key="IsImmortalEmpires")["expression"]
    single_player = native["building_effect_context_expressions"].one(
        key="IsSPChaosCampaign")["expression"].split(" && ", 1)[1]
    yield "building_effect_context_expressions", dict(
        context, key=HOST_CONTEXT,
        expression=(context["expression"].replace('"wh3_dlc27_hef_aislinn"',
                                                  f'"{HOST}"')
                    + " && Region.Owner.IsHuman && " + campaign
                    + " && " + single_player),
        display_only_active_effects="true")
    for agent, members in NATIVE_FAMILIES.items():
        for family in members:
            record = config["families"][family]
            effect = PREFIX + "native_" + family
            yield "effects", dict(hidden, effect=effect)
            for subtype in record["subtypes"]:
                yield "effect_bonus_value_agent_subtype_junctions", dict(
                    template, effect=effect, subtype=subtype)
            for building in NATIVE_BUILDINGS[agent]:
                row = native["building_effects_junction"].one(
                    building=building, effect=CAP_EFFECTS[agent])
                if (row["context_requirement"] or row["effect_scope"] != SCOPE):
                    raise ValueError(f"Native WoC capacity context changed: {building}")
                yield "building_effects_junction", dict(
                    row, effect=effect, context_requirement=HOST_CONTEXT)


def localisation(native):
    for record in families(native).values():
        yield {
            "key": "effects_description_" + record["source_effect"],
            "text": "英雄招募容量：{{tr:" + record["name_key"] + "}}%+n",
            "tooltip": "false"}


def write_assets(native, output):
    """Main and test packs share identical records and generated script data."""
    generated = {}
    for table, row in rows(native):
        generated.setdefault(table, []).append(row)
    for table, values in generated.items():
        write_table(output, native[table], values, FRAGMENT)
    write_localisation(output, localisation(native), FRAGMENT)
    path = output / f"script/campaign/mod/{STATIC_DATA}.lua"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f'core:add_static_object("{STATIC_DATA}", '
                    + lua_literal(script_data(native)) + ")\n",
                    encoding="utf-8")
