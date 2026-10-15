"""Count native hero families for an explicitly selected capacity test pack."""
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path[:0] = [str(ROOT / "tools"),
                str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import read_authored, read_table, run_generator, write_table
import hero_families

BUNDLE = "everchosen_hero_capacity_test"
SCOPE = "faction_to_faction_own_unseen"
FRAGMENT = "everchosen_hero_capacity_test_generated"
# Representative native factions, without incidental invasion-army rosters.
SOURCE_FACTIONS = (
    "wh_main_chs_chaos", "wh_dlc03_bst_beastmen", "wh_dlc08_nor_norsca",
    "wh3_dlc23_chd_zhatan", "wh3_main_dae_daemon_prince",
    "wh3_main_kho_exiles_of_khorne", "wh3_main_nur_poxmakers_of_nurgle",
    "wh3_main_sla_seducers_of_slaanesh",
    "wh3_main_tze_oracles_of_tzeentch",
)
CAP_EFFECTS = {
    "champion": "wh_main_effect_agent_cap_increase_champion_exalted_hero",
    "dignitary": "wh3_main_effect_agent_cap_increase_nur_cultist",
    "engineer": "wh3_main_effect_agent_cap_increase_sla_alluress",
    "runesmith": "wh3_main_effect_agent_cap_increase_tze_iridescent_horror",
    "spy": "wh3_main_effect_agent_cap_increase_nur_plagueridden",
    "wizard": "wh_main_effect_agent_cap_increase_wizard_chaos_sorcerer",
}
TABLES = sorted(set(hero_families.TABLES) | {
    "effects", "effect_bonus_value_agent_junction", "effect_bundles",
    "effect_bundles_to_effects_junctions", "campaign_effect_scopes",
})
NATIVE_INPUTS = {"db.pack": [f"db/{name}_tables" for name in TABLES]}


def capacity_families(native):
    """Return distinct ordinary hero families in each native shared pool."""
    metadata = hero_families.script_data(native)
    for faction in SOURCE_FACTIONS:
        native["factions"].one(key=faction)
    families = {agent: set() for agent in CAP_EFFECTS}
    for row in native["faction_agent_permitted_subtypes"].rows:
        if (row["faction"] in SOURCE_FACTIONS
                and row["mod_disabled"] == "false"
                and row["subtype"] in metadata):
            families[row["agent"]].add(metadata[row["subtype"]]["family"])
    return {agent: sorted(members) for agent, members in families.items()}


def rows(native, families):
    """Clone only cap bindings; no availability or recruitment rows change."""
    scope = native["campaign_effect_scopes"].one(key=SCOPE)
    if (scope["source"], scope["target"]) != ("faction", "faction"):
        raise ValueError("Hero-capacity test requires a faction-wide scope")
    for agent, original in CAP_EFFECTS.items():
        bindings = native["effect_bonus_value_agent_junction"].where(
            effect=original)
        if bindings != [{"effect": original, "bonus_value_id": "cap",
                         "agent": agent}]:
            raise ValueError(f"Native hero cap binding changed: {original}")
        if not families[agent]:
            raise ValueError(f"No ordinary hero families in {agent}")
        effect = BUNDLE + "_" + agent
        yield "effects", dict(native["effects"].one(effect=original),
                              effect=effect)
        yield "effect_bonus_value_agent_junction", dict(bindings[0],
                                                        effect=effect)
        yield "effect_bundles_to_effects_junctions", {
            "effect_bundle_key": BUNDLE, "effect_key": effect,
            "effect_scope": SCOPE, "value": f"{len(families[agent]):.4f}",
            "advancement_stage": "start_turn_completed",
        }


def generate(vanilla, output):
    native = {name: read_table(vanilla / "db", name) for name in TABLES}
    authored = read_authored(MOD / "assets/db", native)
    bundle, = authored["effect_bundles"]
    if bundle["key"] != BUNDLE or bundle["bundle_target"] != "faction":
        raise ValueError("Hero capacity test bundle must target a faction")
    families = capacity_families(native)
    generated = {}
    for name, row in rows(native, families):
        generated.setdefault(name, []).append(row)
    for name, values in generated.items():
        write_table(output, native[name], values, FRAGMENT)
    print("Hero-capacity test: " + ", ".join(
        f"{agent}=+{len(members)}" for agent, members in families.items()))


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
