"""Campaign roster additions must not grant characters or special variants."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"),
               str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import Table
import roster_permissions as roster


class RosterPermissionsTests(unittest.TestCase):
    def setUp(self):
        factions = ["host", *roster.SOURCE_FACTIONS]
        units = ("ordinary", "ror", "already_owned", "banned", "hunt_reward",
                 "hero", "lord", "battle_only", "source_banned")
        source = roster.SOURCE_FACTIONS[0]
        rows = {
            "factions": [{"key": f, "military_group": f + "_group"}
                         for f in factions],
            "groupings_military": [{"military_group": f + "_group"}
                                   for f in factions],
            "main_units": [{"unit": u, "caste": u if u in ("hero", "lord")
                            else "monster"} for u in units],
            "units_custom_battle_permissions": [
                {"unit": u, "faction": source,
                 "campaign_exclusive": "true" if u == "hunt_reward"
                 else "false", "general_unit": "false",
                 "set_piece_character": ""} for u in units],
            "units_to_groupings_military_permissions": [
                {"unit": u, "military_group": source + "_group"}
                for u in units if u not in ("ror", "battle_only")],
            # Older native Beastmen RoRs use only faction exceptions, while
            # current ordinary units use military groups. Keep both sources.
            "units_to_exclusive_faction_permissions": [
                {"key": "ror", "faction": source, "allowed": "true"},
                {"key": "already_owned", "faction": "host",
                 "allowed": "true"},
                {"key": "banned", "faction": "host", "allowed": "false"},
                {"key": "source_banned", "faction": source,
                 "allowed": "false"}],
        }
        self.native = {name: Table(name, [], "0", records)
                       for name, records in rows.items()}

    def test_adds_regular_roster_without_overriding_restrictions(self):
        actual = list(roster.permissions(self.native, "host"))
        self.assertEqual(actual, [
            ("units_to_groupings_military_permissions",
             {"unit": "ordinary", "military_group": "host_group"}),
            ("units_to_groupings_military_permissions",
             {"unit": "ror", "military_group": "host_group"}),
        ])

    def test_rejects_a_group_shared_with_other_factions(self):
        self.native["factions"].rows.append(
            {"key": "unrelated", "military_group": "host_group"})
        with self.assertRaisesRegex(ValueError, "not faction-specific"):
            list(roster.permissions(self.native, "host"))


if __name__ == "__main__":
    unittest.main()
