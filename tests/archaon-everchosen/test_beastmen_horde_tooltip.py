"""Building display sets must select exact stock without replacing unit caps."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"),
               str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import Table
import beastmen_hordes as hordes


class BeastmenHordeTooltipTests(unittest.TestCase):
    def test_each_building_gets_its_own_exact_recruitment_list(self):
        data = {"buildings": {
            hordes.PREFIX + "gors_1": ["ungor", "ungor_spears"],
            hordes.PREFIX + "gors_2": ["gor", "ungor", "ungor_spears"],
            hordes.PREFIX + "minotaurs_1": ["minotaur"],
        }}
        before = deepcopy(data)
        rows = list(hordes.tooltip_rows(data))
        sets = {r["key"] for table, r in rows if table == "unit_sets"}
        self.assertEqual(sets, set(data["buildings"]))
        members = [r for table, r in rows
                   if table == "unit_set_to_unit_junctions"]
        self.assertEqual(len(members), 6)
        for building, expected in data["buildings"].items():
            selected = [r for r in members if r["unit_set"] == building]
            self.assertEqual({r["unit_record"] for r in selected}, set(expected))
            self.assertTrue(all(r["exclude"] == "false" and not r["unit_caste"]
                                and not r["unit_class"] and not r["unit_category"]
                                for r in selected))
        self.assertNotIn(hordes.UNIT_SET, sets)
        self.assertEqual(data, before)

    def test_shared_capacity_set_keeps_all_stock_units(self):
        data = {"buildings": {hordes.PREFIX + "gors_1": ["ungor"]},
                "units": {"ungor": {"cap": 4, "chance": 40},
                          "minotaur": {"cap": 2, "chance": 20}},
                "horn_bonus": {}}
        native = {"mercenary_pool_to_groups_junctions":
                  Table("mercenary_pool_to_groups_junctions", ["key"], "0", [])}
        with patch.object(hordes, "script_data", return_value=data):
            rows = list(hordes.stock_rows(native))
        shared = [r for table, r in rows
                  if table == "unit_set_to_unit_junctions"
                  and r["unit_set"] == hordes.UNIT_SET]
        self.assertEqual({r["unit_record"] for r in shared}, {"ungor", "minotaur"})
        self.assertEqual(len(shared), 2)


if __name__ == "__main__":
    unittest.main()
