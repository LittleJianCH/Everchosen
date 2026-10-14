"""Keep default recruitment available only for Archaon's WoC faction."""
from db_tables import write_table
from host import HOST

TABLES = ("factions", "ui_features_to_cultures", "ui_features_to_factions")
CULTURE = "wh_main_chs_chaos"
SUBCULTURE = "wh_main_sc_chs_chaos"
DISABLE = "DISABLE_DEFAULT_RECRUITMENT"


def rows(native):
    """Restore the native recruitment restriction for every other WoC faction."""
    factions = {row["key"] for row in native["factions"].rows
                if row["subculture"] == SUBCULTURE}
    if HOST not in factions:
        raise ValueError("Archaon is missing from the native WoC subculture")
    existing = {(row["faction"], row["ui_feature"])
                for row in native["ui_features_to_factions"].rows}
    if (HOST, DISABLE) in existing:
        raise ValueError("Native Archaon faction separately disables recruitment")
    for faction in sorted(factions - {HOST}):
        if (faction, DISABLE) not in existing:
            yield "ui_features_to_factions", {
                "faction": faction, "ui_feature": DISABLE}


def write_culture_override(native_root, output, native):
    """Replace only the native fragment containing WoC's culture-wide ban."""
    folder = native_root / "db/ui_features_to_cultures_tables"
    if [path.name for path in folder.iterdir()] != ["data__.tsv"]:
        raise ValueError("Native recruitment UI feature fragments changed")
    table = native["ui_features_to_cultures"]
    blocked = {"culture": CULTURE, "ui_feature": DISABLE}
    if table.rows.count(blocked) != 1:
        raise ValueError("Expected one native WoC default-recruitment ban")
    if len(table.where(culture=CULTURE, ui_feature="WARBANDS")) != 1:
        raise ValueError("Native WoC warbands feature changed")
    write_table(output, table, [row for row in table.rows if row != blocked],
                "data__")
