(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local model (include :everchosen_hero_capacity.world))
(local rules (include :everchosen_hero_capacity.rules))

(local config-key :everchosen_hero_capacity_data)
(local saved-key :everchosen_hero_capacity_state)
(local controller-key :everchosen_hero_capacity_controller)
(local provider-key :everchosen_hero_family_capacity)

;; These values describe this campaign's currently applied execution bundle.
(var config nil)
(var normalizers nil)
(var applied {})
(var last-uplifts {})
(var current-plan nil)
(var published? false)
;; Coalesce deferred ownership/building notifications and invalidate old reads.
(var pending? false)
(var measuring? false)
(var generation 0)

(fn run [callback ...]
  (let [(ok? error) (pcall callback ...)]
    (when (not ok?)
      (set current-plan nil)
      (set normalizers nil)
      (set applied {})
      (set last-uplifts {})
      (set pending? false)
      (set measuring? false)
      (set generation (+ generation 1))
      (when config
        (cm:remove_effect_bundle config.bundle scope.host)
        (cm:set_saved_value saved-key nil))
      (out (.. "[Everchosen hero capacity] " (tostring error))))))

(fn apply-values [host effects]
  (let [bundle (cm:create_new_custom_effect_bundle config.bundle)]
    (each [effect value (pairs effects)]
      (bundle:add_effect effect :faction_to_faction_own_unseen value))
    (bundle:set_duration 0)
    (cm:remove_effect_bundle config.bundle (host:name))
    (cm:apply_custom_effect_bundle_to_faction bundle host)
    (set applied effects)))

(fn snapshot [subtypes]
  (when (and current-plan (world.host))
    (rules.snapshot config current-plan.families subtypes)))

(fn verify [ticket plan]
  (when (= ticket generation)
    (let [host (world.host)]
      (when host
        (let [actual (model.subtype-caps host config)]
          (each [subtype target (pairs plan.targets)]
            (assert (= (. actual subtype) target)
                    (.. "Hero capacity did not reach target: " subtype
                        " target=" target " actual=" (. actual subtype)))))
        (each [agent _ (pairs config.classes)]
          (assert (>= (host:agent_cap agent)
                      (. plan.class-targets agent))
                  (.. "Native hero class still restricts families: " agent)))
        (set current-plan plan)
        (when (not published?)
          (core:add_static_object provider-key
            {: snapshot :ready #(not (not current-plan))})
          (set published? true))))))

(fn refresh []
  (set pending? false)
  (let [host (world.host)]
    (when (and host normalizers)
      (let [present? (host:has_effect_bundle config.bundle)
            bonuses (model.subtype-bonuses host config)
            sources (collect [subtype record (pairs config.subtypes)]
                      (values subtype
                        (- (. bonuses subtype)
                           (if present? (or (. applied record.effect) 0) 0))))
            class-caps (model.class-caps host config)
            plan (rules.plan config sources (model.extras host config)
                             (model.counts host) normalizers
                             class-caps
                             (if present? last-uplifts {}))]
        (set plan.class-targets
          (collect [agent cap (pairs class-caps)]
            (values agent
              (if (= cap 4294967295) cap
                  (+ (- cap (if present?
                                (or (. last-uplifts agent) 0) 0))
                     (. plan.class-uplifts agent))))))
        (set generation (+ generation 1))
        (set current-plan nil)
        (apply-values host plan.effects)
        (set last-uplifts plan.class-uplifts)
        ;; Save the applied values immediately, including saves before verify.
        (cm:set_saved_value saved-key
          {: normalizers : applied :uplifts last-uplifts})
        (let [ticket generation]
          (cm:callback #(run verify ticket plan) 0.1))))))

(fn measure-second [first first-bonuses]
  (let [host (world.host)]
    (when host
      (let [second (model.subtype-caps host config)
            second-bonuses (model.subtype-bonuses host config)]
        (each [subtype value (pairs first)]
          (assert (and (< (. second subtype) 4294967295)
                       (= (. second subtype) (+ value 1))
                       (= (. second-bonuses subtype)
                          (+ (. first-bonuses subtype) 1)))
                  (.. "Unsupported native subtype capacity: " subtype)))
        ;; Keep only the native base offset, never a building's current bonus.
        (set normalizers
          (collect [subtype value (pairs first)]
            (values subtype (- (. first-bonuses subtype) value))))
        (set measuring? false)
        (refresh)))))

(fn measure-first []
  (let [host (world.host)]
    (when host
      (let [first (model.subtype-caps host config)
            bonuses (model.subtype-bonuses host config)]
        (apply-values host
          (collect [_ record (pairs config.subtypes)]
            (values record.effect 2)))
        (cm:callback #(run measure-second first bonuses) 0.1)))))

(fn measure []
  (set pending? false)
  (set measuring? true)
  (let [host (world.host)]
    (when host
      (apply-values host
        (collect [_ record (pairs config.subtypes)]
          (values record.effect 1)))
      (cm:callback #(run measure-first) 0.1))))

(fn request []
  (when (and (not measuring?) (not pending?))
    (set pending? true)
    (set generation (+ generation 1))
    ;; A failed probe can retry on the next relevant event, never in a loop.
    (cm:callback #(run (if normalizers refresh measure)) 0.1)))

(fn tracked? [character]
  (and (world.valid? character)
       (. config.counted_subtypes (character:character_subtype_key))))

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
    (let [controller (core:get_static_object controller-key)]
      (if controller (controller.request)
          (let [saved (cm:get_saved_value saved-key)]
            (set config (assert (core:get_static_object config-key)))
            (core:add_static_object controller-key {: request})
            (listen :CharacterRecruited tracked-character? refresh)
            (each [_ event (ipairs [:CharacterConvalescedOrKilled
                                    :CharacterFactionChangeEvent
                                    :CharacterSkillPointAllocated])]
              (listen event related-character? request))
            (listen :CharacterDestroyed tracked-destruction? request)
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
            (if saved
                (do
                  (set normalizers saved.normalizers)
                  (set applied saved.applied)
                  (set last-uplifts saved.uplifts)
                  (request))
                (measure)))))))

{:start #(run start)}
