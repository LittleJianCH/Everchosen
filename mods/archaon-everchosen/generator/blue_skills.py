"""Replace incompatible effects while retaining each native blue-line slot."""

PREFIX = "everchosen_subjugation_skill_"
ADAPTATIONS = {
    "wh_dlc08_skill_nor_lord_campaign_despoilers": "nor_despoilers",
    "wh_dlc08_skill_nor_wulfrik_campaign_devourers_of_flesh": "nor_devourers",
    "wh_dlc08_skill_nor_throgg_campaign_masters_of_the_fen": "nor_fen",
    "wh3_dlc27_skill_nor_sayl_unique_9": "nor_mists",
    "wh3_dlc23_skill_chd_campaign_post_battle": "chd_tyrant",
    "wh_dlc03_skill_bst_lord_gathering_of_beasts": "bst_gathering",
    "wh_dlc03_skill_bst_lord_children_of_chaos": "bst_children",
}
# Unchanged junctions are preserved. A missing replacement means remove this
# native junction; the new fixed bonus is authored in the product's assets.
REPLACED_EFFECTS = {
    "wh3_dlc27_effect_force_all_campaign_razing_income_spoils_text":
        "wh_main_effect_force_all_campaign_razing_income",
    "wh_dlc08_effect_skill_agent_cap_increase_champion_skin_wolf_werekin": None,
    "wh_dlc08_effect_skill_agent_recruitment_xp_champion_norsca": None,
    "wh3_dlc27_effect_force_stat_recruit_rank_nor_fimir_units_heroes":
        "wh3_dlc27_effect_force_recruit_rank_nor_fimirs",
    "wh_dlc08_effect_agent_cap_increase_dignitary_fimir_balefiend": None,
    "wh3_dlc27_effect_agent_cap_increase_runesmith_fimir_noble": None,
    "wh3_dlc27_effect_agent_recruitment_xp_runesmith_norsca": None,
    "wh3_dlc23_effect_force_chd_campaign_post_battle_labour_dummy":
        "wh3_dlc20_effect_pooled_resource_mod_souls_battle",
    "wh_main_effect_force_all_recruitment_points": None,
    "wh_dlc03_effect_bloodlust_modifier_characters": None,
}


def key(skill):
    return PREFIX + ADAPTATIONS[skill] if skill in ADAPTATIONS else skill


def rows(native):
    junctions = native["character_skill_level_to_effects_junctions"]
    for source in ADAPTATIONS:
        yield "character_skills", dict(
            native["character_skills"].one(key=source), key=key(source),
            localised_name="", localised_description="")
        changed = False
        for row in junctions.where(character_skill_key=source):
            effect = row["effect_key"]
            if effect in REPLACED_EFFECTS:
                changed = True
                replacement = REPLACED_EFFECTS[effect]
                if replacement is None:
                    continue
                native["effects"].one(effect=replacement)
                scope = ("general_to_force_own" if "souls" in replacement
                         else row["effect_scope"])
                row = dict(row, effect_key=replacement, effect_scope=scope)
            yield junctions.name, dict(row, character_skill_key=key(source))
        if not changed:
            raise ValueError("Native blue-line adaptation no longer matches: " + source)


def validate(native, generated, authored):
    levels = "character_skill_level_to_effects_junctions"
    rows = generated.get(levels, []) + authored.get(levels, [])
    effects = native["effects"].column("effect") | {
        r["effect"] for r in authored.get("effects", [])}
    scopes = native["campaign_effect_scopes"]
    keys = {key(source) for source in ADAPTATIONS}
    if keys & native["character_skills"].column("key"):
        raise ValueError("Adapted blue-line skill key already exists")
    for source in ADAPTATIONS:
        old = {r["level"] for r in native[levels].where(character_skill_key=source)}
        new = {r["level"] for r in rows if r["character_skill_key"] == key(source)}
        if old != new:
            raise ValueError("Blue-line skill point cost changed: " + source)
    for row in rows:
        if row["character_skill_key"].startswith(PREFIX):
            if (row["character_skill_key"] not in keys or
                    row["effect_key"] not in effects or
                    row["effect_scope"] not in scopes.column(scopes.header[0])):
                raise ValueError("Invalid blue-line effect: " + str(row))
