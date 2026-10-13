(local world (include :everchosen_core.world))

;; Retain the native dispatcher once per Lua session, never in campaign saves.
(var original nil)

(fn completed [context]
  (let [character (context:character)
        config (. (world.static-data) :subjugation :river_of_blood)]
    (if (and (world.valid? character) (world.host? (character:faction))
             (= (character:character_subtype_key) config.subtype))
        (when (character:won_battle)
          ;; Native 9.0.3 keeps stacking, cap and duration in this helper.
          ;; The full handler also writes the original faction's rampage pool.
          (_G.TauroxRampage_UpdateRiverOfBlood (character:region)
            (or (character:has_skill config.skill)
                (character:has_skill _G.RiverOfBlood.skill_key))))
        (original context))))

(fn start []
  (when (and (not original) (world.host))
    (if (and (= (type _G.TauroxRampage_BattleCompleted) :function)
             (= (type _G.TauroxRampage_UpdateRiverOfBlood) :function)
             (= (type _G.RiverOfBlood) :table))
        (do
          (set original _G.TauroxRampage_BattleCompleted)
          ;; Both native battle listeners resolve this global when called.
          (set _G.TauroxRampage_BattleCompleted completed))
        (out "[Everchosen] Native River of Blood handler unavailable"))))

{: start}
