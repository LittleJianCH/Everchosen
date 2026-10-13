"""Adapt native building displays for Archaon's four private Beastmen camps.

The native panels still own construction, recruitment, and affordability rules.
Only cost presentation, the growth panel position, and private stock lists change.
"""
import json
import xml.etree.ElementTree as ET
from copy import deepcopy
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from host import HOST
import beastmen_hordes

TABLES = beastmen_hordes.TABLES
PREFIX = "everchosen_horde_"
UNIT_SET = PREFIX + "warband_units"
CCO_NAME = "EverchosenHordeUI"
UI_FOLDER = Path("ui/campaign ui")
UI_NAMES = ("building_construction_popup", "building_information",
            "building_browser", "building_info_recruitment_effects")
NATIVE_INPUTS = [str(UI_FOLDER / (name + ".twui.xml")).replace("\\", "/")
                 for name in UI_NAMES]
GROWTH_BACKGROUND = "27403072-B6AB-43B7-B2C76AF116EBD3FF"
INFO_HOLDER = ("hierarchy/root/building_information/building_info_holder/"
               "building_information_holder")
EXPRESSION = "context_function_id"


def one(elements, description):
    if len(elements) != 1:
        raise ValueError(f"Horde UI anchor changed: {description}")
    return elements[0]


def callback(parent, kind, expression, context=None, **properties):
    callbacks = parent.find("callbackwithcontextlist")
    if callbacks is None:
        callbacks = ET.Element("callbackwithcontextlist")
        parent.insert(0, callbacks)
    attrs = {"callback_id": kind, EXPRESSION: expression}
    if context:
        attrs["context_object_id"] = context
    result = ET.SubElement(callbacks, "callback_with_context", **attrs)
    if properties:
        items = ET.SubElement(result, "child_m_user_properties")
        for name, value in properties.items():
            ET.SubElement(items, "property", name=name, value=value)
    return result


def character_scope(actor, subtypes):
    """A selected or slot-bound character must own its matching native horde."""
    pairs = " || ".join(
        f'({actor}.AgentSubtypeRecordContext.Key == {json.dumps(subtype)} && '
        f'{actor}.MilitaryForceContext.ForceType == {json.dumps(kind)})'
        for subtype, kind in sorted(subtypes.items()))
    if not pairs:
        raise ValueError("Horde UI needs subtype/force pairs")
    return (f'PlayersFaction.FactionRecordContext.Key == "{HOST}" && '
            f'IsContextValid({actor}) && '
            f'{actor}.FactionContext.FactionRecordContext.Key == "{HOST}" && '
            f'IsContextValid({actor}.MilitaryForceContext) && ({pairs})')


def adapt_character_information(root, horde_data):
    """Mutate only the growth background; compose after the Seafang adapter."""
    reference = one(root.findall(
        "hierarchy/root/character_information/horde_growth/background"),
        "horde growth hierarchy")
    background = one(root.findall(
        f'components/*[@this="{reference.get("this")}"]'),
        "horde growth background")
    if (background.get("this") != GROWTH_BACKGROUND
            or background.get("docking") != "Top Left"
            or background.get("dock_offset") is not None
            or background.find("callbackwithcontextlist") is not None):
        raise ValueError("Horde growth native anchor changed")
    scope = character_scope("SelectedCharacter", horde_data["subtypes"])
    # Keep the native authority dial in place. Absolute offsets avoid drift
    # when the same lord is selected repeatedly or the panel is reopened.
    expression = f"self.SetDockOffset(0, GetIfElse({scope}, -185, 0))"
    callback(background, "ContextCommandGiverOnVisibilityChanged", expression,
             on_hide_and_show="")
    callback(background, "ContextCommandEvent", expression,
             event0="CampaignSelectionChanged")


