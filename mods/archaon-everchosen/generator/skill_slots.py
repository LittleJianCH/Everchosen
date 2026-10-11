"""Preserve skill positions and isolate the dependency paths being adapted."""


def linked_nodes(native, nodes, changed, prefix):
    """Map every node connected to CHANGED within this native tree.

    Links belong to nodes, not node sets. Sharing a neighbour of a replaced
    node would retain its original prerequisite in the adapted tree and add
    the replacement prerequisite to the native tree.
    """
    neighbours = {row["key"]: set() for row in nodes}
    for row in native["character_skill_node_links"].rows:
        parent, child = row["parent_key"], row["child_key"]
        if parent in neighbours and child in neighbours:
            neighbours[parent].add(child)
            neighbours[child].add(parent)
    connected = set(changed)
    pending = list(changed)
    while pending:
        for key in neighbours[pending.pop()] - connected:
            connected.add(key)
            pending.append(key)
    return {key: prefix + key for key in sorted(connected)}


def links(native, replacements):
    """Copy internal links only, with both ends private to the variant."""
    for row in native["character_skill_node_links"].rows:
        if row["parent_key"] in replacements and row["child_key"] in replacements:
            yield "character_skill_node_links", dict(
                row, parent_key=replacements[row["parent_key"]],
                child_key=replacements[row["child_key"]])


def validate_trees(native, generated):
    """Check prerequisites inside each new tree, not just global DB keys."""
    nodes = generated.get("character_skill_nodes", [])
    keys = {row["key"] for row in nodes}
    if len(keys) != len(nodes):
        raise ValueError("Duplicated adapted skill node")
    new_links = generated.get("character_skill_node_links", [])
    all_links = native["character_skill_node_links"].rows + new_links
    parents = {}
    for row in all_links:
        parents.setdefault(row["child_key"], set()).add(row["parent_key"])
    added = generated.get("character_skill_node_set_items", [])
    trees = {row["key"] for row in generated.get("character_skill_node_sets", [])}
    trees.update(row["set"] for row in added)
    for tree in trees:
        items = {(row["set"], row["item"]): row for row in
                 native["character_skill_node_set_items"].where(set=tree)}
        items.update({(row["set"], row["item"]): row for row in added
                      if row["set"] == tree})
        members = {row["item"] for row in items.values()
                   if row["mod_disabled"] == "false"}
        for child in sorted(members):
            missing = parents.get(child, set()) - members
            if missing:
                raise ValueError(f"Skill prerequisite outside {tree}: "
                                 f"{child} <- {sorted(missing)}")
    for row in new_links:
        if row["parent_key"] not in keys or row["child_key"] not in keys:
            raise ValueError("Adapted skill link changes a shared native node")


def mapping(native, pairs, other_nodes=()):
    levels = native["character_skill_level_to_effects_junctions"]
    result = []
    for old, new, maximum in pairs:
        if (old["indent"], old["tier"]) != (new["indent"], new["tier"]):
            raise ValueError("Converted skill moved to a different position")
        source, target = old["character_skill_key"], new["character_skill_key"]
        old_max = max(int(r["level"]) for r in
                      levels.where(character_skill_key=source))
        if maximum < old_max:
            raise ValueError("Converted skill would discard invested points")
        if source != target:
            result.append({"source": source, "target": target,
                           "source_max": old_max, "target_max": maximum})
    source_keys = [r["source"] for r in result]
    target_keys = [r["target"] for r in result]
    if len(set(source_keys)) != len(source_keys) or len(set(target_keys)) != len(target_keys):
        raise ValueError("Skill conversion has ambiguous positions")
    changed = set(source_keys) | set(target_keys)
    if changed & {r["character_skill_key"] for r in other_nodes}:
        raise ValueError("Converted blue-line skill is shared with another line")
    return result
