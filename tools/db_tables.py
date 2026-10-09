"""Read and emit RPFM TSVs without assuming a table's primary key."""
import csv


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


def read_table(db, name, key_columns=()):
    folder = db / (name + "_tables")
    files = sorted(folder.glob("*"))
    if not files or any(not p.is_file() or p.suffix != ".tsv" for p in files):
        raise ValueError(f"{folder}: missing or undecoded native table")
    header, metadata, rows = None, None, []
    for path in files:
        with path.open(encoding="utf-8-sig", newline="") as stream:
            reader = csv.reader(stream, delimiter="\t")
            columns, schema = next(reader), next(reader)[0]
            if not schema.startswith(f"#{name}_tables;"):
                raise ValueError(f"{path}: invalid schema metadata")
            if header is not None and (columns != header or
                    schema.split(";")[:2] != metadata.split(";")[:2]):
                raise ValueError(f"{path}: inconsistent table schema")
            header, metadata = columns, schema
            for row in reader:
                if len(row) != len(header):
                    raise ValueError(f"{path}: unexpected column count")
                rows.append(dict(zip(header, row)))
    if key_columns:
        keys = [tuple(row[column] for column in key_columns) for row in rows]
        if len(keys) != len(set(keys)):
            raise ValueError(f"{folder}: overlapping native keys need explicit load-order resolution")
    return header, metadata, rows


def write_table(output, name, table, rows, fragment):
    header, metadata, _ = table
    path = output / "db" / (name + "_tables") / (fragment + ".tsv")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(header)
        writer.writerow([";".join(metadata.split(";")[:2])
                         + f";db/{name}_tables/{fragment}"]
                        + [""] * (len(header) - 1))
        for row in rows:
            if set(row) != set(header):
                raise ValueError(f"{name}: output fields do not match the schema")
            writer.writerow([row[column] for column in header])
