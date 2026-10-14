;;; Military building unlocks and city-scaled local recruitment discounts.

(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local subjugation (include :everchosen_subjugation.state))
(local data (include :everchosen_vassal_recruitment.data))

;; Listener registration and an in-flight refresh are session-local guards.
(var started? false)
(var pending? false)
;; Reapply once after load, then only when a race unlock changes.
(var building-state {})

(fn log [message]
  (out (.. "[Everchosen vassal recruitment] " message)))

(fn unlocked? [race completed]
  (accumulate [found? false _ target (ipairs race.targets)
               &until found?]
    (or found? (. completed target) false)))

(fn city-count [host subculture]
  (accumulate [total 0 faction (world.factions)]
    (if (and (world.valid? faction) (not (faction:is_dead))
             (= (faction:subculture) subculture)
             (faction:is_vassal_of host))
        (+ total (faction:num_regions))
        total)))

(fn sync-discount [host race unlocked applied]
  (let [cities (if unlocked (city-count host race.subculture) 0)
        amount (- (math.min data.discount-cap
                            (* cities data.discount-per-city)))
        present? (host:has_effect_bundle race.bundle)]
    (if (= amount 0)
        (do
          (when present?
            (cm:remove_effect_bundle race.bundle scope.host))
          (when (not (host:has_effect_bundle race.bundle))
            (tset applied race.name 0)))
        (when (or (not present?) (not= (. applied race.name) amount))
          (let [bundle (cm:create_new_custom_effect_bundle race.bundle)]
            (bundle:set_effect_value_by_key race.effect amount)
            (bundle:set_duration 0)
            (cm:apply_custom_effect_bundle_to_faction bundle host)
            (if (host:has_effect_bundle race.bundle)
                (tset applied race.name amount)
                (log (.. "Recruitment bonus not applied: " race.name))))))))

(fn sync []
  (set pending? false)
  (let [host (world.host)]
    (when host
      (let [completed (subjugation.saved subjugation.done-key)
            generated (. (world.static-data) :vassal_military_buildings)
            applied (or (cm:get_saved_value data.applied-key) {})]
        (each [_ race (ipairs data.races)]
          (let [config (. generated race.name)
                unlocked (unlocked? race completed)
                state (if unlocked :unlocked :locked)]
            (when (not= (. building-state race.name) state)
              (cm:restrict_buildings_for_faction
                scope.host config.levels (not unlocked))
              (tset building-state race.name state))
            (sync-discount host race unlocked applied)))
        (cm:set_saved_value data.applied-key applied)))))

(local safely-sync (world.guarded "Everchosen vassal recruitment" sync))

(fn request []
  ;; Ownership and diplomatic relationships can settle after their event.
  (when (not pending?)
    (set pending? true)
    (cm:callback safely-sync 0.2)))

(fn restrict-unsupported []
  (let [faction (cm:get_faction scope.host)]
    (when (world.valid? faction)
      (let [generated (. (world.static-data) :vassal_military_buildings)]
        (each [_ race (ipairs data.races)]
          (cm:restrict_buildings_for_faction
            scope.host (. generated race.name :levels) true))))))

(fn start []
  (when (not started?)
    (set started? true)
    (if (world.host)
        (do
          (core:add_listener :everchosen_vassal_recruitment_subjugation
            :ScriptEventArchaonSubjugatesChaosFaction true
            (world.guarded "Everchosen vassal recruitment" request) true)
          (core:add_listener :everchosen_vassal_recruitment_region
            :RegionFactionChangeEvent true
            (world.guarded "Everchosen vassal recruitment" request) true)
          (core:add_listener :everchosen_vassal_recruitment_vassal_added
            :PositiveDiplomaticEvent #($1:is_vassalage)
            (world.guarded "Everchosen vassal recruitment" request) true)
          (core:add_listener :everchosen_vassal_recruitment_vassal_removed
            :NegativeDiplomaticEvent #($1:was_vassalage)
            (world.guarded "Everchosen vassal recruitment" request) true)
          (core:add_listener :everchosen_vassal_recruitment_turn
            :FactionTurnStart #(world.host? ($1:faction))
            safely-sync true)
          (safely-sync))
        (restrict-unsupported))))

{: start}
