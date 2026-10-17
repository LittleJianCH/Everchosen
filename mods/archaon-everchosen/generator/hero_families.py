"""Native names and icons for the hero families shown by Archaon's UI."""

TABLES = ("agent_subtypes", "agent_culture_details",
          "faction_agent_permitted_subtypes", "factions", "main_units",
          "cultures_subcultures")

SUBCULTURES = {
    "wh_main_sc_chs_chaos", "wh_dlc03_sc_bst_beastmen",
    "wh_dlc08_sc_nor_norsca", "wh3_dlc23_sc_chd_chaos_dwarfs",
    "wh3_main_sc_dae_daemons", "wh3_main_sc_kho_khorne",
    "wh3_main_sc_nur_nurgle", "wh3_main_sc_sla_slaanesh",
    "wh3_main_sc_tze_tzeentch",
}

# Merge spell lores of one hero, preserving the separate marked hero families.
# The name keys refer to native labels without a spell-lore suffix.
FAMILIES = {
    "wh_dlc03_bst_bray_shaman": (
        "agent_culture_details_onscreen_name_552",
        ("wh_dlc03_bst_bray_shaman_beasts",
         "wh_dlc03_bst_bray_shaman_death",
         "wh_dlc03_bst_bray_shaman_shadows",
         "wh_dlc03_bst_bray_shaman_wild")),
    "wh_dlc08_nor_shaman_sorcerer": (
        "agent_culture_details_onscreen_name_2064663880",
        ("wh_dlc08_nor_shaman_sorcerer_death",
         "wh_dlc08_nor_shaman_sorcerer_fire",
         "wh_dlc08_nor_shaman_sorcerer_metal")),
    "wh_dlc08_nor_fimir_balefiend": (
        "agent_culture_details_onscreen_name_130851887",
        ("wh_dlc08_nor_fimir_balefiend_fire",
         "wh_dlc08_nor_fimir_balefiend_shadow")),
    "wh3_dlc23_chd_daemonsmith_sorcerer": (
        "agent_culture_details_onscreen_name_613252808",
        ("wh3_dlc23_chd_daemonsmith_sorcerer_death",
         "wh3_dlc23_chd_daemonsmith_sorcerer_fire",
         "wh3_dlc23_chd_daemonsmith_sorcerer_hashut",
         "wh3_dlc23_chd_daemonsmith_sorcerer_metal")),
    "wh_main_chs_chaos_sorcerer": (
        "agent_culture_details_onscreen_name_533",
        ("wh_main_chs_chaos_sorcerer_death",
         "wh_main_chs_chaos_sorcerer_fire",
         "wh_main_chs_chaos_sorcerer_metal",
         "wh_dlc07_chs_chaos_sorcerer_shadow")),
    "wh3_dlc20_chs_sorcerer_msla": (
        "ui_text_replacements_localised_text_marked_chaos_sorcerers_chs_azazel",
        ("wh3_dlc20_chs_sorcerer_shadows_msla",
         "wh3_dlc20_chs_sorcerer_slaanesh_msla")),
    "wh3_dlc20_chs_sorcerer_mtze": (
        "ui_text_replacements_localised_text_marked_chaos_sorcerers_chs_vilitch",
        ("wh3_dlc20_chs_sorcerer_metal_mtze",
         "wh3_dlc20_chs_sorcerer_tzeentch_mtze")),
    "wh3_dlc25_chs_sorcerer_mnur": (
        "units_custom_battle_permissions_override_name_"
        "wh3_dlc25_chs_cha_chaos_sorcerer_death_mnurwh_main_chs_chaosfalse",
        ("wh3_dlc25_chs_sorcerer_death_mnur",
         "wh3_dlc25_chs_sorcerer_nurgle_mnur")),
    "wh3_main_nur_plagueridden": (
        "agent_culture_details_onscreen_name_2014253694",
        ("wh3_main_nur_plagueridden_death",
         "wh3_main_nur_plagueridden_nurgle")),
    "wh3_main_sla_alluress": (
        "agent_culture_details_onscreen_name_1412286428",
        ("wh3_main_sla_alluress_shadow",
         "wh3_main_sla_alluress_slaanesh")),
    "wh3_main_tze_iridescent_horror": (
        "agent_culture_details_onscreen_name_1161079929",
        ("wh3_main_tze_iridescent_horror_metal",
         "wh3_main_tze_iridescent_horror_tzeentch")),
}

# This native subtype label is an inline translation reference to its unit.
NAME_KEYS = {
    "wh3_dlc27_chs_exalted_hero_msla":
        "land_units_onscreen_name_wh3_dlc27_chs_cha_exalted_hero_msla",
}


def script_data(native):
    """Return subtype display metadata, never permissions or capacities.

    The campaign UI discovers the actual available subtypes from native
    buttons. A subtype absent here keeps its own family and native CCO label.
    """
    cultures = {row["subculture"]: row["culture"]
                for row in native["cultures_subcultures"].rows}
    factions = {row["key"]: cultures[row["subculture"]]
                for row in native["factions"].rows
                if row["subculture"] in SUBCULTURES}
    permitted = {}
    for row in native["faction_agent_permitted_subtypes"].rows:
        if (row["faction"] in factions
                and row["agent"] not in ("general", "colonel", "minister")
                and row["mod_disabled"] == "false"):
            permitted.setdefault(row["subtype"], set()).add(
                (row["agent"], factions[row["faction"]]))
    units = {row["unit"]: row for row in native["main_units"].rows}
    heroes = {
        row["key"]: row for row in native["agent_subtypes"].rows
        if row["key"] in permitted
        and all(row[field] == "true" for field in (
            "auto_generate", "recruitable", "contributes_to_agent_cap",
            "show_in_ui"))
        and units[row["associated_unit_override"]]["caste"] == "hero"
    }
    families = {subtype: (family, name)
                for family, (name, members) in FAMILIES.items()
                for subtype in members}
    missing = families.keys() - heroes.keys()
    if missing:
        raise ValueError(f"Missing ordinary hero family members: {missing}")

    result = {}
    for subtype, row in sorted(heroes.items()):
        family, name = families.get(subtype, (
            subtype, NAME_KEYS.get(
                subtype, "agent_subtypes_onscreen_name_override_" + subtype)))
        # Culture records supply icons for noncasters such as the Gorebull
        # and Fimir Noble whose subtype small_icon is empty.
        culture_icons = sorted({detail["small_icon"]
                                for detail in native[
                                    "agent_culture_details"].rows
                                if detail["associated_unit"] == row[
                                    "associated_unit_override"]
                                and detail["small_icon"]})
        icon = row["small_icon"] or next(iter(culture_icons), "")
        if not icon:
            raise ValueError(f"Missing native hero-family icon: {subtype}")
        original = sorted((detail for detail in
                           native["agent_culture_details"].rows
                           if detail["associated_unit"] == row[
                               "associated_unit_override"]
                           and detail["recruitable_in_ui"] == "true"
                           and (detail["agent"], detail["culture"])
                           in permitted[subtype]),
                          key=lambda detail: detail["key"])
        if name.startswith("agent_culture_details_onscreen_name_"):
            description = name.replace("_onscreen_name_", "_description_text_", 1)
        elif original:
            description = "agent_culture_details_description_text_" + original[0]["key"]
        else:
            description = "agent_subtypes_description_text_override_" + subtype
        result[subtype] = {"family": family, "name_key": name, "icon": icon,
                           "description_key": description}
    return result
