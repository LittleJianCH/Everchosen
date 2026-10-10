"""Derive positional skill conversions, never infer them from row order."""


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
