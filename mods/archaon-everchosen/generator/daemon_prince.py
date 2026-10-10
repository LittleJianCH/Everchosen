"""Native body-part progression, with rewards directed at the acquired prince.

Threshold records are read by the UI and script, never attached to Archaon's
resource manager: their engine armory operations address the faction leader.
Only the resources and the resource-related effects of dedication are inherited.
"""
import xml.etree.ElementTree as ET
from copy import deepcopy
from uuid import NAMESPACE_URL, uuid5
import daemon_legion

PREFIX = "everchosen_daemon_"
HOST = "wh_main_chs_chaos"
PRINCE = "wh3_main_dae_daemon_prince"
GODS = {"khorne": "kho", "nurgle": "nur", "slaanesh": "sla",
        "tzeentch": "tze", "undivided": "und"}
GROUP = "everchosen_inheritance_host"
TABLES = """campaign_group_pooled_resources campaign_group_rituals
    pooled_resources pooled_resource_factor_junctions
    campaign_group_pooled_resource_threshold_operation_sets
    pooled_resource_threshold_operation_sets operation_set_groups
    operation_set_to_operation_group_junctions campaign_operation_sets
    campaign_operation_set_armory_item_elements campaign_operation_armory_items
    armory_items ritual_payloads ritual_payload_effect_bundles
    effect_bundles effect_bundles_to_effects_junctions
    resource_costs resource_cost_pooled_resource_junctions
""".split() + daemon_legion.TABLES
UI_NAMES = ("character_details_panel", "character_details_panel_dae_gifts",
            "daemonic_progression", "tooltip_ritual", "tooltip_effect_bundle")


def ui_path(name):
    folder = "common ui" if name == "tooltip_effect_bundle" else "campaign ui"
    return f"ui/{folder}/{name}.twui.xml"


def resource(god):
    return f"wh3_main_dae_{god}_points"


def ritual(god):
    return PREFIX + "dedicate_" + god


def rows(native):
    for god in GODS:
        row = native["campaign_group_pooled_resources"].one(
            campaign_group="wh3_main_feature_daemons", resource=resource(god))
        yield "campaign_group_pooled_resources", dict(
            row, campaign_group=GROUP, initial_amount="0")
        source = f"wh3_main_ritual_dae_ascend_{god}"
        target = ritual(god)
        row = native["rituals"].one(key=source)
        yield "rituals", dict(row, key=target, completion_payload=target)
        # The original payload's resource-unlock operation assumes an engine
        # threshold manager. Here the script awards parts to the prince instead.
        row = native["ritual_payloads"].one(key=source)
        yield "ritual_payloads", dict(row, key=target, payload_base="")
        row = native["ritual_payload_effect_bundles"].one(payload=source)
        yield "ritual_payload_effect_bundles", dict(
            row, payload=target, effect_bundle=target)
        row = native["effect_bundles"].one(key=source)
        yield "effect_bundles", dict(row, key=target)
        for row in native["effect_bundles_to_effects_junctions"].where(
                effect_bundle_key=source):
            effect = row["effect_key"]
            if ("_points_maximum_mod" in effect or
                    "_points_income_disabled" in effect or
                    "_dedicate_" in effect or
                    effect == "wh3_main_effect_disable_ritual_dae_ascend"):
                yield "effect_bundles_to_effects_junctions", dict(
                    row, effect_bundle_key=target)
        row = native["campaign_group_rituals"].one(
            campaign_group="wh3_main_feature_daemons", ritual=source)
        yield "campaign_group_rituals", dict(
            row, campaign_group=GROUP, ritual=target,
            initially_unlocked="false")
    permission = native["faction_agent_permitted_subtypes"].one(
        faction=HOST, subtype="wh3_main_nur_kugath")
    yield "faction_agent_permitted_subtypes", dict(permission, subtype=PRINCE)


