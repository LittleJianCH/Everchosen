(local shared (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local data (include :everchosen_hordes.data))
(local rules (include :everchosen_hordes.rules))

(fn eligible-force [character]
  "Return only a matching bound horde commanded by its current host lord."
  (when (and (shared.valid? character)
             (character:character_type :general)
             (shared.host? (character:faction))
             (character:has_military_force))
    (let [kind (. (data.config) :subtypes
                  (character:character_subtype_key))
          force (character:military_force)]
      (when (and kind (shared.valid? force)
                 (shared.host? (force:faction)) (force:has_general)
                 (shared.valid? (force:general_character))
                 (= (: (force:force_type) :key) kind)
                 (= (: (force:general_character) :command_queue_index)
                    (character:command_queue_index)))
        force))))

(fn forces []
  (let [host (shared.host)]
    (if host
        (collect [character (shared.items (host:character_list))]
          (let [force (eligible-force character)]
            (when force
              (values (force:command_queue_index) force))))
        {})))

(fn related-character? [character]
  (and (shared.valid? character)
       (or (. (data.config) :subtypes (character:character_subtype_key))
           (and (character:has_military_force)
                (: (character:military_force) :has_effect_bundle
                   (. (data.config) :settle_bundle))))))

(fn camps [eligible]
  (icollect [_ force (pairs eligible)]
    (let [character (force:general_character)]
      (when (and (= (force:active_stance) data.settle)
                 (character:has_region))
        (let [region (character:region)
              province (and (shared.valid? region) (region:province))
              horde (force:horde_details)]
          (when (and (shared.valid? province) (shared.valid? horde))
            (let [buildings
                  (icollect [slot (shared.items
                                   (horde:military_force_slot_list))]
                    (when (slot:has_building) (slot:building)))]
              {:region (region:name) :province (province:key)
               :units (rules.camp-units (data.config) buildings)})))))))

(fn pool [region-key unit initialize?]
  "Find/register camp stock; failures return nil and a diagnostic reason."
  (let [region (cm:get_region region-key)
        province (and (shared.valid? region) (region:province))
        province-pool (and (shared.valid? province) (province:mercenary_pool))]
    (if (not (shared.valid? region)) (values nil "invalid region")
        (not (shared.valid? province)) (values nil "invalid province")
        (not (shared.valid? province-pool)) (values nil "invalid province pool")
        (let [matches (icollect [entry (shared.items
                                        (province-pool:mercenary_pool_units))]
                        (when (= (: (entry:unit_record) :key) unit) entry))
              own (accumulate [found nil _ entry (ipairs matches) &until found]
                    (when (= (entry:faction_restriction_key) scope.host) entry))]
          (if own own
              (> (length matches) 0)
              (values nil
                (.. "conflicting restrictions: "
                    (table.concat
                      (icollect [_ entry (ipairs matches)]
                        (string.format "%q" (entry:faction_restriction_key)))
                      ", ")))
              initialize?
              (do
                ;; Creation replaces stock and caps: never touch an existing
                ;; entry, including one shared with another mechanic or faction.
                (cm:add_unit_to_province_mercenary_pool
                  region unit 0 0 0 0 scope.host "" "")
                (let [(registered reason) (pool region-key unit)]
                  (if registered registered
                      (values nil (.. "registration not confirmed: " reason)))))
              (values nil "unit not represented"))))))

{: eligible-force : forces : related-character? : camps : pool}
