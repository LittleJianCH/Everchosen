"""A private, paginated hero-family selector using native recruitment tabs."""
import xml.etree.ElementTree as ET
from copy import deepcopy
from uuid import NAMESPACE_URL, uuid5

TABLES = ("agent_culture_details",)
PANEL = "ui/campaign ui/character_panel.twui.xml"
UI_PATH = "ui/everchosen/hero_families.twui.xml"
ROOT = "everchosen_hero_families"
PAGE_SIZE = 8
NATIVE_INPUTS = (
    PANEL,
    "ui/templates/square_medium_text_tab_toggle.twui.xml",
    "ui/templates/cycle_button_arrow_previous.twui.xml",
    "ui/templates/cycle_button_arrow_next.twui.xml",
)
ANCHORS = {
    "container": "3A620DFB-CB4E-4BC3-BF1B230582AA59C4",
    "label": "6664E522-0080-4756-BBDFE1C21F2C9297",
    "icon": "83BE0492-8E0D-4ED0-9B2CCDB88B331291",
    "previous": "7A17A59C-96C3-4E6A-A1B07F368A212C21",
    "next": "747CF023-894B-473A-83D74BED7C6C91BF",
}

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


def clone(source, name):
    """Remap instance GUIDs, retaining references into native UI templates."""
    part = deepcopy(source)
    remap = {value: str(uuid5(NAMESPACE_URL, f"{ROOT}/{name}/{value}"))
             .upper() for element in part.iter()
             for attr, value in element.attrib.items()
             if attr in {"this", "uniqueguid"}}
    for element in part.iter():
        for attr, value in list(element.attrib.items()):
            if attr != "uniqueguid_in_template" and value in remap:
                element.set(attr, remap[value])
    part.tag = name
    part.set("id", name)
    # The selector is filled by campaign code, not the recruitment callback.
    for tag in ("userproperties", "user_properties", "callbackwithcontextlist",
                "callbacks_with_context", "localised_texts"):
        for child in part.findall(tag):
            part.remove(child)
    for text in part.findall("states/*/component_text"):
        text.attrib.pop("textlabel", None)
        text.set("text", "")
    return part


def validate_ui(tree, native_root):
    """Check local component/state/image references and native template links."""
    root = tree.getroot()
    components = root.find("components")
    parts = {part.get("this"): part for part in components}
    hierarchy = list(root.find("hierarchy").iter())[1:]
    if (len(parts) != len(components) or len(hierarchy) != len(parts)
            or {node.get("this") for node in hierarchy} != set(parts)):
        raise ValueError("Private hero selector component hierarchy is invalid")
    for node in hierarchy:
        if parts[node.get("this")].tag != node.tag:
            raise ValueError("Private hero selector hierarchy tag mismatch")
    panel = root.find(f"hierarchy/root/{ROOT}")
    for index in range(1, PAGE_SIZE + 1):
        entry = panel.find(f"everchosen_hero_slot_{index}")
        button = parts[entry.get("this")]
        if (button.get("template_id") or button.get("part_of_template")
                or button.find("states") is None
                or button.find("componentimages") is None):
            raise ValueError("Hero family slot must own its states and children")
        for name in ("label", "icon"):
            child = entry.find(name)
            if child is None or parts[child.get("this")].get("id") != name:
                raise ValueError(f"Hero family slot is missing its {name}")
    definitions = [element.get("this") for element in components.iter()
                   if element.get("this")]
    if len(definitions) != len(set(definitions)):
        raise ValueError("Private hero selector has duplicate instance GUIDs")
    known = set(definitions)
    known.update(element.get("uniqueguid") for element in components.iter()
                 if element.tag in {"state_uniqueguid",
                                    "component_image_uniqueguid"})
    template_guids = set()
    for relative in NATIVE_INPUTS[1:]:
        template = ET.parse(native_root / relative)
        template_guids.update(element.get("this") for element in template.iter()
                              if element.get("this"))
    for element in components.iter():
        for attr in ("currentstate", "defaultstate", "componentimage",
                     "transition_m_target_state"):
            if attr in element.attrib and element.get(attr) not in known:
                raise ValueError(f"Unresolved hero selector {attr} reference")
        source = element.get("uniqueguid_in_template")
        if source and source not in template_guids:
            raise ValueError("Unresolved hero selector native template reference")


