"""Daemon Portals hero recruitment, derived from current native records.

Daemon Portals supplies the foreign buildings; this pack supplies permissions
and building effects only. Do not load the earlier woc_heroes_portals pack.
"""
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MOD.parents[1] / 'tools'))
from db_tables import (read_authored, read_table, run_generator, stable_id,
                       write_localisation, write_table)

PREFIX = 'everchosen_portal_heroes_'
CULTURE = 'wh_main_chs_chaos'
UNDIVIDED = ('wh_main_chs_chaos', 'wh3_main_chs_shadow_legion',
             'wh3_dlc20_chs_kholek', 'wh3_dlc20_chs_sigvald')
GODS = {
    'kho': ('wh3_dlc20_chs_valkia', 'wh3_main_kho_khorne',
            ('wh3_main_kho_bloodreaper', 'wh3_main_kho_cultist')),
    'nur': ('wh3_dlc20_chs_festus', 'wh3_main_nur_nurgle',
            ('wh3_main_nur_plagueridden_death',
             'wh3_main_nur_plagueridden_nurgle', 'wh3_main_nur_cultist')),
    'tze': ('wh3_dlc20_chs_vilitch', 'wh3_main_tze_tzeentch',
            ('wh3_main_tze_iridescent_horror_metal',
             'wh3_main_tze_iridescent_horror_tzeentch', 'wh3_main_tze_cultist')),
    'sla': ('wh3_dlc20_chs_azazel', 'wh3_main_sla_slaanesh',
            ('wh3_main_sla_alluress_shadow', 'wh3_main_sla_alluress_slaanesh',
             'wh3_main_sla_cultist', 'wh3_dlc27_sla_druchii_anointed')),
}
# Native culture/associated unit pairs missing from the Chaos recruitment UI.
CULTURE_UNITS = (
    ('wh3_main_kho_khorne', 'wh3_main_kho_cha_bloodreaper_0'),
    ('wh3_main_kho_khorne', 'wh3_main_kho_cha_cultist_0'),
    ('wh3_main_tze_tzeentch', 'wh3_main_tze_cha_iridescent_horror_tzeentch_0'),
    ('wh3_main_sla_slaanesh', 'wh3_main_sla_cha_alluress_slaanesh_0'),
    ('wh3_main_sla_slaanesh', 'wh3_dlc27_sla_cha_druchii_anointed'),
)
TABLES = '''agent_culture_details building_effects_junction
building_effect_context_expressions building_levels character_skill_nodes
character_skill_node_sets character_skill_node_set_items character_skills
effects effect_bonus_value_agent_junction effect_bonus_value_agent_subtype_junctions
faction_agent_permitted_subtypes
technology_effects_junction technologies campaign_effect_scopes agent_subtypes
factions main_units units_to_groupings_military_permissions
units_to_exclusive_faction_permissions'''.split()
INPUTS = {
    'db.pack': [f'db/{name}_tables' for name in TABLES],
    'daemon_portals.pack': ['db/building_levels_tables'],
}


def permissions(native):
    for god, (champion, culture, subtypes) in GODS.items():
        for subtype in subtypes:
            agent = native['agent_subtypes'].one(key=subtype)
            if agent['auto_generate'] != 'true' or agent['recruitable'] != 'true':
                raise ValueError(f'Hero is not normally recruitable: {subtype}')
            source = [r for r in native['faction_agent_permitted_subtypes'].where(
                subtype=subtype, mod_disabled='false')
                if native['factions'].one(key=r['faction'])['subculture'] == culture.replace('wh3_main_', 'wh3_main_sc_')]
            if not source or len({r['agent'] for r in source}) != 1:
                raise ValueError(f'Ambiguous hero agent type: {subtype}')
            for faction in (*UNDIVIDED, champion):
                yield god, source[0], faction, agent['associated_unit_override']


def rows(native):
    seen_units = set()
    for _, original, faction, unit in permissions(native):
        wanted = dict(original, faction=faction)
        existing = native['faction_agent_permitted_subtypes'].where(
            faction=faction, subtype=original['subtype'])
        if existing and existing != [wanted]:
            raise ValueError(f'Conflicting hero permission: {wanted}')
        if not existing:
            yield 'faction_agent_permitted_subtypes', wanted
        group = native['factions'].one(key=faction)['military_group']
        if native['units_to_exclusive_faction_permissions'].where(
                key=unit, faction=faction, allowed='false'):
            raise ValueError(f'Explicit native hero ban: {faction} {unit}')
        if (unit, group) not in seen_units:
            seen_units.add((unit, group))
            if not native['units_to_groupings_military_permissions'].where(
                    unit=unit, military_group=group):
                yield 'units_to_groupings_military_permissions', {
                    'unit': unit, 'military_group': group}
    details = native['agent_culture_details']
    used = details.column('key')
    for culture, unit in CULTURE_UNITS:
        if not details.where(culture=CULTURE, associated_unit=unit):
            original = details.one(culture=culture, associated_unit=unit)
            yield details.name, dict(original, culture=CULTURE,
                key=stable_id(PREFIX + unit, used))
    for god, (_, _, subtypes) in GODS.items():
        skill = f'wh3_dlc20_skill_authority_{god}_hero'
        native['character_skills'].one(key=skill)
        for subtype in subtypes:
            tree = native['character_skill_node_sets'].one(
                agent_subtype_key=subtype, faction_key='', campaign_key='')
            members = native['character_skill_node_set_items'].where(
                set=tree['key'], mod_disabled='false')
            nodes = [native['character_skill_nodes'].one(key=m['item'])
                     for m in members]
            if any(n['character_skill_key'] == skill for n in nodes):
                continue
            key = PREFIX + 'authority_' + subtype
            tier = max(int(n['tier']) for n in nodes if n['indent'] == '0') + 1
            yield 'character_skill_nodes', dict(nodes[0], key=key,
                campaign_key='', character_skill_key=skill, faction_key='',
                indent='0', tier=str(tier), subculture='wh_main_sc_chs_chaos',
                points_on_creation='1', required_num_parents='0', visible_in_ui='true')
            yield 'character_skill_node_set_items', {
                'set': tree['key'], 'item': key, 'mod_disabled': 'false'}
