(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local settings (include :everchosen_chieftains.settings))
(local world (include :everchosen_chieftains.world))

(fn start []
  (local faction (cm:get_faction data.faction))
  (when (world.valid faction)
    (var config (settings.read))
    (var queued false)
    (var pending nil)
    (var reconcile nil)

    (fn log [message] (out (.. "[" data.mod-key "] " message)))

    (fn request []
      (when (not queued)
        (set queued true)
        ;; Native ownership transfers can finish after the triggering event.
        (cm:callback (fn [] (set queued false) (reconcile)) 0.2)))

    (fn finish [character ticket]
      (when (and (= pending ticket) (world.valid character)
                 (= (: (character:faction) :name) data.faction)
                 (= (character:character_subtype_key) ticket.subtype))
        ;; Keep the guard while initialization itself raises rank-up events.
        (local (ok err)
          (pcall
            (fn []
              (local hero (. rules.by-subtype ticket.subtype))
              (local lookup (cm:char_lookup_str (character:command_queue_index)))
              (cm:force_add_ancillary character hero.ancillary true true)
              (when hero.extra (cm:force_add_ancillary character hero.extra true true))
              (cm:force_add_trait lookup hero.trait 1)
              (cm:add_agent_experience lookup ticket.rank true))))
        (set pending nil)
        (if ok (request)
            (log (.. "Chieftain initialization failed: " (tostring err))))))

    (fn confirm [ticket]
      (when (= pending ticket)
        (local owner (cm:get_faction data.faction))
        (local character (and (world.valid owner)
                              (. (world.owned owner) ticket.subtype)))
        (if character (finish character ticket)
            (do
              ;; Preserve correlation with late spawn events until the next turn.
              (tset ticket :unconfirmed true)
              (log (.. "Spawn not confirmed: " ticket.subtype))))))

    (fn spawn [owner characters subtype location]
      (local ticket {: subtype :rank (math.min 7 (: (. characters data.tamurkhan) :rank))})
      (set pending ticket)
      (local (ok err)
        (pcall
          (fn []
            (if location.character
                (cm:spawn_unique_agent_at_character
                  (owner:command_queue_index) subtype
                  (: location.character :command_queue_index) true)
                (cm:spawn_unique_agent_at_region
                  (owner:command_queue_index) subtype (: location.region :cqi) true)))))
      (when (not ok) (log (.. "Spawn command failed: " (tostring err))))
      ;; The command has no success return; only the event/world confirms ownership.
      (cm:callback (fn [] (confirm ticket)) 5))

    (set reconcile
      (fn []
        (when (not pending)
          (local owner (cm:get_faction data.faction))
          (when (world.valid owner)
            (local characters (world.owned owner))
            (local tamurkhan (. characters data.tamurkhan))
            (when tamurkhan
              (local subtype (rules.next-missing (tamurkhan:rank) config characters))
              ;; Do not clone a unique hero owned by another faction.
              (when (and subtype (not (world.held-elsewhere? subtype)))
                (local location (world.spawn-location owner characters))
                (when location (spawn owner characters subtype location))))))))

    (fn listen [suffix event condition callback]
      (core:add_listener (.. data.mod-key "_" suffix) event condition callback true))

    (listen :spawn :UniqueAgentSpawned
      (fn [context]
        (local character (: (context:unique_agent_details) :character))
        (and pending (world.valid character)
             (= (: (character:faction) :name) data.faction)
             (= (character:character_subtype_key) pending.subtype)))
      (fn [context] (finish (: (context:unique_agent_details) :character) pending)))

    (listen :rank :CharacterRankUp
      (fn [context]
        (local character (context:character))
        (and (world.valid character)
             (= (: (character:faction) :name) data.faction)
             (= (character:character_subtype_key) data.tamurkhan)))
      request)

    (listen :turn :FactionTurnStart
      (fn [context] (= (: (context:faction) :name) data.faction))
      (fn []
        (when (and pending pending.unconfirmed)
          (local ticket pending)
          (confirm ticket)
          (when (= pending ticket) (set pending nil)))
        (request)))

    (each [_ event (ipairs [:MctInitialized :MctFinalized])]
      (listen event event true (fn [] (set config (settings.read)) (request))))

    (listen :subjugation :ScriptEventArchaonSubjugatesChaosFaction true request)
    (request)))

{: start}
