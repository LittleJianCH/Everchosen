(local data (include :everchosen_inheritance.data))
(local rules (include :everchosen_inheritance.rules))
(local world (include :everchosen_inheritance.world))
(local mechanics (include :everchosen_inheritance.mechanics))
(local blessings (include :everchosen_inheritance.blessings))
(local portals (include :everchosen_inheritance.portals))

(local pending-key (.. data.prefix "pending_confederations"))

;; Guards listener registration within this script session.
(var started? false)

(fn log [message]
  (out (.. "[Everchosen inheritance] " message)))

(fn unlock [source]
  (let [faction (world.host)
        god (and (world.valid? source)
                 (rules.classify (source:name) (source:subculture)))]
    (when (and faction god (not (mechanics.unlocked? god)))
      (let [(ok? err) (pcall mechanics.apply faction god)]
        (if ok?
            (do
              (cm:set_saved_value (rules.state-key god) true)
              (when (= god :gg)
                (mechanics.record-ascendant))
              (mechanics.sync-income faction)
              (mechanics.refresh-ui-after-layout)
              (log (.. "Unlocked " god " from " (source:name))))
            (log (.. "Setup failed for " god ": " (tostring err))))))))

(fn check-lords []
  (let [faction (world.host)
        environment (core:get_env)
        config environment.archaon_subjugation_config]
    (when (and faction config)
      (let [owned (world.owned faction)]
        (each [source entry (pairs config.faction_key_to_leader_subtype_list)]
          (when (. owned entry.subtype_key)
            (unlock (cm:get_faction source))))))))

(fn check-confederations []
  (let [pending (or (cm:get_saved_value pending-key) {})]
    (each [source _ (pairs pending)]
      (let [faction (cm:get_faction source)]
        (when (and (world.valid? faction)
                   (faction:was_confederated_by_faction (world.host)))
          (unlock faction))))
    ;; Retain only requests whose corresponding mechanic is not yet acquired.
    (cm:set_saved_value pending-key
      (collect [source _ (pairs pending)]
        (let [faction (cm:get_faction source)
              god (and (world.valid? faction)
                       (rules.classify (faction:name) (faction:subculture)))]
          (when (and god (not (mechanics.unlocked? god)))
            (values source true)))))))

(fn reconcile []
  (when (world.host)
    (check-confederations)
    (check-lords)
    (mechanics.sync-income (world.host))
    (mechanics.refresh-ui)
    (blessings.sync)))

(fn request []
  ;; Native transfer callbacks can finish after the notification is emitted.
  (cm:callback reconcile 0.2)
  (cm:callback reconcile 1))

(fn on-confederation [context]
  (let [source (context:faction)
        god (rules.classify (source:name) (source:subculture))]
    (when god
      (let [pending (or (cm:get_saved_value pending-key) {})]
        (tset pending (source:name) true)
        (cm:set_saved_value pending-key pending)
        (request)))))

(fn listen [suffix event condition callback]
  (core:add_listener (.. data.prefix suffix) event condition callback true))

(fn relevant-diplomacy? [context]
  (or (blessings.relevant? (context:proposer))
      (blessings.relevant? (context:recipient))))

(fn vassalage-established? [context]
  (and (context:is_vassalage) (relevant-diplomacy? context)))

(fn vassalage-broken? [context]
  (and (context:was_vassalage) (relevant-diplomacy? context)))

(fn status []
  (collect [_ god (ipairs data.gods)]
    god (mechanics.unlocked? god)))

(fn prepare []
  ;; CA initializes its managers on first tick. Register adapters before that
  ;; so a locked Archaon is never treated as a native manifestation owner.
  (when (world.host) (mechanics.install)))

(fn start []
  (when (and (not started?) (world.host))
    (mechanics.install)
    (set started? true)
    (listen :confederation :FactionJoinsConfederation
            #(world.host? ($1:confederation)) on-confederation)
    (listen :subjugation :ScriptEventArchaonSubjugatesChaosFaction true
            request)
    (listen :turn :FactionTurnStart #(blessings.relevant? ($1:faction))
            reconcile)
    (listen :vassal_added :PositiveDiplomaticEvent
            vassalage-established? request)
    (listen :vassal_removed :NegativeDiplomaticEvent
            vassalage-broken? request)
    (listen :ui :PanelClosedCampaign true mechanics.refresh-ui-after-layout)
    (listen :ui_open :PanelOpenedCampaign true
            mechanics.refresh-ui-after-layout)
    (listen :ascendance :ScriptEventNewGodAscendant true mechanics.ascendance)
    (listen :battle_start :PendingBattle true mechanics.begin-battle)
    (listen :battle_end :BattleCompleted true mechanics.reward-battle)
    (core:add_static_object :everchosen_inheritance {: status})
    (portals.start)
    (reconcile)
    ;; The HUD may not exist until the first layout after campaign startup.
    (cm:callback mechanics.refresh-ui 0.5)))

{: prepare : start}
