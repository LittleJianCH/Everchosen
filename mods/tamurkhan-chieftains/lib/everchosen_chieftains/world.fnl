;;; Queries against the campaign model.

(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))

(fn guarded [label callback]
  "Log a callback's Lua error without interrupting later event listeners."
  ;; WH3 9.0.3 lib_core only protects callbacks when its tweaker is enabled.
  (fn [...]
    (let [(ok? error) (pcall callback ...)]
      (when (not ok?) (out (.. "[" label "] " (tostring error)))))))

(fn next-init-action [character hero target-rank]
  "Next missing initialization result, or nil when all are observed."
  ;; WH3 9.0.3: these are character queries in the Assembly Kit API docs.
  (if (not (character:has_ancillary hero.ancillary))
      {:kind :ancillary :key hero.ancillary}
      (and hero.extra (not (character:has_ancillary hero.extra)))
      {:kind :ancillary :key hero.extra}
      (< (character:trait_points hero.trait) 1)
      {:kind :trait :key hero.trait}
      (< (character:rank) target-rank)
      {:kind :experience :amount (- target-rank (character:rank))}))

(fn valid? [object]
  (and object (not (object:is_null_interface))))

(fn items [list]
  "Iterate a game list interface, which is zero-indexed."
  (let [count (list:num_items)]
    (var index -1)
    (fn []
      (set index (+ index 1))
      (if (< index count) (list:item_at index)))))

(fn faction-key [character]
  (: (character:faction) :name))

(fn ours? [character subtype]
  "Whether CHARACTER is a SUBTYPE currently owned by the host faction."
  (and (valid? character)
       (= (faction-key character) data.faction)
       (= (character:character_subtype_key) subtype)))

(fn tracked? [subtype]
  (or (not= nil (. rules.by-subtype subtype))
      (= subtype data.tamurkhan)
      (= subtype data.archaon)))

(fn owned [faction]
  "Map each tracked subtype key to the character FACTION owns."
  (let [key (faction:name)
        result {}]
    (fn track [character]
      (when (and (valid? character) (= (faction-key character) key))
        (let [subtype (character:character_subtype_key)]
          (when (tracked? subtype)
            (tset result subtype character)))))
    ;; Wounded characters count; an unlocked registry entry without a
    ;; character does not.
    (each [character (items (faction:character_list))]
      (track character))
    (each [agent (items (faction:unique_agents))]
      (track (agent:character)))
    result))

(fn usable? [character]
  (and (valid? character) (not (character:is_wounded)) (character:has_region)))

(fn fallback-region [faction]
  (let [home (faction:home_region)
        regions (faction:region_list)]
    (if (and (valid? home) (= (: (home:owning_faction) :name) data.faction))
        home
        (> (regions:num_items) 0)
        (regions:item_at 0))))

(fn spawn-location [faction characters]
  "Where a new chieftain can appear: {: character}, {: region}, or nil."
  (let [tamurkhan (. characters data.tamurkhan)
        archaon (. characters data.archaon)]
    (if (usable? tamurkhan) {:character tamurkhan}
        (usable? archaon) {:character archaon}
        (let [region (fallback-region faction)]
          (if (valid? region) {: region})))))

{: valid? : items : ours? : owned : spawn-location : next-init-action
 : guarded}