def adapt_costs(root, subtypes):
    costs = root.findall('components/*[@id="building_cost"]')
    if len(costs) != 2:
        raise ValueError("Horde construction cost anchors changed")
    slot = 'StoredContextFromParent("CcoCampaignBuildingSlot")'
    actor = slot + ".CharacterContext"
    scope = (f"IsContextValid({slot}) && {slot}.IsPlayerFaction && "
             f"{slot}.IsHordeSlot && ({character_scope(actor, subtypes)})")
    price = f"CreateCost({actor}, PlayersFaction)"
    for cost in costs:
        callbacks = cost.find("callbacks_with_context")
        if callbacks is None:
            raise ValueError("Horde construction cost callbacks changed")
        for kind, private in (("ContextTextLabel", price),
                              ("ContextVisibilitySetter", price + " != 0")):
            target = one(callbacks.findall(
                f'callback_with_context[@callback_id="{kind}"]'), kind)
            original = target.get(EXPRESSION, "")
            if (target.get("context_object_id") != "CcoBuildingLevelRecord"
                    or "CreateCost(Buildings.StoredSettlementOrCharacter"
                    not in original):
                raise ValueError("Horde cost context changed")
            target.set(EXPRESSION,
                       f"GetIfElse({scope}, {private}, {original})")
        state = one(callbacks.findall(
            'callback_with_context[@callback_id="ContextStateSetterConditional"]'),
            "cost colour callback")
        properties = state.find("child_m_user_properties")
        red = one(properties.findall('property[@name="red"]'), "cost red state")
        original = red.get("value", "")
        if "CanAfford(Buildings.StoredSettlementOrCharacter" not in original:
            raise ValueError("Horde cost affordability context changed")
        red.set("value", f"GetIfElse({scope}, PlayersFaction.TreasuryAmount < "
                f"{price}, {original})")
        events = properties.findall('property')
        event_keys = [e.get("name") for e in events
                      if e.get("name", "").startswith("event")]
        if "CampaignSelectionChanged" not in [e.get("value") for e in events]:
            ET.SubElement(properties, "property", name=f"event{len(event_keys)}",
                          value="CampaignSelectionChanged")


def adapt_cards(root, expected):
    targets = root.findall(
        './/callback_with_context[@callback_id="ContextList"]'
        '[@context_function_id="MercenaryUnitAndAmountPairList"]')
    if len(targets) != expected:
        raise ValueError("Native building unit-card lists changed")
    for target in targets:
        if target.get("context_object_id") != "CcoBuildingLevelRecord":
            raise ValueError("Native building unit-card context changed")
        target.set(EXPRESSION, f"GetIfElse({CCO_NAME}.IsPrivate(this), "
                   f"{CCO_NAME}.Pairs(this), MercenaryUnitAndAmountPairList)")


def use_state(component, state_name):
    state = one(component.findall(f'states/*[@name="{state_name}"]'),
                f"{component.get('id')}/{state_name}")
    component.set("currentstate", state.get("this"))
    component.set("defaultstate", state.get("this"))


def capacity_key(building):
    return PREFIX + "capacity_" + building.removeprefix(PREFIX)


def capacity_localisation(native):
    """Describe the same per-unit capacity limits the campaign script uses."""
    data = beastmen_hordes.script_data(native)
    for building, members in sorted(data["buildings"].items()):
        lines = []
        for unit in sorted(members):
            land_unit = native["main_units"].one(unit=unit)["land_unit"]
            lines.append("{{tr:land_units_onscreen_name_" + land_unit + "}}："
                         + str(data["units"][unit]["cap"]))
        yield {"key": capacity_key(building), "text": "\\n".join(lines),
               "tooltip": "false"}


