(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local model (include :everchosen_hero_capacity.world))
(local rules (include :everchosen_hero_capacity.rules))
(local data (include :everchosen_hero_capacity.data))

;; Derived capacity state is rebuilt from owned heroes and active sources.
(var config nil)
(var current-plan nil)
;; Coalesce deferred ownership/building notifications and invalidate old reads.
(var pending? false)
(var working? false)
(var generation 0)

(fn run [callback ...]
  (let [(ok? error) (pcall callback ...)]
    (when (not ok?)
      (set current-plan nil)
      (set pending? false)
      (set working? false)
      (set generation (+ generation 1))
      (when config (cm:remove_effect_bundle config.bundle scope.host))
      (core:trigger_custom_event data.failed {})
      (out (.. "[Everchosen hero capacity] " (tostring error))))))

(fn apply-values [host effects]
  (let [bundle (cm:create_new_custom_effect_bundle config.bundle)]
    (each [effect value (pairs effects)]
      (bundle:add_effect effect :faction_to_faction_own_unseen value))
    (bundle:set_duration 0)
    (cm:apply_custom_effect_bundle_to_faction bundle host)))

(fn snapshot [subtypes]
  (when (and current-plan (world.host))
    (rules.snapshot config current-plan.families subtypes)))

(fn ready []
  (and current-plan (not pending?) (not working?)))

(fn verify [ticket plan]
  (when (= ticket generation)
    (let [host (world.host)]
      (when host
        (each [agent target (pairs plan.class-targets)]
          (let [actual (host:agent_cap agent)]
            (assert (or (= actual target)
                        (and (>= actual 4294967295)
                             (>= target 4294967295)))
                    (.. "Native hero capacity did not reach target: " agent
                        " target=" target " actual=" actual))))
        (set current-plan plan)
        (set working? false)
        (core:trigger_custom_event data.ready {})))))

(fn calculate [ticket]
  (when (= ticket generation)
    (let [host (world.host)]
      (when host
        (let [plan (rules.plan config (model.subtype-bonuses host config)
                               (model.extras host config) (model.counts host)
                               (model.class-caps host config))]
          (apply-values host plan.effects)
          (cm:callback #(run verify ticket plan) 0.1))))))

(fn refresh []
  (set pending? false)
  (when (world.host)
    (set generation (+ generation 1))
    (set working? true)
    (set current-plan nil)
    ;; Mask recruitment before removing our contribution. Reading a clamped
    ;; total minus a negative contribution cannot recover the native baseline.
    (core:trigger_custom_event data.updating {})
    (cm:remove_effect_bundle config.bundle scope.host)
    (let [ticket generation]
      (cm:callback #(run calculate ticket) 0.1))))

(fn request []
  (when (not pending?)
    (set pending? true)
    (set generation (+ generation 1))
    (core:trigger_custom_event data.updating {})
    (let [ticket generation]
      (cm:callback #(when (= ticket generation) (run refresh)) 0.1))))

(fn tracked? [character]
  (and (world.valid? character)
       (. config.counted_subtypes (character:character_subtype_key))))

(fn promotion-finished []
  ;; Native promotion deletes the previous hero 0.5 seconds after this event.
  ;; request adds its own delay, so it observes the final faction list.
  (cm:callback request 0.5))

(fn tracked-character? [context] (tracked? (context:character)))

(fn related-character? [context]
  (let [character (context:character)]
    (and (world.valid? character)
         (or (tracked? character) (world.host? (character:faction))))))

(fn tracked-destruction? [context]
  (let [member (context:family_member)]
    (and (world.valid? member) (tracked? (member:character_details)))))

(fn listen [event condition callback]
  (core:add_listener (.. "everchosen_hero_capacity_" event) event condition
    #(run callback $1) true))

(fn start []
  (when (world.host)
    (let [controller (core:get_static_object data.controller)]
      (if controller (controller.request)
          (do
            (set config (assert (core:get_static_object data.config)))
            (core:add_static_object data.controller {: request})
            (core:add_static_object data.provider
              {: snapshot : ready :pending #(or pending? working?)
               :request #(run request)})
            (listen :CharacterRecruited tracked-character? refresh)
            (each [_ event (ipairs [:CharacterConvalescedOrKilled
                                    :CharacterFactionChangeEvent
                                    :CharacterSkillPointAllocated])]
              (listen event related-character? request))
            (listen :CharacterDestroyed tracked-destruction? request)
            (listen :ScriptEventCharacterUpgraded true promotion-finished)
            (listen :FactionTurnStart #(world.host? ($1:faction)) request)
            (listen :PanelOpenedCampaign
                    #(= $1.string :character_panel) request)
            ;; Re-query current ownership after native asynchronous commands.
            (each [_ event (ipairs [:FactionJoinsConfederation
                                    :BuildingCompleted
                                    :MilitaryForceBuildingCompleteEvent
                                    :ForeignSlotBuildingCompleteEvent
                                    :ResearchCompleted
                                    :RegionFactionChangeEvent])]
              (listen event true request))
            (refresh))))))

{:start #(run start)}
