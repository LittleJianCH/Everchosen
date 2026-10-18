(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local initialized :everchosen_regiments_initialized)

(fn pool-entries [faction]
  (let [pool (faction:mercenary_pool)]
    (assert (world.valid? pool) "Missing faction mercenary pool")
    (collect [entry (world.items (pool:mercenary_pool_units))]
      (when (or (= (entry:faction_restriction_key) "")
                (= (entry:faction_restriction_key) scope.host))
        (values (: (entry:unit_record) :key) entry)))))

(fn verify [records]
  ;; A successful command submission does not prove that a pool entry exists.
  (let [faction (assert (world.host))
        actual (pool-entries faction)]
    (each [_ record (ipairs records)]
      (let [entry (. actual record.unit)]
        (assert entry (.. "RoR pool registration missing: " record.unit))
        (assert (= (entry:base_max_units) record.maximum)
                (.. "Unexpected RoR pool capacity: " record.unit))))
    (out (.. "[Everchosen regiments] Confirmed " (length records)
             " additional RoR pool entries"))))

(fn start []
  ;; The engine saves the pool itself; reloading must never refill its stock.
  (when (and (cm:is_new_game) (world.host)
             (not (core:get_static_object initialized)))
    (core:add_static_object initialized true)
    (let [faction (world.host)
          records (. (world.static-data) :regiments_of_renown)
          existing (pool-entries faction)]
      (each [_ record (ipairs records)]
        (when (not (. existing record.unit))
          (cm:add_unit_to_faction_mercenary_pool
            faction record.unit record.source record.count record.chance
            record.maximum record.rate record.faction record.subculture
            record.technology record.partial record.group)))
      (cm:callback (world.guarded "Everchosen regiments" #(verify records))
                   0.1))))

{: start}