def adapt_tooltip(root, template):
    """Insert a private native recruitment widget, leaving all originals intact."""
    before = ET.tostring(root)
    native_hierarchy = one(template.findall(
        "hierarchy/root/building_info_recruitment_effects"),
        "native recruitment hierarchy")
    remap = {e.get("this"): str(uuid5(NAMESPACE_URL, PREFIX + e.get("this")))
             .upper() for e in template.iter() if e.get("this")}

    def clone(source):
        item = deepcopy(source)
        for element in item.iter():
            for attr, value in list(element.attrib.items()):
                if value in remap:
                    element.set(attr, remap[value])
        return item

    hierarchy = clone(native_hierarchy)
    hierarchy.tag = PREFIX + "unit_capacity"
    holder = one(root.findall(INFO_HOLDER),
        "building information hierarchy")
    effects = one(holder.findall("effects_list"), "building effects hierarchy")
    holder.insert(list(holder).index(effects) + 1, hierarchy)
    guids = {e.get("this") for e in native_hierarchy.iter()}
    parts = {e.get("id"): clone(e) for e in template.find("components")
             if e.get("this") in guids}
    if len(parts) != len(guids):
        raise ValueError("Native recruitment component hierarchy changed")
    panel = parts["building_info_recruitment_effects"]
    panel.tag = hierarchy.tag
    panel.set("id", hierarchy.tag)
    for attr in ("offset", "dock_offset"):
        panel.attrib.pop(attr, None)
    panel.set("visible", "false")
    for native_callbacks in panel.findall("callbackwithcontextlist"):
        panel.remove(native_callbacks)
    callback(panel, "ContextVisibilitySetter", f"{CCO_NAME}.IsPrivate(this)",
             "CcoBuildingLevelRecord", update_constant="")
    # Keep the summary on its building context instead of dispatching custom
    # pairs as native recruitment entries.
    entry = hierarchy.find("entry_parent/unit_entry")
    for child in list(entry):
        if child.tag != "unit_name":
            entry.remove(child)
    for name in ("unit_cat_frame", "unit_category_icon", "experience",
                 "garrison_size"):
        del parts[name]
    for name in ("entry_parent", "unit_entry", "unit_name"):
        for callbacks in parts[name].findall("callbackwithcontextlist"):
            parts[name].remove(callbacks)
    use_state(parts["tx_enables"], "capacity_positive_light")
    use_state(parts["unit_name"], "light")
    for text in parts["unit_name"].findall("states/*/component_text"):
        text.attrib.pop("textlabel", None)
        text.attrib.pop("text", None)
    callback(parts["unit_name"], "ContextTextLabel",
             f"{CCO_NAME}.CapacityText(this)", "CcoBuildingLevelRecord")
    for name, width in (("unit_entry", 390), ("unit_name", 338)):
        height = f"{CCO_NAME}.CapacityHeight(this)"
        resize = (f"DoIf(self.Dimensions.y != {height}, "
                  f"self.Resize({width}, {height}, false))")
        callback(parts[name], "ContextCommandGiverOnVisibilityChanged",
                 resize,
                 "CcoBuildingLevelRecord", on_hide_and_show="")
        callback(parts[name], "ContextCommandEvent", resize,
                 "CcoBuildingLevelRecord",
                 event0="LayoutFinished_building_information")
    for name, x in (("tx_enables", 38), ("unit_name", 52)):
        parts[name].set("docking", "Top Left")
        parts[name].set("component_anchor_point", "0.00,0.00")
        parts[name].set("dock_offset", f"{x}.00,0.00")
    for state in parts["unit_entry"].find("states"):
        state.set("height", "32")
    # The native 210px widget is too narrow for the campaign's Chinese names.
    for name in ("building_info_recruitment_effects", "entry_parent", "unit_entry"):
        for state in parts[name].find("states"):
            state.set("width", "390")
        for column in parts[name].findall("LayoutEngine/columnwidths/column"):
            column.set("width", "390")
    components = root.find("components")
    for part in parts.values():
        components.append(part)
    # This shared tooltip is used by every faction. Removing our private nodes
    # must restore the entire native document, including callbacks and states.
    check = deepcopy(root)
    check_holder = one(check.findall(INFO_HOLDER),
        "private building information hierarchy")
    check_holder.remove(check_holder.find(hierarchy.tag))
    private_ids = {part.get("this") for part in parts.values()}
    check_components = check.find("components")
    for part in list(check_components):
        if part.get("this") in private_ids:
            check_components.remove(part)
    if ET.tostring(check) != before:
        raise ValueError("Private horde tooltip changed shared native content")


