"""Imported troops must cost gold without changing heroes or native factions."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"),
               str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import Table
import beastmen_troop_economy as economy


class BeastmenTroopEconomyTests(unittest.TestCase):
    def setUp(self):
        def unit(key, land, recruitment, upkeep, value, caste="melee_infantry",
                 renown="false"):
            return {"unit": key, "land_unit": land, "caste": caste,
                    "is_renown": renown, "recruitment_cost": str(recruitment),
                    "upkeep_cost": str(upkeep), "multiplayer_cost": str(value)}

        troops = ["unique", "mirror", "ror", "paid", "hero", "summoned"]
        troops.append("wh_dlc03_bst_mon_giant_0")
        records = {
            "factions": [{"key": economy.SOURCE, "military_group": "source"}],
            "groupings_military": [{"military_group": "source"}],
            "units_custom_battle_permissions": [
                {"faction": economy.SOURCE, "unit": key,
                 "campaign_exclusive": "true" if key == "summoned" else "false",
                 "general_unit": "false", "set_piece_character": ""}
                for key in troops],
            "units_to_groupings_military_permissions": [
                {"military_group": "source", "unit": key} for key in troops],
            "units_to_exclusive_faction_permissions": [],
            "main_units": [
                unit("unique", "unique_land", 0, 0, 650),
                unit("mirror", "shared_land", 0, 0, 1900),
                unit("native_paid", "shared_land", 1800, 450, 1900),
                unit("ror", "ror_land", 0, 325, 1250, renown="true"),
                unit("paid", "paid_land", 1000, 250, 900),
                unit("hero", "hero_land", 0, 0, 700, caste="hero"),
                unit("summoned", "summoned_land", 0, 0, 0),
                unit("wh_dlc03_bst_mon_giant_0", "beastmen_giant", 0, 0, 1400),
                unit("wh_main_chs_mon_giant", "chaos_giant", 1500, 375, 1400),
            ],
            "main_unit_faction_overrides": [
                {"faction_set": economy.NATIVE_SET,
                 "unit": "wh2_dlc09_tmb_cha_tomb_prince_0", "name_group": "",
                 "recruitment_cost": "1000", "upkeep_cost": "250"}],
        }
        self.native = {name: Table(name, [], "0", rows)
                       for name, rows in records.items()}

    def test_fills_free_fields_using_native_equivalents_and_keeps_paid_fields(self):
        self.assertEqual(economy.unit_costs(self.native), {
            "unique": (650, 163), "mirror": (1800, 450), "ror": (1250, 325),
            "wh_dlc03_bst_mon_giant_0": (1500, 375)})

    def test_overrides_only_the_host_set_without_mutating_original_units(self):
        before = deepcopy(self.native)
        rows = list(economy.rows(self.native))
        self.assertEqual(len(rows), 4)
        for table, row in rows:
            self.assertEqual(table, "main_unit_faction_overrides")
            self.assertEqual(row["faction_set"], economy.FACTION_SET)
            self.assertEqual(row["name_group"], "")
            self.assertGreater(int(row["recruitment_cost"]), 0)
            self.assertGreater(int(row["upkeep_cost"]), 0)
        self.assertEqual(self.native, before)


if __name__ == "__main__":
    unittest.main()
