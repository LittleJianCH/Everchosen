(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local rules (include :everchosen_hero_capacity_test.rules))

(local config-key :everchosen_hero_capacity_test_families)
(local provider-key :everchosen_hero_family_capacity)
(local saved-key :everchosen_hero_capacity_test_family_measurement)

;; Measurement and deferred effect checks belong to this running session.
(var config nil)
(var offsets nil)
(var enabled? false)
(var pending? false)
(var generation 0)

(fn log [message]
  (out (.. "[Everchosen hero family test] " message)))

(fn counts [host]
  ;; Wounded heroes stay in the faction list and continue using their slot.
  (accumulate [result {} character (world.items (host:character_list))]
    (do
      (when (world.valid? character)
        (let [subtype (character:character_subtype_key)]
          (when (and (. config.subtypes subtype)
                     (world.host? (character:faction)))
            (tset result subtype (+ 1 (or (. result subtype) 0))))))
      result)))

(fn read-caps [host]
  (collect [subtype _ (pairs config.subtypes)]
    (values subtype (host:agent_subtype_cap subtype))))

(fn apply-values [host effect-values]
  (let [bundle (cm:create_new_custom_effect_bundle config.bundle)]
    (each [subtype value (pairs effect-values)]
      (bundle:add_effect (. config.subtypes subtype :effect)
                         :faction_to_faction_own_unseen value))
    (bundle:set_duration 0)
    (cm:remove_effect_bundle config.bundle (host:name))
    (cm:apply_custom_effect_bundle_to_faction bundle host)))

(fn cleanup []
  (when config (cm:remove_effect_bundle config.bundle scope.host))
  (cm:set_saved_value saved-key {:status :unsupported}))

(fn stop [message]
  (set enabled? false)
  (set offsets nil)
  (set pending? false)
  (set generation (+ generation 1))
  (let [(cleaned? error) (pcall cleanup)]
    (when (not cleaned?)
      (log (.. "Cleanup failed: " (tostring error)))))
  (log message))

(fn run [callback ...]
  (let [(ok? error) (pcall callback ...)]
    (when (not ok?) (stop (tostring error)))))

(fn snapshot [subtypes]
  (when enabled?
    (let [host (world.host)]
      (when host (rules.snapshot config (counts host) subtypes)))))

(fn verify [ticket targets]
  (when (= ticket generation)
    (let [host (world.host)]
      (when host
        (let [actual (read-caps host)
              correct? (and (host:has_effect_bundle config.bundle)
                (accumulate [correct? true subtype target (pairs targets)]
                  (and correct? (= (. actual subtype) target))))]
          (each [subtype target (pairs targets)]
            (log (.. subtype ": target=" target
                     ", actual=" (. actual subtype))))
          (if correct?
              (when (not enabled?)
                (set enabled? true)
                (core:add_static_object provider-key {: snapshot})
                (cm:set_saved_value saved-key
                                    {:status :ready : offsets})
                (log "Independent family limits enabled."))
              (stop "Cap check failed; this experiment was disabled.")))))))

(fn refresh []
  (set pending? false)
  (let [host (world.host)]
    (when (and host offsets)
      (set generation (+ generation 1))
      (let [ticket generation
            targets (rules.targets config (counts host))
            effect-values (collect [subtype target (pairs targets)]
                            (values subtype (+ target (. offsets subtype))))]
        (apply-values host effect-values)
        (cm:callback #(run verify ticket targets) 0.1)))))

(fn safe-refresh [] (run refresh))

(fn request []
  (when (and enabled? (not pending?))
    ;; Several post-battle events can precede the final ownership update.
    (set pending? true)
    (set generation (+ generation 1))
    (cm:callback safe-refresh 0.1)))

(fn measure-second [first]
  (let [host (world.host)]
    (when host
      (let [second (read-caps host)]
        (each [subtype value (pairs second)]
          (log (.. subtype ": effect1=" (. first subtype)
                   ", effect2=" value)))
        (set offsets (rules.measured-offsets first second))
        (if offsets (refresh)
            (stop "Subtype cap effects did not respond linearly; disabled."))))))

(fn measure-first []
  (let [host (world.host)]
    (when host
      (let [first (read-caps host)]
        (apply-values host
          (collect [subtype _ (pairs config.subtypes)] (values subtype 2)))
        (cm:callback #(run measure-second first) 0.1)))))

(fn tracked? [character]
  (and (world.valid? character)
       (. config.subtypes (character:character_subtype_key))))

(fn tracked-character? [context] (tracked? (context:character)))

(fn tracked-destruction? [context]
  (let [member (context:family_member)]
    (and (world.valid? member) (tracked? (member:character_details)))))

(fn start []
  (let [host (world.host)
        saved (cm:get_saved_value saved-key)]
    (when (and host (or (cm:is_new_game) saved))
      (set config (assert (core:get_static_object config-key)))
      (when (or (cm:is_new_game) (not= saved.status :unsupported))
        (core:add_listener :everchosen_hero_family_recruited :CharacterRecruited
          tracked-character? #(when enabled? (safe-refresh)) true)
        (each [_ event (ipairs [:CharacterConvalescedOrKilled
                                :CharacterFactionChangeEvent])]
          (core:add_listener (.. "everchosen_hero_family_" event) event
                             tracked-character? request true))
        (core:add_listener :everchosen_hero_family_destroyed :CharacterDestroyed
                           tracked-destruction? request true)
        (core:add_listener :everchosen_hero_family_confederated
                           :FactionJoinsConfederation true request true)
        (core:add_listener :everchosen_hero_family_turn :FactionTurnStart
          #(world.host? ($1:faction)) request true)
        (core:add_listener :everchosen_hero_family_panel :PanelOpenedCampaign
          #(= $1.string :character_panel) request true)
        (if (and saved (= saved.status :ready))
            (do (set offsets saved.offsets) (refresh))
            (do
              (cm:set_saved_value saved-key {:status :measuring})
              (each [subtype cap (pairs (read-caps host))]
                (log (.. subtype ": record=" (. config.subtypes subtype :base)
                         ", baseline=" cap)))
              (apply-values host
                (collect [subtype _ (pairs config.subtypes)]
                  (values subtype 1)))
              (cm:callback #(run measure-first) 0.1)))))))

{:start #(run start)}