def script_data(native):
    thresholds = native["pooled_resource_threshold_operation_sets"]
    memberships = native["campaign_group_pooled_resource_threshold_operation_sets"]
    ordinary = {r["pooled_resource_threshold_operation_set"] for r in
                memberships.where(campaign_group="wh3_main_feature_daemons")}
    rewards = {}
    for threshold in thresholds.rows:
        key = threshold["key"]
        if key not in ordinary and not key.startswith("wh3_pro10_"):
            continue
        if threshold["pooled_resource_set"] not in {resource(g) for g in GODS}:
            continue
        options = {}
        for row in native["operation_set_to_operation_group_junctions"].where(
                operation_group=threshold["operation_set_group"]):
            operation = row["operation_set"]
            items = []
            for element in native["campaign_operation_set_armory_item_elements"].where(
                    operation_set=operation):
                item = native["campaign_operation_armory_items"].one(
                    key=element["operation_armory_item"], is_removal="false")
                native["armory_items"].one(key=item["armory_item"])
                items.append(item["armory_item"])
            if items:
                options[operation] = items
        if options:
            rewards[key] = {"resource": threshold["pooled_resource_set"],
                            "minimum": int(threshold["lower_bound"]),
                            "maximum": int(threshold["upper_bound"]),
                            "achievement": key not in ordinary,
                            "options": options}
    if not rewards or not any(r["achievement"] for r in rewards.values()):
        raise ValueError("Missing native armory or achievement thresholds")
    gods = {}
    for god, short in GODS.items():
        glory = resource(god)
        spent = "wh3_dlc20_chs_souls_spent_" + short
        for key, factor in ((glory, "events"), (spent, "gifts_of_chaos"),
                            ("wh3_dlc20_chs_souls", "gifts_of_chaos")):
            native["pooled_resources"].one(key=key)
            native["pooled_resource_factor_junctions"].one(
                resource=key, factor=factor)
        native_ritual = native["rituals"].one(
            key=f"wh3_main_ritual_dae_ascend_{god}")
        cost = native["resource_cost_pooled_resource_junctions"].one(
            resource_cost=native_ritual["required_resources"])
        factor = native["pooled_resource_factor_junctions"].one(
            unique_id=cost["pooled_resource_factor"])
        if (factor["resource"] != glory or cost["context"] != "absolute"
                or native_ritual["expended_resources"]):
            raise ValueError("Changed native dedication resource contract")
        gods[glory] = {"name": god, "spent": spent, "ritual": ritual(god),
                       "dedication_minimum": -int(cost["amount"]),
                       "glory_factor": native["pooled_resource_factor_junctions"].one(
                           resource=glory, factor="events")["factor"],
                       "spent_factor": native["pooled_resource_factor_junctions"].one(
                           resource=spent, factor="gifts_of_chaos")["factor"],
                       "native_ritual": f"wh3_main_ritual_dae_ascend_{god}"}
    return {"gods": gods, "rewards": rewards,
            "legions": daemon_legion.progression(native),
            "souls_factor": native["pooled_resource_factor_junctions"].one(
                resource="wh3_dlc20_chs_souls", factor="gifts_of_chaos")["factor"]}


EXPR = "context_function_id"
HOST_UI = ('PlayersFaction.FactionRecordContext.Key == "' + HOST + '" && '
           'ScriptObjectContext("' + PREFIX + 'enabled").NumericValue == 1')
CHARACTER = ('PlayersFaction.CharacterList.FirstContext('
             'AgentSubtypeRecordContext.Key == "' + PRINCE + '")')


def callback(parent, kind, context=None, expression=None, **properties):
    attributes = {"callback_id": kind}
    if context:
        attributes["context_object_id"] = context
    if expression:
        attributes[EXPR] = expression
    element = ET.SubElement(parent, "callback_with_context", attributes)
    if properties:
        props = ET.SubElement(element, "child_m_user_properties")
        for name, value in properties.items():
            ET.SubElement(props, "property", name=name, value=value)
    return element


def components(tree, name):
    return [e for e in tree.getroot().find("components") if e.get("id") == name]


