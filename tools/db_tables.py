"""Read, check, and emit RPFM TSVs for the per-product asset generators."""
import csv
import zlib
from dataclasses import dataclass


def lua_literal(value):
    """Serialize strings, booleans, lists, and string-keyed dicts as Lua."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        escaped = (value.replace("\\", "\\\\").replace('"', '\\"')
                   .replace("\n", "\\n"))
        return f'"{escaped}"'
    if isinstance(value, dict):
        return "{" + ",".join(f"[{lua_literal(key)}]={lua_literal(item)}"
                              for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    raise TypeError(f"No Lua literal for {type(value).__name__}")


@dataclass
class Table:
    """Rows of one DB table as dicts, with the layout RPFM exported them in."""
    name: str
    header: list
    version: str
    rows: list

    def where(self, **match):
        return [row for row in self.rows
                if all(row[column] == value for column, value in match.items())]

    def one(self, **match):
        """A copy of the only row matching MATCH; anything else is an error."""
        found = self.where(**match)
        if len(found) != 1:
            raise ValueError(f"Expected one {self.name} row for {match}, "
                             f"got {len(found)}")
        return found[0].copy()

    def column(self, column):
        return {row[column] for row in self.rows}


def run_generator(generate, native_inputs):
    """Shared command-line contract used by build.sh and package.ps1."""
    import argparse
    import json
    from pathlib import Path

    parser = argparse.ArgumentParser()
    parser.add_argument("--print-inputs", action="store_true",
                        help="Print native pack paths for the packaging script")
    parser.add_argument("--vanilla", type=Path,
                        help="Root of the RPFM native extraction")
    parser.add_argument("--output", type=Path,
                        help="Generated pack staging directory")
    args = parser.parse_args()
    if args.print_inputs:
        print(json.dumps(native_inputs))
    else:
        if args.vanilla is None or args.output is None:
            parser.error("--vanilla and --output are required for generation")
        generate(args.vanilla, args.output)


def _read_fragment(path, name):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        # RPFM exports literal quotes, including text beginning with a quote.
        reader = csv.reader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)
        header, metadata = next(reader), next(reader)[0].split(";")
        if metadata[0] != f"#{name}_tables" or len(metadata) < 2:
            raise ValueError(f"{path}: invalid schema metadata")
        rows = []
        for row in reader:
            if len(row) != len(header):
                raise ValueError(f"{path}: unexpected column count")
            rows.append(dict(zip(header, row)))
    return Table(name, header, metadata[1], rows)


def _fragments(db, name):
    folder = db / (name + "_tables")
    files = sorted(folder.glob("*")) if folder.is_dir() else []
    if any(not p.is_file() or p.suffix != ".tsv" for p in files):
        raise ValueError(f"{folder}: undecoded table fragment")
    return folder, files


def read_table(db, name, key_columns=()):
    """Merge every fragment of a native table extracted under DB."""
    folder, files = _fragments(db, name)
    if not files:
        raise ValueError(f"{folder}: missing native table")
    table = None
    for path in files:
        fragment = _read_fragment(path, name)
        if table is None:
            table = fragment
        elif (fragment.header, fragment.version) != (table.header, table.version):
            raise ValueError(f"{path}: inconsistent table schema")
        else:
            table.rows.extend(fragment.rows)
    if key_columns:
        keys = [tuple(row[column] for column in key_columns) for row in table.rows]
        if len(keys) != len(set(keys)):
            raise ValueError(f"{folder}: overlapping native keys need explicit load-order resolution")
    return table


def read_authored(db, native):
    """Rows of a product's hand-written fragments, by table name.

    NATIVE maps table names to their native Table. An authored fragment pins
    its column layout and table version, so a game update that changes either
    must fail here instead of producing a pack the game misreads.
    """
    authored = {}
    for name, table in native.items():
        _, files = _fragments(db, name)
        for path in files:
            fragment = _read_fragment(path, name)
            if (fragment.header, fragment.version) != (table.header, table.version):
                raise ValueError(
                    f"{path}: authored layout {fragment.header} v{fragment.version} "
                    f"differs from native {table.header} v{table.version}")
            authored.setdefault(name, []).extend(fragment.rows)
    return authored


def write_table(output, table, rows, fragment):
    """Write ROWS as a new fragment of TABLE in the staging directory."""
    path = output / "db" / (table.name + "_tables") / (fragment + ".tsv")
    if path.exists():
        raise ValueError(f"{path}: generated fragment would replace an asset")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n",
                            quoting=csv.QUOTE_NONE, quotechar=None)
        writer.writerow(table.header)
        writer.writerow([f"#{table.name}_tables;{table.version};"
                         f"db/{table.name}_tables/{fragment}"]
                        + [""] * (len(table.header) - 1))
        for row in rows:
            if set(row) != set(table.header):
                raise ValueError(f"{table.name}: output fields do not match the schema")
            writer.writerow([row[column] for column in table.header])


def stable_id(label, used):
    """A positive signed 32-bit ID derived from LABEL and recorded in USED."""
    value = str(zlib.crc32(label.encode("utf-8")) & 0x7fffffff)
    if value in used:
        raise ValueError(f"Generated ID collides with an existing row: {label}")
    used.add(value)
    return value


def write_localisation(output, rows, fragment):
    """Write native-derived translations separately from authored Loc assets."""
    path = output / "text" / (fragment + ".loc.tsv")
    if path.exists():
        raise ValueError(f"{path}: generated localisation would replace an asset")
    path.parent.mkdir(parents=True, exist_ok=True)
    keys = set()
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n",
                            quoting=csv.QUOTE_NONE, quotechar=None)
        writer.writerow(["key", "text", "tooltip"])
        writer.writerow([f"#Loc;1;text/{fragment}.loc", "", ""])
        for row in rows:
            if set(row) != {"key", "text", "tooltip"} or row["key"] in keys:
                raise ValueError(f"Invalid or duplicate localisation: {row}")
            keys.add(row["key"])
            writer.writerow([row["key"], row["text"], row["tooltip"]])