def cco_source(data):
    buildings, units = data["buildings"], data["units"]
    if not buildings or not units:
        raise ValueError("Horde UI needs building supply data")
    if any(not key.startswith(PREFIX) for key in buildings):
        raise ValueError("Horde UI building is outside the private namespace")
    for building, members in buildings.items():
        if not members or set(members) - units.keys():
            raise ValueError(f"Horde UI has invalid supply units: {building}")
    if any(not isinstance(rule["cap"], int) or rule["cap"] <= 0
           for rule in units.values()):
        raise ValueError("Horde UI stock capacity must be a positive integer")
    keys = " || ".join(f"building.Key == {json.dumps(key)}"
                       for key in sorted(buildings))
    conditions = " || ".join(
        f"(building.Key == {json.dumps(key)} && (" + " || ".join(
            f"unit.Key == {json.dumps(unit)}" for unit in sorted(members)) + "))"
        for key, members in sorted(buildings.items()))
    capacity = "0"
    for key, rule in reversed(sorted(units.items())):
        capacity = (f"GetIfElse(unit.Key == {json.dumps(key)}, "
                    f"{rule['cap']}, {capacity})")
    text, height = '""', "0"
    for building, members in reversed(sorted(buildings.items())):
        match = f"building.Key == {json.dumps(building)}"
        text = f"GetIfElse({match}, Loc({json.dumps(capacity_key(building))}), {text})"
        height = f"GetIfElse({match}, {18 * len(members) + 14}, {height})"
    scope = character_scope("character", data["subtypes"])
    return (f"{CCO_NAME}\n{{\n"
            "  IsCharacter(CcoCampaignCharacter character)\n  {\n"
            f"    {scope}\n  }}\n"
            "  IsPrivate(CcoBuildingLevelRecord building)\n  {\n"
            f"    IsContextValid(building) && {CCO_NAME}.IsCharacter(SelectedCharacter) "
            f"&& ({keys})\n  }}\n"
            "  Capacity(CcoMainUnitRecord unit)\n  {\n"
            f"    {capacity}\n  }}\n"
            "  CapacityText(CcoBuildingLevelRecord building)\n  {\n"
            f"    {text}\n  }}\n"
            "  CapacityHeight(CcoBuildingLevelRecord building)\n  {\n"
            f"    {height}\n  }}\n"
            "  Pairs(CcoBuildingLevelRecord building)\n  {\n"
            f'    DatabaseRecordContext("CcoUnitSetRecord", "{UNIT_SET}")'
            ".UnitsInSetList\n"
            f"      .Filter((unit) => {conditions})\n"
            f"      .Transform((unit) => MakePair(unit, {CCO_NAME}.Capacity(unit)))\n"
            "  }\n}\n")


def write_cco(stage_root, native):
    """Write the camp's read-only building-supply context."""
    cco = Path("ui/cco") / (PREFIX + "ui.cco")
    (stage_root / cco).parent.mkdir(parents=True, exist_ok=True)
    (stage_root / cco).write_text(
        cco_source(beastmen_hordes.script_data(native)), encoding="utf-8",
        newline="\n")


def adapt(tree, name, native_root, native):
    root = tree.getroot()
    if name == "character_information":
        adapt_character_information(root, beastmen_hordes.script_data(native))
    elif name == "building_construction_popup":
        adapt_costs(root, beastmen_hordes.script_data(native)["subtypes"])
        adapt_cards(root, 2)
    elif name == "building_browser":
        adapt_cards(root, 3)
    else:
        template = ET.parse(native_root / UI_FOLDER /
                            "building_info_recruitment_effects.twui.xml")
        adapt_tooltip(root, template.getroot())


UI_ADAPTATIONS = {
    f"ui/campaign ui/{name}.twui.xml":
        (lambda tree, native_root, native, name=name:
         adapt(tree, name, native_root, native))
    for name in ("character_information", *UI_NAMES[:-1])
}
