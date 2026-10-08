(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))

(fn valid [object] (and object (not (object:is_null_interface))))

(fn owned [faction]
  (local result {})
  (fn include-character [character]
    (when (and (valid character)
               (= (: (character:faction) :name) (faction:name)))
      (local subtype (character:character_subtype_key))
      (when (or (. rules.by-subtype subtype)
                (= subtype data.tamurkhan) (= subtype data.archaon))
        (tset result subtype character))))
  ;; Wounded characters count; an unlocked registry entry without a character does not.
  (local characters (faction:character_list))
  (for [i 0 (- (characters:num_items) 1)]
    (include-character (characters:item_at i)))
  (local agents (faction:unique_agents))
  (for [i 0 (- (agents:num_items) 1)]
    (include-character (: (agents:item_at i) :character)))
  result)

(fn held-elsewhere? [subtype]
  (local factions (: (: (cm:model) :world) :faction_list))
  (var found false)
  (for [i 0 (- (factions:num_items) 1) &until found]
    (local faction (factions:item_at i))
    (when (and (not= (faction:name) data.faction)
               (. (owned faction) subtype))
      (set found true)))
  found)

(fn usable? [character]
  (and (valid character) (not (character:is_wounded)) (character:has_region)))

(fn spawn-location [faction characters]
  (local tamurkhan (. characters data.tamurkhan))
  (local archaon (. characters data.archaon))
  (if (usable? tamurkhan) {:character tamurkhan}
      (usable? archaon) {:character archaon}
      (do
        (local home (faction:home_region))
        (local regions (faction:region_list))
        (local region
          (if (and (valid home) (= (: (home:owning_faction) :name) data.faction))
              home
              (> (regions:num_items) 0) (regions:item_at 0)
              nil))
        (and (valid region) {: region}))))

{: valid : owned : held-elsewhere? : spawn-location}