def write_ui(native_root, output):
    """Write the standalone selector; campaign code supplies labels and clicks."""
    native = ET.parse(native_root / PANEL).getroot()
    sources = {}
    for name, guid in ANCHORS.items():
        matches = native.findall(f'components/*[@this="{guid}"]')
        if len(matches) != 1:
            raise ValueError(f"Hero recruitment UI anchor changed: {name}")
        sources[name] = matches[0]
    template = ET.parse(native_root / NATIVE_INPUTS[1]).getroot()
    source_button = template.find("components/square_medium_text_tab_toggle")
    if source_button is None:
        raise ValueError("Native hero tab button template changed")
    root = ET.Element("layout", native.attrib)
    hierarchy = ET.SubElement(root, "hierarchy")
    components = ET.SubElement(root, "components")

    for name, parent in (("root", hierarchy), (ROOT, None)):
        part = clone(sources["container"], name)
        part.attrib.pop("component_anchor_point", None)
        part.set("docking", "Top Left")
        part.set("offset", "0.00,0.00")
        part.set("dock_offset", "0.00,0.00")
        part.set("allowhorizontalresize", "false")
        part.set("allowverticalresize", "false")
        part.remove(part.find("LayoutEngine"))
        for state in part.find("states"):
            state.set("width", "810")
            state.set("height", "122")
        if parent is None:
            parent = hierarchy.find("root")
        node = ET.SubElement(parent, name, this=part.get("this"))
        components.append(part)
    panel = node

    for index in range(1, PAGE_SIZE + 1):
        name = f"everchosen_hero_slot_{index}"
        # Native recruitment marks its extra label/icon as dynamic children.
        # This private selector has authored children: materialize the complete
        # button instead of retaining an external template instance.
        button = clone(source_button, name)
        button.attrib.pop("uniqueguid_in_template", None)
        button.attrib.pop("component_anchor_point", None)
        button.set("docking", "Top Left")
        position = (f"{5 + (index - 1) % 4 * 200}.00,"
                    f"{(index - 1) // 4 * 42}.00")
        button.set("offset", position)
        button.set("dock_offset", position)
        button.set("visible", "false")
        button.set("allowhorizontalresize", "false")
        button.set("allowverticalresize", "false")
        for state in button.find("states"):
            width, height = int(state.get("width")), int(state.get("height"))
            state.set("width", "200")
            state.set("height", "42")
            for image in state.findall("imagemetrics/image"):
                image.set("width", str(round(int(image.get("width"))
                                             * 200 / width)))
                image.set("height", str(round(int(image.get("height"))
                                              * 42 / height)))
        callbacks = ET.SubElement(button, "callbackwithcontextlist")
        ET.SubElement(callbacks, "callback_with_context", callback_id="Button")
        propagate = ET.SubElement(callbacks, "callback_with_context",
                                  callback_id="StatePropagatorCallback")
        props = ET.SubElement(propagate, "child_m_user_properties")
        ET.SubElement(props, "property", name="target_id", value="label")
        entry = ET.SubElement(panel, name, this=button.get("this"))
        components.append(button)
        for child in ("label", "icon"):
            part = clone(sources[child], f"{name}_{child}")
            part.tag = child
            part.set("id", child)
            ET.SubElement(entry, child, this=part.get("this"))
            components.append(part)

    for direction, x in (("previous", 270), ("next", 504)):
        name = "everchosen_hero_" + ("prev" if direction == "previous"
                                     else "next")
        part = clone(sources[direction], name)
        part.set("dimensions", "36.00,32.00")
        part.set("dock_point", "Top Left")
        part.set("offset", f"{x}.00,86.00")
        callbacks = ET.SubElement(part, "callbacks_with_context")
        ET.SubElement(callbacks, "callback_with_context", callback_id="Button")
        ET.SubElement(panel, name, this=part.get("this"))
        components.append(part)
    page = clone(sources["label"], "everchosen_hero_page")
    page.set("offset", "315.00,87.00")
    page.set("dock_offset", "315.00,87.00")
    for state in page.find("states"):
        state.set("width", "180")
        state.set("height", "30")
    ET.SubElement(panel, page.tag, this=page.get("this"))
    components.append(page)

    tree = ET.ElementTree(root)
    validate_ui(tree, native_root)
    destination = output / UI_PATH
    destination.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="\t")
    tree.write(destination, encoding="utf-8", xml_declaration=True)
    return 1
