(local world (include :everchosen_core.world))

(fn counts [host]
  ;; Wounded heroes remain in the faction list and continue using capacity.
  (accumulate [result {} character (world.items (host:character_list))]
    (do
      (when (and (world.valid? character)
                 (world.host? (character:faction)))
        (let [subtype (character:character_subtype_key)]
          (tset result subtype (+ 1 (or (. result subtype) 0)))))
      result)))

(fn subtype-bonuses [host config]
  (let [bonuses (host:bonus_values)]
    (collect [subtype _ (pairs config.subtypes)]
      (values subtype (bonuses:agent_subtype_value subtype :cap)))))

(fn subtype-caps [host config]
  (collect [subtype _ (pairs config.subtypes)]
    (values subtype (host:agent_subtype_cap subtype))))

(fn class-caps [host config]
  (collect [agent _ (pairs config.classes)]
    (values agent (host:agent_cap agent))))

(fn external-capacities [host external]
  ;; This optional mod is DB-only; the Lua mod registry cannot detect it.
  (let [result {}]
    (when (common.vfs_exists external.marker_path)
      (each [manager (world.items (host:foreign_slot_managers))]
        (each [slot (world.items (manager:slots))]
          (when (and (slot:active) (slot:has_building))
            (each [_ source (ipairs external.portals)]
              (when (= (slot:building) source.building)
                (tset result source.family
                      (+ source.value (or (. result source.family) 0))))))))
      (each [region (world.items (host:region_list))]
        (each [slot (world.items (region:slot_list))]
          (when (slot:has_building)
            (let [building (slot:building)]
              ;; These optional settlement effects use 1/1/0 health values.
              (when (> (building:percent_health) 0)
                (each [_ source (ipairs external.cultists)]
                  (when (and (= (building:name) source.building)
                             (host:has_technology source.technology))
                    (tset result source.family
                          (+ source.value
                             (or (. result source.family) 0)))))
                (let [source external.anointed]
                  (when (and (= (building:name) source.building)
                             (cm:is_dlc_flag_enabled source.product
                                                     (host:name)))
                    (tset result source.family
                          (+ source.value
                             (or (. result source.family) 0)))))))))))
    result))

(fn extras [host config]
  (let [result (external-capacities host config.external)
        bonuses (host:bonus_values)]
    ;; Permanent native capacity rewards modify the base class capacity.
    ;; Subtract active bonuses, including our uplift, to retain those rewards.
    (each [agent families (pairs config.native_families)]
      (let [cap (host:agent_cap agent)
            base (if (= cap 4294967295) 0
                     (math.max 0 (- cap (bonuses:agent_value agent :cap))))]
        (each [_ family (ipairs families)]
          (tset result family (+ base (or (. result family) 0))))))
    (accumulate [result result
               character (world.items (host:character_list))]
    (do
      (when (and (world.valid? character)
                 (world.host? (character:faction)))
        (each [_ source (ipairs config.skills)]
          (when (and (character:has_skill source.key)
                     (or (not source.on_map)
                         (not (character:is_wounded))))
            (each [_ family (ipairs source.families)]
              (tset result family
                    (+ source.value (or (. result family) 0)))))))
      result))))

{: counts : subtype-bonuses : subtype-caps : class-caps : extras}
