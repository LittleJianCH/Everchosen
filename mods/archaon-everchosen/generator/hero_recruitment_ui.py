"""Native representative icons for Archaon's shared hero-capacity groups."""
TABLES = ("agent_culture_details",)

# Native representative icons; these are display records, not new permissions.
ICON_SOURCES = {
    "champion": "494",
    "wizard": "533",
    "spy": "227243909",
    "dignitary": "130851887",
    "runesmith": "1746459626",
    "engineer": "1811693418",
}


def script_data(native):
    icons = {}
    for agent, key in ICON_SOURCES.items():
        row = native["agent_culture_details"].one(key=key, agent=agent)
        if not row["small_icon"]:
            raise ValueError(f"Missing native hero icon: {agent}")
        icons[agent] = row["small_icon"]
    return icons
