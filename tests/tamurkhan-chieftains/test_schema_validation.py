"""The validation-only generator rejects schema drift and leaves staging intact."""
import contextlib
import importlib.util
import io
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "mods/tamurkhan-chieftains"
SPEC = importlib.util.spec_from_file_location(
    "chieftains_generator", MOD / "generator/generate.py")
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class SchemaValidationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.native = self.root / "vanilla"
        self.output = self.root / "stage"
        # The product's small authored tables supply the known schema fixture.
        shutil.copytree(MOD / "assets/db", self.native / "db")
        shutil.copytree(MOD / "assets", self.output)

    def validate(self):
        with contextlib.redirect_stdout(io.StringIO()):
            generator.generate(self.native, self.output)

    def test_matching_schema_leaves_staged_assets_unchanged(self):
        before = {path.relative_to(self.output): path.read_bytes()
                  for path in self.output.rglob("*") if path.is_file()}
        self.validate()
        after = {path.relative_to(self.output): path.read_bytes()
                 for path in self.output.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_rejects_native_column_order_or_version_change(self):
        fragment = (self.native / "db/campaign_group_members_tables/"
                    "everchosen_chieftains.tsv")
        original = fragment.read_text(encoding="utf-8").splitlines()
        changed_header = original.copy()
        changed_header[0] = "\t".join(reversed(original[0].split("\t")))
        changed_version = original.copy()
        metadata = changed_version[1].split(";")
        metadata[1] = str(int(metadata[1]) + 1)
        changed_version[1] = ";".join(metadata)
        for change, lines in (("column order", changed_header),
                              ("version", changed_version)):
            with self.subTest(change=change):
                fragment.write_text("\n".join(lines) + "\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "differs from native"):
                    self.validate()


if __name__ == "__main__":
    unittest.main()