def conditional(native, replacement):
    return f'GetIfElse({HOST_UI}, {replacement}, {native})'


def adapt(tree, name, native_root, native):
    root = tree.getroot()
    if name in ("daemonic_progression", "character_details_panel_dae_gifts"):
        # Precache occurs before campaign Lua sets its UI flags.
        root.set("precache_condition", f'({root.get("precache_condition")}) || '
                 f'PlayersFaction.FactionRecordContext.Key == "{HOST}"')
    if name == "character_details_panel":
        for e in root.iter("callback_with_context"):
            expression = e.get(EXPR, "")
            if expression == ('FactionContext.CultureContext.Key == '
                              '"wh3_main_dae_daemons" && CanUseArmoryItems'):
                e.set(EXPR, f'({expression}) || ({HOST_UI} && '
                      f'AgentSubtypeRecordContext.Key == "{PRINCE}")')
        return
    if name == "tooltip_effect_bundle":
        for element in root.iter("callback_with_context"):
            expression = element.get(EXPR, "")
            source = "PooledResourceList.FirstContext.IconPath"
            if source in expression:
                element.set(EXPR, conditional(expression,
                    'Format(Loc("everchosen_daemon_legion_requirement"), '
                    'LowerBound, PooledResourceContext.Name)'))
        return
    if name == "tooltip_ritual":
        for element in root.iter("callback_with_context"):
            if (element.get("callback_id") == "ContextImageSetter" and
                    element.get("context_object_id") ==
                    "CcoCampaignPooledResourceTransaction"):
                expression = element.get(EXPR)
                for god in GODS:
                    expression = (
                        f'GetIfElse(ResourceKey == "{resource(god)}", '
                        f'"ui/skins/wh3_dae_main_dae_daemons/icon_dae_{god}_points.png", '
                        f'{expression})')
                element.set(EXPR, conditional(element.get(EXPR), expression))
        return
    if name != "daemonic_progression":
        return
    # Recruitment is provided by Warriors of Chaos. Replace native faction
    # rewards with character-bound legion training, while preserving Daniel's UI.
    for component in components(tree, "template_unit_icon") + components(
            tree, "template_unit_icon_ascend"):
        cbs = component.find("callbacks_with_context")
        if cbs is None:
            cbs = component.find("callbackwithcontextlist")
        callback(cbs, "ContextVisibilitySetter", "CcoStaticObject",
                 f'({HOST_UI}) == false')
    for component in components(tree, "template_effect") + components(
            tree, "template_effect_ascend"):
        cbs = component.find("callbacks_with_context")
        if cbs is None:
            cbs = component.find("callbackwithcontextlist")
        callback(cbs, "ContextVisibilitySetter",
                 "CcoPooledResourceThresholdOperationSetRecord",
                 conditional("true", f'Key.Contains("{PREFIX}legion_")'))
    for element in root.iter():
        for attribute in (EXPR, "value"):
            expression = element.get(attribute, "")
            if "PlayersFaction.FactionLeaderContext" in expression:
                element.set(attribute, conditional(expression, expression.replace(
                    "PlayersFaction.FactionLeaderContext", CHARACTER)))
            elif "IsComplete" in expression:
                complete = ('(IsComplete || ScriptObjectContext("' + PREFIX +
                            'dedication").StringValue == Key)')
                element.set(attribute, conditional(expression,
                    expression.replace("IsComplete", complete)))

    # Archaon must not enter the daemon faction's native ascension ritual.
    # A campaign command applies the scoped dedication bundle to this host.
    for button in components(tree, "button_ascend"):
        for element in button.iter("callback_with_context"):
            expression = element.get(EXPR, "")
            if element.get("callback_id") == "ContextCommandLeftClick":
                element.set(EXPR, f'DoIf(({HOST_UI}) == false, {expression})')
            elif element.get("callback_id") == "ContextInactiveStateSetter":
                element.set(EXPR, conditional(expression,
                    'ScriptObjectContext("' + PREFIX + 'can_dedicate_" + '
                    'StoredContextFromParent("CcoCampaignPooledResource").Key)'
                    '.NumericValue == 1'))

    # Store each row's resource before introducing a database-record context.
    for row in components(tree, "upgrade_row_entry"):
        cbs = row.find("callbackwithcontextlist")
        if cbs is None:
            cbs = ET.SubElement(row, "callbackwithcontextlist")
        callback(cbs, "ContextObjectStore", "CcoCampaignPooledResource")
    # Select verified native records by key; no faction threshold manager is
    # installed on Archaon because its operations would award his body parts.
    rewards = {**script_data(native)["rewards"],
               **daemon_legion.progression(native)}
    record_list = 'DatabaseRecordsForKeys("CcoPooledResourceThresholdOperationSetRecord")'
    for god in GODS:
        keys = sorted(key for key, reward in rewards.items()
                      if reward["resource"] == resource(god))
        if not keys:
            raise ValueError("No body-part thresholds for " + god)
        records = ('DatabaseRecordsForKeys("CcoPooledResourceThresholdOperationSetRecord", '
                   + ', '.join('"' + key + '"' for key in keys) + ')')
        record_list = ('GetIfElse(StoredContextFromParent("CcoCampaignPooledResource").Key '
                       f'== "{resource(god)}", {records}, {record_list})')
    for component in list(root.find("components")):
        cbs = component.find("callbackwithcontextlist")
        if cbs is None:
            continue
        for element in list(cbs):
            expression = element.get(EXPR, "")
            if (element.get("callback_id") == "ContextList" and
                    expression.startswith("Join(ActiveThresholdSetList")):
                end = expression.index(").Filter(")
                element.set(EXPR, conditional(expression,
                    record_list + expression[end + 1:]))
    # Resource icons otherwise resolve through the Warriors of Chaos skin.
    icon_path = '"ui/skins/wh3_dae_main_dae_daemons/icon_dae_undivided_points.png"'
    for god in GODS:
        icon_path = (f'GetIfElse(Key == "{resource(god)}", '
                     f'"ui/skins/wh3_dae_main_dae_daemons/icon_dae_{god}_points.png", '
                     f'{icon_path})')
    for component in components(tree, "race_symbol"):
        for element in component.iter("callback_with_context"):
            if element.get("callback_id") == "ContextImageSetter":
                element.set(EXPR, conditional(element.get(EXPR), icon_path))
    for element in root.iter("callback_with_context"):
        expression = element.get(EXPR, "")
        if expression.endswith(".ChooseOperationSet(PlayersFaction, this)"):
            element.set(EXPR, conditional(expression,
                'TriggerScriptEvent(Format("' + PREFIX + 'choose:%s:%s", '
                'StoredContextFromParent("CcoPooledResourceThresholdOperationSetRecord").Key, Key))'))

    # These decorations also read the engine's threshold choices. The host
    # tracks choices on the prince instead of attaching operations to Archaon.
    for component in components(tree, "cost"):
        for element in component.iter("callback_with_context"):
            expression = element.get(EXPR, "")
            empty = "ActiveOperationSetList(PlayersFaction).IsEmpty"
            if empty in expression:
                element.set(EXPR, conditional(expression, expression.replace(
                    empty, '(ScriptObjectContext("' + PREFIX +
                    'threshold_" + Key).NumericValue == 0)')))
    for component in components(tree, "divider_arrow"):
        for prop in component.iter("property"):
            expression = prop.get("value", "")
            if expression.startswith("Join(PooledResourceContext.ActiveThresholdSetList"):
                end = expression.index(").Filter(")
                prop.set("value", conditional(
                    expression, record_list + expression[end + 1:]))

    # Keep CA's inventory states for the native faction. Our states read the
    # verified grants to this prince instead of Archaon's engine operation set.
    for component in components(tree, "template_armory_bundle") + components(
            tree, "template_armory_item"):
        for prop in component.iter("property"):
            expression = prop.get("value", "")
            selected = ('ScriptObjectContext("' + PREFIX + 'operation_" + '
                        'StoredContext("CcoCampaignOperationSetRecord").Key).NumericValue == 1')
            chosen = ('ScriptObjectContext("' + PREFIX + 'threshold_" + Key)'
                      '.NumericValue == 1')
            changes = {"1.selected": selected,
                       "2.inactive": f'({chosen}) && ({selected}) == false',
                       "3.active": ('IsLockedByAchievement == false && '
                                    'PooledResourceList.FirstContext.Total >= LowerBound')}
            if prop.get("name") in changes:
                prop.set("value", conditional(expression, changes[prop.get("name")]))

    for element in root.iter():
        for attribute in (EXPR, "value"):
            expression = element.get(attribute, "")
            if "PooledResourceList.FirstContext" in expression:
                element.set(attribute, conditional(expression, expression.replace(
                    "PooledResourceList.FirstContext",
                    'StoredContextFromParent("CcoCampaignPooledResource")')))

    # The native dev-only control already sits beneath each god's resource
    # symbol. Replace its entire template with a normal campaign text button.
    button = components(tree, "dev_button_add_points")[0]
    guid = button.get("this")
    template = ET.parse(native_root / "ui/templates/square_medium_text_button.twui.xml")
    native_button = components(template, "square_medium_text_button")[0]
    remap = {e.get("this"): str(uuid5(NAMESPACE_URL, PREFIX + e.get("this"))).upper()
             for e in template.iter() if e.get("this")}
    remap[native_button.get("this")] = guid
    for e in template.iter():
        for attribute, value in list(e.attrib.items()):
            if value in remap:
                e.set(attribute, remap[value])
        e.attrib.pop("uniqueguid_in_template", None)
    button.clear()
    button.tag = "everchosen_daemon_sacrifice"
    button.attrib.update(native_button.attrib)
    button.set("id", button.tag)
    button.set("offset", "-4.00,130.00")
    button.set("allowhorizontalresize", "false")
    button.set("priority", "70")
    button.extend(deepcopy(list(native_button)))
    for state in button.find("states"):
        state.set("width", "88")
        state.set("height", "28")
        for metric in state.findall("imagemetrics/image"):
            metric.set("width", "88")
            metric.set("height", "28")
    text = components(template, "button_txt")[0]
    # The Chinese header font sits above the visual centre of this frame.
    text.set("offset", "0.00,3.00")
    text.set("dock_offset", "0.00,3.00")
    text.set("isrelativeresize", "false")
    text.set("allowhorizontalresize", "false")
    for state in text.find("states"):
        state.set("width", "80")
        state.set("height", "28")
    text_callbacks = ET.SubElement(text, "callbackwithcontextlist")
    callback(text_callbacks, "ContextTextLabel", "CcoCampaignPooledResource",
             'Loc("' + PREFIX + 'sacrifice")')
    for name in ("button_txt",):
        root.find("components").append(deepcopy(components(template, name)[0]))
    cbs = button.find("callbackwithcontextlist")
    for cb in list(cbs):
        if cb.get("callback_id") == "TextButton":
            cbs.remove(cb)
    callback(cbs, "ContextVisibilitySetter", "CcoStaticObject", HOST_UI)
    callback(cbs, "ContextTooltipSetter", "CcoCampaignPooledResource",
             'Loc("' + PREFIX + 'sacrifice_tooltip")')
    callback(cbs, "ContextInactiveStateSetter", "CcoCampaignPooledResource",
             'ScriptObjectContext("' + PREFIX + 'can_" + Key).NumericValue == 1')
    for element in list(root.find("hierarchy").iter()):
        if element.get("this") == guid:
            element.tag = button.tag
            element.clear()
            element.set("this", guid)
            children = template.getroot().find(
                "hierarchy/root/square_medium_text_button")
            element.extend(deepcopy([child for child in children
                                     if child.tag == "button_txt"]))
