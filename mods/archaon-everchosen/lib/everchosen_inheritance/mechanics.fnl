(local data (include :everchosen_inheritance.data))
(local rules (include :everchosen_inheritance.rules))
(local world (include :everchosen_inheritance.world))
(local plagues (include :everchosen_inheritance.plagues))

;; Native function adapters are installed once, without replacing CA scripts.
(var native-has-manifestations nil)
(var native-unlock-manifestations nil)

(local ascendant-key (.. data.prefix "ascendant"))
(local rewarded-key (.. data.prefix "battle_rewarded"))

(fn unlocked? [god]
  (= true (cm:get_saved_value (rules.state-key god))))

(fn ritual-data []
  (assert (core:get_static_object :everchosen_inheritance_data)
          "Inherited ritual data unavailable"))

(fn sync-income [faction]
  (if (unlocked? :nur)
      (when (faction:has_effect_bundle data.income-lock)
        (cm:remove_effect_bundle data.income-lock data.host))
      (when (not (faction:has_effect_bundle data.income-lock))
        (cm:apply_effect_bundle data.income-lock data.host 0))))

(fn sync-manifestations [faction]
  (let [ascendant (cm:get_saved_value :great_game_ascendant_god)]
    (each [index culture (ipairs data.cultures)]
      (let [key (rules.manifestation-key index)
            upgraded? (= ascendant culture)]
        (cm:unlock_ritual faction
                          (.. key (if upgraded? "_upgraded" "")))
        (cm:lock_ritual faction
                        (.. key (if upgraded? "" "_upgraded")))))))

(fn has-manifestations [faction]
  (if (world.host? faction) (unlocked? :gg)
      (native-has-manifestations faction)))

(fn unlock-manifestations [level faction upgraded?]
  (if (world.host? faction)
      (when (unlocked? :gg) (sync-manifestations faction))
      (native-unlock-manifestations level faction upgraded?)))

(fn install []
  (plagues.install)
  (when (not native-has-manifestations)
    ;; CA's campaign functions belong to its script environment, not _G.
    (let [environment (core:get_env)
          has-rituals environment.faction_has_great_game_rituals
          unlock-rituals environment.unlock_gg_rituals]
      (assert (and (= (type has-rituals) :function)
                   (= (type unlock-rituals) :function))
              "Native manifestation functions unavailable")
      (set native-has-manifestations has-rituals)
      (set native-unlock-manifestations unlock-rituals)
      (set environment.faction_has_great_game_rituals has-manifestations)
      (set environment.unlock_gg_rituals unlock-manifestations))))

(fn apply [faction god]
  "First acquisition only. Never run this as a save/load restore routine."
  (let [features (. data.features god)]
    (when features
      (cm:add_or_remove_faction_features faction features true)))
  (when (= god :nur) (plagues.unlock faction))
  (when (and (= god :tze) (not (faction:has_effect_bundle data.tze-bundle)))
    (cm:apply_effect_bundle data.tze-bundle data.host 0))
  (if (= god :gg)
      (do
        (each [index _ (ipairs data.cultures)]
          (cm:unlock_ritual faction
                            (.. (rules.manifestation-key index) "_uses")))
        (sync-manifestations faction))
      (each [_ ritual (ipairs (or (. (ritual-data) god) []))]
        (cm:unlock_ritual faction ritual))))

(fn refresh-ui []
  (when (world.host)
    (each [_ god (ipairs data.gods)]
      (common.set_context_value (.. data.prefix "ui_" god)
                                (if (unlocked? god) 1 0)))
    ;; Native HUD layout can show DB-enabled controls before the context gate
    ;; updates. Touch only our five controls, leaving native button states alone.
    (let [root (core:get_ui_root)]
      (when root
        (each [id god (pairs data.ui-controls)]
          (let [component (find_uicomponent root id)]
            (when component (component:SetVisible (unlocked? god)))))))))

(fn refresh-ui-after-layout []
  (refresh-ui)
  (cm:callback refresh-ui 0.2))

(fn ascendant-god []
  (or (cm:get_saved_value :great_game_ascendant_god) false))

(fn record-ascendant []
  "Remember which god the manifestation rituals were last synced for."
  (cm:set_saved_value ascendant-key (ascendant-god)))

(fn ascendance []
  (let [faction (world.host)
        ascendant (ascendant-god)]
    ;; Repeated events and ordinary loads do not reopen ritual locks.
    (when (and faction (unlocked? :gg)
               (not= ascendant (cm:get_saved_value ascendant-key)))
      (sync-manifestations faction)
      (cm:set_saved_value ascendant-key ascendant))))

(fn defeated-culture? [culture]
  (cm:pending_battle_cache_faction_won_battle_against_culture
    data.host culture))

(fn reward-battle []
  (when (and (world.host) (unlocked? :gg)
             (not (cm:get_saved_value rewarded-key))
             (cm:pending_battle_cache_faction_won_battle data.host))
    (let [index (accumulate [found nil i culture (ipairs data.cultures)
                            &until found]
                  (if (defeated-culture? culture) i))]
      (when index
        (cm:faction_add_pooled_resource
          data.host (.. (rules.manifestation-key index) "_uses") :other 1)
        (cm:set_saved_value rewarded-key true)))))

(fn begin-battle []
  ;; This persisted guard survives the battle's campaign-script reload.
  (cm:set_saved_value rewarded-key false))

{: unlocked? : apply : install : refresh-ui : refresh-ui-after-layout
 : sync-income : record-ascendant
 : ascendance : reward-battle : begin-battle}
