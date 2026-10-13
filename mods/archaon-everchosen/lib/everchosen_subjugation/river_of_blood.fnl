(local world (include :everchosen_core.world))

;; Retain the native dispatcher once per Lua session, never in campaign saves.
(var original nil)

(fn completed [context]
  (let [character (context:character)
        config (. (world.static-data) :subjugation :river_of_blood)
        environment (core:get_env)]
    (if (and (world.host? (character:faction))
             (= (character:character_subtype_key) config.subtype))
        (when (character:won_battle)
          ;; Native 9.0.3 keeps stacking, cap and duration in this helper.
          ;; The full handler also writes the original faction's rampage pool.
          (environment.TauroxRampage_UpdateRiverOfBlood (character:region)
            (character:has_skill config.skill)))
        (original context))))

(fn start []
  (when (and (not original) (world.host))
    (let [environment (core:get_env)]
      (set original environment.TauroxRampage_BattleCompleted)
      ;; Both native listeners resolve this in the campaign environment.
      (set environment.TauroxRampage_BattleCompleted completed))))

{: start}
