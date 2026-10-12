(local shared (include :everchosen_inheritance.world))
(local inheritance (include :everchosen_inheritance.data))
(local data (include :everchosen_hordes.data))
(local rules (include :everchosen_hordes.rules))
(local world (include :everchosen_hordes.world))

;; Listener registration belongs to this Lua session, not the campaign save.
(var started? false)
;; Several engine events can describe the same in-flight army change.
(var sync-pending? false)

(fn log [message]
  (out (.. "[Everchosen hordes] " message)))

(fn saved []
  (or (cm:get_saved_value data.state-key)
      {:turn -1 :provinces {} :forces {}}))

(fn persist [state]
  (cm:set_saved_value data.state-key state))

(fn sync-start []
  (let [host (shared.host)
        bundle (. (data.config) :start_bundle)]
    (when (not (host:has_effect_bundle bundle))
      (cm:apply_effect_bundle bundle inheritance.host 0)
      (when (not (host:has_effect_bundle bundle))
        (log "New-horde configuration was not applied")))))

(fn sync-stances [state eligible]
  (let [bundle (. (data.config) :settle_bundle)]
    (each [cqi _ (pairs eligible)] (tset state.forces cqi true))
    (persist state)
    (each [cqi force (pairs eligible)]
      (when (not (force:has_effect_bundle bundle))
        (cm:apply_effect_bundle_to_force bundle cqi 0)
        (when (not (force:has_effect_bundle bundle))
          (log (.. "Encampment permission was not applied: " cqi)))))
    (each [_ cqi (ipairs (rules.sorted-keys state.forces))]
      (when (not (. eligible cqi))
        (let [force (cm:get_military_force_by_cqi cqi)]
          (when (and (shared.valid? force) (force:has_effect_bundle bundle))
            (cm:remove_effect_bundle_from_force bundle cqi))
          (if (and (shared.valid? force) (force:has_effect_bundle bundle))
              (log (.. "Encampment remains on ineligible force: " cqi))
              (tset state.forces cqi nil)))))))

(fn remember [state active]
  (each [province camp (pairs active)]
    (let [entry (or (. state.provinces province)
                    {:region camp.region :units {}})]
      (each [unit _ (pairs camp.units)] (tset entry.units unit true))
      (tset state.provinces province entry))))

(fn sync-pool [entry unit active?]
  (let [config (data.config)
        pool (world.pool entry.region unit)]
    (if pool
        (let [before (pool:unit_count)
              previous (pool:scripted_capacity_bonus_for_source
                          config.pool_source)
              target (rules.capacity
                       (if active? (. config.units unit :cap) 0)
                       previous (pool:current_max_units) before)]
          (when (not= previous target)
            (cm:set_mercenary_pool_unit_scripted_capacity_bonus
              pool target config.pool_source))
          ;; This engine command returns no success result. Re-query its state.
          (let [current (world.pool entry.region unit)]
            (if (and current
                     (= (current:scripted_capacity_bonus_for_source
                          config.pool_source) target)
                     (>= (current:unit_count) before))
                (or active? (> target 0))
                (do (log (.. "Pool capacity update not confirmed: "
                             entry.region "/" unit)) true))))
        (do (log (.. "Missing host pool: " entry.region "/" unit)) true))))

(fn sync-capacities [state active]
  (remember state active)
  (persist state)
  (each [_ province (ipairs (rules.sorted-keys state.provinces))]
    (let [entry (. state.provinces province)
          camp (. active province)]
      (each [_ unit (ipairs (rules.sorted-keys entry.units))]
        (when (not (sync-pool entry unit
                     (and camp (. camp.units unit))))
          (tset entry.units unit nil)))
      (when (not (next entry.units))
        (tset state.provinces province nil)))))

(fn reconcile [state]
  (let [eligible (world.forces)
        active (rules.provinces (world.camps eligible))]
    (sync-start)
    (sync-stances state eligible)
    (sync-capacities state active)
    (persist state)
    active))

(fn sync []
  (when (shared.host) (reconcile (saved))))

(fn replenish-unit [entry unit chance]
  (let [pool (world.pool entry.region unit)
        config (data.config)]
    (when (and pool
               (>= (pool:scripted_capacity_bonus_for_source config.pool_source)
                   (. config.units unit :cap))
               (< (pool:unit_count) (. config.units unit :cap))
               (< (pool:unit_count) (pool:current_max_units))
               (<= (cm:random_number 100) chance))
      (let [before (pool:unit_count)]
        (cm:add_units_to_province_mercenary_pool_by_region entry.region unit 1)
        (let [current (world.pool entry.region unit)]
          (when (or (not current) (not= (current:unit_count) (+ before 1)))
            (log (.. "Stock addition not confirmed: "
                     entry.region "/" unit))))))))

(fn refresh []
  (when (shared.host)
    (let [state (saved)
          active (reconcile state)
          turn (cm:turn_number)]
      (when (not= state.turn turn)
        ;; Record before draws and commands; repeated events cannot reroll.
        (set state.turn turn)
        (persist state)
        (each [_ province (ipairs (rules.sorted-keys active))]
          (let [entry (. active province)]
            (each [_ unit (ipairs (rules.sorted-keys entry.units))]
              (replenish-unit entry unit (. entry.units unit)))))))))

(fn safely-sync []
  (set sync-pending? false)
  (let [(ok? error) (pcall sync)]
    (when (not ok?) (log (tostring error)))))

(fn safely-refresh []
  (let [(ok? error) (pcall refresh)]
    (when (not ok?) (log (tostring error)))))

(fn request-sync []
  ;; Recruitment and battle returns can precede the completed model change.
  (when (not sync-pending?)
    (set sync-pending? true)
    (cm:callback safely-sync 0.2)))

(fn related? [context]
  (world.related-character? (context:character)))

(fn listen [suffix event condition callback]
  (core:add_listener (.. data.prefix suffix) event condition callback true))

(fn start []
  (when (and (not started?) (shared.host))
    (set started? true)
    (safely-sync)
    (listen :turn :FactionTurnStart #(shared.host? ($1:faction))
            safely-refresh)
    (each [_ event (ipairs [:CharacterSelected :CharacterRecruited
                            :CharacterFactionChangeEvent
                            :CharacterFinishedMovingEvent
                            :CharacterHordeBuildingDemolished
                            :MilitaryForceBuildingCompleteEvent])]
      (listen event event related? request-sync))
    (listen :created :MilitaryForceCreated
      #(shared.host? (: ($1:military_force_created) :faction)) request-sync)
    (listen :stance :ForceAdoptsStance
      #(shared.host? (: ($1:military_force) :faction)) request-sync)
    (listen :trained :UnitTrained
      #(shared.host? (: ($1:unit) :faction)) request-sync)
    (each [_ event (ipairs [:CharacterConvalescedOrKilled
                            :MilitaryForceDestroyed
                            :FactionJoinsConfederation
                            :ScriptEventArchaonSubjugatesChaosFaction])]
      (listen event event true request-sync))))

{: start}