def validate(native, authored, generated):
    def keys(table, column):
        return native[table].column(column) | {
            r[column] for r in authored.get(table, []) + generated.get(table, [])}

    refs = {
        'building_effects_junction': {
            'building': ('building_levels', 'level_name'),
            'effect': ('effects', 'effect'),
            'context_requirement': ('building_effect_context_expressions', 'key'),
            'effect_scope': ('campaign_effect_scopes', 'key')},
        'effect_bonus_value_agent_subtype_junctions': {
            'subtype': ('agent_subtypes', 'key'), 'effect': ('effects', 'effect')},
        'technology_effects_junction': {
            'technology': ('technologies', 'key'), 'effect': ('effects', 'effect'),
            'effect_scope': ('campaign_effect_scopes', 'key')},
        'faction_agent_permitted_subtypes': {
            'subtype': ('agent_subtypes', 'key'), 'faction': ('factions', 'key')},
        'character_skill_nodes': {'character_skill_key': ('character_skills', 'key')},
        'character_skill_node_set_items': {
            'set': ('character_skill_node_sets', 'key'),
            'item': ('character_skill_nodes', 'key')},
    }
    for table, fields in refs.items():
        for row in authored.get(table, []) + generated.get(table, []):
            for field, (target, column) in fields.items():
                if row[field] and row[field] not in keys(target, column):
                    raise ValueError(f'Invalid {table}.{field}: {row[field]}')
    for expression in authored['building_effect_context_expressions']:
        if expression['expression'].startswith('"'):
            raise ValueError('Context expression must not contain CSV wrapper quotes')
    for row in authored['building_effects_junction']:
        if row['building'].startswith('cf_'):
            if not row['building'].endswith(('_3', '_4', '_5')):
                raise ValueError('Portal heroes require tier three or above')
            if not row['context_requirement'].endswith('_factions'):
                raise ValueError('Portal effects require god-specific faction guards')


def category_localisation(native, generated):
    """Label both native and added Chaos records for shared hero categories."""
    categories = {
        'dignitary': ('混沌使徒', '鲜血收割者与纳垢、色孽、奸奇狂信徒等事务官。具体招募条件以各事务官卡片为准。'),
        'spy': ('瘟疫使徒', '纳垢瘟疫使徒，包含死亡系与纳垢系法术变体。具体招募条件以各事务官卡片为准。'),
        'runesmith': ('混沌祭司', '恐虐狂信徒、虹光惧妖、杜鲁齐受祝者等事务官。具体招募条件以各事务官卡片为准。'),
        'engineer': ('魅魔侍女', '魅魔侍女，包含阴影系与色孽系法术变体。具体招募条件以各事务官卡片为准。'),
    }
    records = {r['key']: r for r in native['agent_culture_details'].rows}
    records.update({r['key']: r for r in generated.get('agent_culture_details', [])})
    for key, row in records.items():
        if row['culture'] != CULTURE or row['agent'] not in categories:
            continue
        name, description = categories[row['agent']]
        for field, text in (('onscreen_name', name), ('description_text', description)):
            yield {'key': f'agent_culture_details_{field}_{key}',
                   'text': text, 'tooltip': 'false'}


def generate(native_root, output):
    native = {name: read_table(native_root / 'db', name) for name in TABLES}
    authored = read_authored(MOD / 'assets/db', native)
    generated = {}
    for table, row in rows(native):
        generated.setdefault(table, []).append(row)
    validate(native, authored, generated)
    for table, records in generated.items():
        write_table(output, native[table], records, 'everchosen_portal_heroes_data')
    write_localisation(output, category_localisation(native, generated),
        'everchosen_portal_heroes_categories')
    print(f'Portal heroes: {sum(map(len, generated.values()))} native-derived rows; '
          'Daemon Portals building references verified')


if __name__ == '__main__':
    run_generator(generate, INPUTS)
