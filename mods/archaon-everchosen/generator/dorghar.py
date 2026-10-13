"""Validate the integrated mount layouts and adapt Archaon's native skill slot."""

TABLES = (
    'ancillaries',
    'ancillaries_included_agent_subtypes',
    'ancillaries_required_skills',
    'ancillary_info',
    'ancillary_to_effects',
    'ancillary_to_included_agents',
    'battle_animations_table',
    'battle_entities',
    'battle_personalities',
    'campaign_map_attrition_unit_immunities',
    'campaign_mount_animation_set_overrides',
    'campaign_mounts',
    'character_skill_level_details',
    'character_skill_level_to_ancillaries_junctions',
    'character_skill_level_to_effects_junctions',
    'character_skill_node_set_items',
    'character_skill_nodes',
    'character_skills',
    'character_skills_to_level_reached_criterias',
    'effect_bundles',
    'effect_bundles_to_effects_junctions',
    'effects',
    'land_units',
    'land_units_to_battle_personalities_junctions',
    'land_units_to_unit_abilites_junctions',
    'main_units',
    'melee_weapons',
    'mounts',
    'projectiles',
    'special_ability_groups_to_units_junctions',
    'special_ability_to_invalid_usage_flags',
    'ui_unit_bullet_point_unit_overrides',
    'unit_abilities',
    'unit_abilities_to_additional_ui_effects_juncs',
    'unit_attributes_groups',
    'unit_attributes_to_groups_junctions',
    'unit_set_to_unit_junctions',
    'unit_special_abilities',
    'unit_variants',
    'units_custom_battle_mounts',
    'units_custom_battle_permissions',
    'variants',
)


def rows(native):
    node = native['character_skill_nodes'].one(
        key='wh_main_skill_node_chs_archaon_unique_auth')
    sets = {row['set'] for row in
            native['character_skill_node_set_items'].where(item=node['key'])}
    owners = {row['agent_subtype_key'] for row in
              native['character_skill_node_sets'].rows if row['key'] in sets}
    if owners != {'wh_main_chs_archaon'}:
        raise ValueError("Dorghar's skill slot is shared with another lord")
    node['tier'] = '5'
    yield 'character_skill_nodes', node
