"""RoR pool access must preserve native gates and avoid duplicate stock."""
from copy import deepcopy
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"),
               str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import Table
import regiments_of_renown as ror
import roster_permissions as roster


class RegimentsOfRenownTests(unittest.TestCase):
    def setUp(self):
        source = roster.SOURCE_FACTIONS[0]
        factions = [ror.HOST, *roster.SOURCE_FACTIONS, *ror.EXTRA_RORS]
        hunt = "wh_dlc08_nor_mon_frost_wyrm_ror_0"
        units = ["native", "new", "gated", "ordinary", "disabled", "foreign",
                 "denied", hunt]
        records = {
            "factions": [{"key": f, "military_group": f + "_group",
                          "subculture": f + "_subculture"} for f in factions],
            "groupings_military": [{"military_group": f + "_group"}
                                   for f in factions],
            "main_units": [{"unit": u, "caste": "monster",
                            "is_renown": "false" if u == "ordinary" else "true"}
                           for u in units],
            "units_custom_battle_permissions": [
                {"unit": u, "faction": source, "campaign_exclusive": "false",
                 "general_unit": "false", "set_piece_character": ""}
                for u in units],
            "units_to_groupings_military_permissions": [
                {"unit": u, "military_group": source + "_group"} for u in units],
            "units_to_exclusive_faction_permissions": [
                {"key": "denied", "faction": ror.HOST, "allowed": "false"}],
            "mercenary_pools": [{"key": f + "_pool",
                                 "recruitment_source": "native_renown_source",
                                 "ui_recruitment_info": "renown"}
                                for f in factions],
            "faction_to_mercenary_set_junctions": [
                {"faction": f, "mercenary_set": f + "_pool"} for f in factions],
            "mercenary_unit_groups": [
                {"key": u + "_group", "unit_record": u,
                 "max_count": "0" if u == "disabled" else "1",
                 "chance_to_replenish": "100.0000",
                 "use_partial_replenishment": "true",
                 "max_replenish_per_turn": "0.1000"} for u in units],
            "mercenary_pool_to_groups_junctions": [
                {"key": str(i), "group": u + "_group", "initial_unit_count": "1",
                 "pool": source + "_pool", "faction_requirement": "",
                 "subculture_requirement": source + "_subculture",
                 "tech_requirement": ""} for i, u in enumerate(units, 1)],
        }
        entries = records["mercenary_pool_to_groups_junctions"]
        entries.append(dict(entries[0], key="101", pool=ror.HOST + "_pool",
                            subculture_requirement=""))
        entries[2].update(initial_unit_count="0", faction_requirement=source,
                          tech_requirement="native_technology")
        entries[5]["faction_requirement"] = "unrelated_faction"
        self.native = {name: Table(name, [], "0", rows)
                       for name, rows in records.items()}

    def test_adds_only_recruitable_rors_without_extra_native_stock(self):
        before = deepcopy(self.native)
        rows = list(ror.additions(self.native))
        actual = {row["group"]: row for row in rows}
        self.assertEqual(set(actual), {"new_group", "gated_group"})
        for row in actual.values():
            self.assertEqual(row["pool"], ror.HOST + "_pool")
            self.assertEqual(row["faction_requirement"], ror.HOST)
            self.assertEqual(row["subculture_requirement"], "")
        self.assertEqual(actual["gated_group"]["initial_unit_count"], "0")
        self.assertEqual(actual["gated_group"]["tech_requirement"],
                         "native_technology")
        self.assertEqual(self.native, before)

    def test_does_not_mistake_another_factions_stock_for_host_stock(self):
        entries = self.native["mercenary_pool_to_groups_junctions"].rows
        entries[-1]["faction_requirement"] = "unrelated_faction"
        actual = {row["group"] for row in ror.additions(self.native)}
        self.assertEqual(actual, {"native_group", "new_group", "gated_group"})

    def test_adds_the_sourguts_with_its_native_group_and_host_permission(self):
        faction = "wh3_dlc20_chs_vilitch"
        unit = "wh3_dlc24_tze_inf_pink_horrors_ror"
        self.native["main_units"].rows.append(
            {"unit": unit, "caste": "missile_infantry", "is_renown": "true"})
        self.native["mercenary_unit_groups"].rows.append(
            {"key": unit, "unit_record": unit, "max_count": "1"})
        source = {"key": "102", "group": unit, "initial_unit_count": "1",
                  "pool": faction + "_pool", "faction_requirement": faction,
                  "subculture_requirement": "", "tech_requirement": ""}
        self.native["mercenary_pool_to_groups_junctions"].rows.append(source)
        actual = list(ror.rows(self.native))
        pools = [row for row in ror.additions(self.native) if row["group"] == unit]
        self.assertEqual(len(pools), 1)
        self.assertEqual(pools[0]["pool"], ror.HOST + "_pool")
        self.assertEqual(pools[0]["faction_requirement"], ror.HOST)
        self.assertIn(("units_to_groupings_military_permissions",
                       {"unit": unit, "military_group": ror.HOST + "_group"}),
                      actual)
        self.assertEqual(source["faction_requirement"], faction)

    def test_runtime_registration_retains_native_source_stock_and_cooldown(self):
        actual = {row["unit"]: row for row in ror.script_data(self.native)}
        self.assertEqual(set(actual), {"new", "gated"})
        self.assertEqual(actual["gated"], {
            "unit": "gated", "group": "gated_group",
            "source": "native_renown_source", "count": 0, "chance": 100.0,
            "maximum": 1, "rate": 0.1, "partial": True,
            "faction": ror.HOST, "subculture": "",
            "technology": "native_technology",
        })
        self.assertEqual(actual["new"]["count"], 1)
        self.assertFalse(any(table == "mercenary_pool_to_groups_junctions"
                             for table, _ in ror.rows(self.native)))


if __name__ == "__main__":
    unittest.main()
