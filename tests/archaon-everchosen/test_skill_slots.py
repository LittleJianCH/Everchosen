"""A variant must not share neighbours of an adapted skill node."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "tools"),
               str(ROOT / "mods/archaon-everchosen/generator")]
from db_tables import Table
import skill_slots


class SkillTreeTests(unittest.TestCase):
    def setUp(self):
        # WH3 links use node keys, with no node-set discriminator.
        self.native = {"character_skill_node_links": Table(
            "character_skill_node_links", [], "3", [
                {"parent_key": "entry", "child_key": "adapted",
                 "link_type": "REQUIRED"},
                {"parent_key": "adapted", "child_key": "later",
                 "link_type": "SUBSET_REQUIRED"}]),
            "character_skill_node_set_items": Table(
                "character_skill_node_set_items", [], "0", [])}
        self.nodes = [{"key": key} for key in
                      ("entry", "adapted", "later", "unrelated")]

    def variant(self, mapping):
        return {
            "character_skill_nodes": [{"key": key} for key in mapping.values()],
            "character_skill_node_sets": [{"key": "variant"}],
            "character_skill_node_set_items": [
                {"set": "variant", "item": mapping.get(row["key"], row["key"]),
                 "mod_disabled": "false"} for row in self.nodes],
            "character_skill_node_links": [row for _, row in
                                           skill_slots.links(self.native, mapping)]}

    def test_isolates_whole_path_without_copying_unrelated_nodes(self):
        mapping = skill_slots.linked_nodes(
            self.native, self.nodes, {"adapted"}, "private_")
        variant = self.variant(mapping)
        skill_slots.validate_trees(self.native, variant)
        self.assertEqual({"entry", "adapted", "later"}, set(mapping))
        inverse = {new: old for old, new in mapping.items()}
        restored = [dict(row, parent_key=inverse[row["parent_key"]],
                         child_key=inverse[row["child_key"]])
                    for row in variant["character_skill_node_links"]]
        self.assertEqual(self.native["character_skill_node_links"].rows, restored)
        self.assertIn({"set": "variant", "item": "unrelated",
                       "mod_disabled": "false"},
                      variant["character_skill_node_set_items"])

    def test_rejects_partial_copy_even_when_all_db_references_exist(self):
        mapping = {"adapted": "private_adapted"}
        variant = self.variant(mapping)
        variant["character_skill_node_links"] = [
            dict(row, parent_key=mapping.get(row["parent_key"], row["parent_key"]),
                 child_key=mapping.get(row["child_key"], row["child_key"]))
            for row in self.native["character_skill_node_links"].rows]
        with self.assertRaisesRegex(ValueError, "prerequisite outside variant"):
            skill_slots.validate_trees(self.native, variant)

    def test_checks_paths_added_to_an_existing_tree(self):
        mapping = skill_slots.linked_nodes(
            self.native, self.nodes, {"adapted"}, "private_")
        variant = self.variant(mapping)
        variant["character_skill_node_sets"] = []
        self.native["character_skill_node_set_items"].rows = [
            {"set": "variant", "item": row["key"], "mod_disabled": "false"}
            for row in self.nodes]
        skill_slots.validate_trees(self.native, variant)
        variant["character_skill_node_set_items"] = [
            r for r in variant["character_skill_node_set_items"]
            if r["item"] != "private_entry"]
        with self.assertRaisesRegex(ValueError, "prerequisite outside variant"):
            skill_slots.validate_trees(self.native, variant)


if __name__ == "__main__":
    unittest.main()
