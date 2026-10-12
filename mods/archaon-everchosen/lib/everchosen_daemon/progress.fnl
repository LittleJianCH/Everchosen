;;; Daemon prince progression, resource limits and armory unlocks.

(local data (include :everchosen_daemon.data))
(local host (include :everchosen_core.data))
(local world (include :everchosen_core.world))

(fn config []
  (. (world.static-data) :daemon_prince))

(fn saved [key fallback]
  (or (cm:get_saved_value (.. data.prefix key)) fallback))

(fn save [key value]
  (cm:set_saved_value (.. data.prefix key) value))

(fn prince [faction]
  (when (world.valid? faction)
    (accumulate [found nil character (world.items (faction:character_list))
                 &until found]
      (when (and (world.valid? character)
                 (= (character:character_subtype_key) data.prince)
                 (= (: (character:faction) :name) (faction:name)))
        character))))

(fn resource-value [faction key]
  (: (world.resource faction key) :value))

(fn inventory [character]
  (let [armory (: (character:family_member) :armory)]
    (collect [_ key (ipairs (armory:get_currently_registered_armory_items))]
      (values key true))))

(fn all-owned? [items registered]
  (accumulate [owned? true _ item (ipairs items) &until (not owned?)]
    (. registered item)))

(fn dedication [faction]
  (accumulate [chosen nil _ god (pairs (. (config) :gods)) &until chosen]
    (when (faction:has_effect_bundle god.ritual) god.ritual)))

(fn snapshot []
  "Capture progression before changing ownership, including a wounded prince."
  (when (not (saved :snapshot))
    (let [source (cm:get_faction data.prince)]
      (when (world.valid? source)
        (save :snapshot
          {:values (collect [key _ (pairs (. (config) :gods))]
                     (values key (resource-value source key)))
           :dedication
           (accumulate [chosen nil _ god (pairs (. (config) :gods))
                        &until chosen]
             (when (source:has_effect_bundle god.native_ritual)
               god.ritual))})))))

(fn import-progress []
  (let [faction (world.host)
        previous (saved :snapshot {:values {}})]
    (when (and faction (prince faction) (not (saved :initialized)))
      (when previous.dedication
        (cm:apply_effect_bundle previous.dedication host.host 0))
      (each [key _ (pairs (. (config) :gods))]
        (let [resource (world.resource faction key)
              amount (math.min (or (. previous.values key) 0)
                               (resource:maximum_value))]
          (when (> amount (resource:value))
            (cm:faction_add_pooled_resource host.host key :events
                                            (- amount (resource:value))))))
      (each [_ god (pairs (. (config) :gods))]
        (cm:unlock_ritual faction god.ritual 0))
      (save :initialized true))))

(fn available? [faction key reward]
  (let [amount (resource-value faction reward.resource)]
    (and (>= amount reward.minimum) (<= amount reward.maximum)
         (or (not reward.achievement)
             (= false (: (cco :CcoPooledResourceThresholdOperationSetRecord key)
                         :Call :IsLockedByAchievement))))))

(fn grant [character items]
  (let [registered (inventory character)]
    (each [_ item (ipairs items)]
      (when (not (. registered item))
        ;; Acquiring a part must not change the player's equipped loadout.
        (cm:add_armory_item_to_character character item false false)))))

(fn unlock-parts [faction character]
  (let [choices (saved :choices {})
        registered (inventory character)]
    (each [key reward (pairs (. (config) :rewards))]
      (let [operations
            (icollect [operation _ (pairs reward.options)] operation)]
        (table.sort operations)
        (when (not (. choices key))
          (let [owned (accumulate [found nil _ operation (ipairs operations)
                                  &until found]
                        (when (all-owned? (. reward.options operation)
                                          registered)
                          operation))]
            (when owned (tset choices key owned))))
        (when (and (not (. choices key)) (= (length operations) 1)
                   (available? faction key reward))
          (tset choices key (. operations 1)))
        (when (. choices key)
          (grant character (. reward.options (. choices key))))))
    (save :choices choices)))

(fn donation-amount [faction key]
  (let [god (. (config) :gods key)
        chosen (dedication faction)]
    (when (and god (or (not chosen) (= chosen god.ritual)
                       (= chosen (.. data.prefix "dedicate_undivided"))))
      (let [resource (world.resource faction key)]
        (math.max 0 (math.min data.step
                              (- (resource:maximum_value)
                                 (resource:value))))))))

{: config : saved : save : prince : resource-value : inventory : all-owned?
 : dedication : snapshot : import-progress : available? : grant : unlock-parts
 : donation-amount}
