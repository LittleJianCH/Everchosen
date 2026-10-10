"""RPFM TSV quotes are literal data, not CSV quoting syntax."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from db_tables import read_table, write_table


class RpfmTsvTests(unittest.TestCase):
    def test_quoted_dilemma_description_survives_read_and_write(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fragment = root / "input/dilemmas_tables/data__.tsv"
            fragment.parent.mkdir(parents=True)
            fragment.write_text(
                'key\tlocalised_description\n#dilemmas_tables;0;db/dilemmas_tables/data__\t\n'
                'first\t"An opening quote" followed by text\n'
                'second\tAnother "quoted" description\n', encoding="utf-8")
            original = read_table(root / "input", "dilemmas")
            self.assertEqual(2, len(original.rows))
            self.assertEqual('"An opening quote" followed by text',
                             original.rows[0]["localised_description"])
            write_table(root / "output", original, original.rows, "copy")
            copied = read_table(root / "output/db", "dilemmas")
            self.assertEqual(original.rows, copied.rows)


if __name__ == "__main__":
    unittest.main()
