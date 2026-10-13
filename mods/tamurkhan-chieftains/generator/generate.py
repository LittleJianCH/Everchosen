"""Validate authored DB layouts without producing or changing pack assets."""
import sys
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MOD.parents[1] / "tools"))
from db_tables import read_authored, read_table, run_generator

AUTHORED_DB = MOD / "assets/db"
TABLES = [folder.name.removesuffix("_tables")
          for folder in sorted(AUTHORED_DB.glob("*_tables")) if folder.is_dir()]
NATIVE_INPUTS = {"db.pack": [f"db/{name}_tables" for name in TABLES]}


def generate(vanilla, output):
    """Keep OUTPUT untouched; it is part of the shared generator CLI contract."""
    native = {name: read_table(vanilla / "db", name) for name in TABLES}
    authored = read_authored(AUTHORED_DB, native)
    print(f"Chieftains: {sum(map(len, authored.values()))} authored rows "
          f"across {len(authored)} tables validated; no generated assets")


if __name__ == "__main__":
    run_generator(generate, NATIVE_INPUTS)
