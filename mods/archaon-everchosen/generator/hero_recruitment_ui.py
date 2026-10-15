"""Name Archaon's shared hero-capacity groups without replacing recruitment."""
import json
import xml.etree.ElementTree as ET

from daemon_prince import callback
from host import HOST, CAMPAIGN

PREFIX = "everchosen_hero_group_"
TABLES = ("agent_culture_details",)
PANEL = "ui/campaign ui/character_panel.twui.xml"
SCOPE = (f'PlayersFaction.FactionRecordContext.Key == "{HOST}" && '
         f'CampaignKey == "{CAMPAIGN}" && IsMultiplayer == false')
AGENT_KEY = 'self.ParentContext.GetProperty("agent_type_key")'

# Native representative icons; these are display records, not new permissions.
ICON_SOURCES = {
    "champion": "494",
    "wizard": "533",
    "spy": "227243909",
    "dignitary": "130851887",
    "runesmith": "1746459626",
    "engineer": "1811693418",
}
ANCHORS = {
    "list": "3A620DFB-CB4E-4BC3-BF1B230582AA59C4",
    "label": "6664E522-0080-4756-BBDFE1C21F2C9297",
    "icon": "83BE0492-8E0D-4ED0-9B2CCDB88B331291",
    "button": "A9B843F1-669C-49F2-90D1B9248EE4ED62",
}


def by_agent(values, fallback, agent_key=AGENT_KEY):
    """Keep the native display for agent classes outside our named groups."""
    result = fallback
    for agent, value in reversed(sorted(values.items())):
        result = (f"GetIfElse({agent_key} == {json.dumps(agent)}, "
                  f"{value}, {result})")
    return f"GetIfElse({SCOPE}, {result}, {fallback})"


def adapt(tree, native_root, native):
    root = tree.getroot()
    parts = {}
    for name, guid in ANCHORS.items():
        matches = root.findall(f'components/*[@this="{guid}"]')
        if len(matches) != 1:
            raise ValueError(f"Hero recruitment UI anchor changed: {name}")
        parts[name] = matches[0]
    for name in ("label", "icon"):
        parent = parts[name].find(
            'userproperties/property[@name="dynamic_child_parent"]')
        if parent is None or parent.get("value") != "button_template_agent":
            raise ValueError(f"Hero recruitment tab child changed: {name}")

    icons = {}
    for agent, key in ICON_SOURCES.items():
        row = native["agent_culture_details"].one(key=key, agent=agent)
        if not row["small_icon"]:
            raise ValueError(f"Missing native hero icon: {agent}")
        icons[agent] = json.dumps(row["small_icon"])
    for name, kind, expression in (
            ("label", "ContextTextLabel",
             by_agent({agent: f'Loc("{PREFIX}{agent}")'
                       for agent in ICON_SOURCES}, "self.CurrentText")),
            ("button", "ContextTooltipSetter",
             by_agent({agent: f'Loc("{PREFIX}{agent}_tooltip")'
                       for agent in ICON_SOURCES}, "self.CurrentTooltip",
                      'self.GetProperty("agent_type_key")')),
            ("icon", "ContextImageSetter",
             by_agent(icons, "self.ImagePath(0)"))):
        callbacks = parts[name].find("callbackwithcontextlist")
        if callbacks is None:
            callbacks = parts[name].find("callbacks_with_context")
        if callbacks is None:
            callbacks = ET.SubElement(parts[name], "callbackwithcontextlist")
        callback(callbacks, kind, "CcoStaticObject", expression,
                 update_constant="")

    layout = parts["list"].find("LayoutEngine")
    if layout is None or layout.get("type") != "List":
        raise ValueError("Hero recruitment tab layout changed")
    original_columns = int(layout.attrib["itemsperrow"])
    columns = f"GetIfElse({SCOPE}, 3, {original_columns})"
    resize = (f"DoIf(self.ListLayoutContext.ItemsPerRow != {columns}, "
              f"self.ListLayoutContext.SetItemsPerRow({columns}))")
    callbacks = parts["list"].find("callbackwithcontextlist")
    callback(callbacks, "ContextCommandGiverOnVisibilityChanged",
             "CcoStaticObject", resize, on_hide_and_show="")
    callback(callbacks, "ContextCommandEvent", "CcoStaticObject", resize,
             event0="LayoutFinished_character_panel")


UI_ADAPTATIONS = {PANEL: adapt}
