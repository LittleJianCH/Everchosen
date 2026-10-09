;;; Game-event adapter: keeps the host faction's chieftains at the target
;;; count by spawning one missing hero at a time.

(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local settings (include :everchosen_chieftains.settings))
(local world (include :everchosen_chieftains.world))

(var config nil)
;; The spawn in flight, as {: subtype : rank}. Only one runs at a time; it is
;; an in-flight guard, not saved progression.
(var pending nil)
(var queued? false)

;; Forward declaration: a finished spawn requests the next reconcile.
(var request nil)

(fn log [message]
  (out (.. "[" data.mod-key "] " message)))

(fn host-faction []
  (let [faction (cm:get_faction data.faction)]
    (if (world.valid? faction) faction)))

(fn initialize [character ticket]
  (let [hero (. rules.by-subtype ticket.subtype)
        lookup (cm:char_lookup_str (character:command_queue_index))]
    (cm:force_add_ancillary character hero.ancillary true true)
    (when hero.extra
      (cm:force_add_ancillary character hero.extra true true))
    (cm:force_add_trait lookup hero.trait 1)
    (cm:add_agent_experience lookup ticket.rank true)))

(fn finish [character ticket]
  (when (and (= pending ticket) (world.ours? character ticket.subtype))
    ;; Keep the guard while initialization itself raises rank-up events.
    (let [(ok? err) (pcall initialize character ticket)]
      (set pending nil)
      (if ok?
          (request)
          (log (.. "Chieftain initialization failed: " (tostring err)))))))

(fn confirm [ticket]
  (when (= pending ticket)
    (let [owner (host-faction)
          character (and owner (. (world.owned owner) ticket.subtype))]
      (if character
          (finish character ticket)
          (do
            ;; Preserve correlation with late spawn events until the next turn.
            (set ticket.unconfirmed? true)
            (log (.. "Spawn not confirmed: " ticket.subtype)))))))

(fn issue-spawn [owner subtype location]
  (let [owner-cqi (owner:command_queue_index)]
    (if location.character
        (cm:spawn_unique_agent_at_character
          owner-cqi subtype (location.character:command_queue_index) true)
        (cm:spawn_unique_agent_at_region
          owner-cqi subtype (location.region:cqi) true))))

(fn spawn [owner subtype location rank]
  (let [ticket {: subtype :rank (math.min data.spawn-rank-cap rank)}]
    (set pending ticket)
    (let [(ok? err) (pcall issue-spawn owner subtype location)]
      (when (not ok?)
        (log (.. "Spawn command failed: " (tostring err)))))
    ;; The command has no success return; only the event/world confirms
    ;; ownership.
    (cm:callback #(confirm ticket) 5)))

(fn reconcile []
  (let [owner (and (not pending) (host-faction))
        characters (and owner (world.owned owner))
        tamurkhan (and characters (. characters data.tamurkhan))]
    (when tamurkhan
      (let [rank (tamurkhan:rank)
            subtype (rules.next-missing rank config characters)
            location (and subtype
                          (world.spawn-location owner characters))]
        (when location
          (spawn owner subtype location rank))))))

(set request
     (fn []
       (when (not queued?)
         (set queued? true)
         ;; Native ownership transfers can finish after the triggering event.
         (cm:callback (fn []
                        (set queued? false)
                        (reconcile))
                      0.2))))

(fn expire-unconfirmed []
  "Give an unconfirmed spawn one last check, then release the guard."
  (when (and pending pending.unconfirmed?)
    (let [ticket pending]
      (confirm ticket)
      (when (= pending ticket)
        (set pending nil)))))

(fn reload-config []
  (set config (settings.read))
  (request))

(fn listen [suffix event condition callback]
  (core:add_listener (.. data.mod-key "_" suffix) event condition callback
                     true))

(fn start []
  (when (host-faction)
    (set config (settings.read))
    (listen :spawn :UniqueAgentSpawned
            (fn [context]
              (let [details (context:unique_agent_details)]
                (and pending
                     (world.ours? (details:character) pending.subtype))))
            (fn [context]
              (let [details (context:unique_agent_details)]
                (finish (details:character) pending))))
    (listen :rank :CharacterRankUp
            #(world.ours? ($1:character) data.tamurkhan)
            #(request))
    (listen :turn :FactionTurnStart
            #(= (: ($1:faction) :name) data.faction)
            (fn []
              (expire-unconfirmed)
              (request)))
    (each [_ event (ipairs [:MctInitialized :MctFinalized])]
      (listen event event true reload-config))
    (listen :subjugation :ScriptEventArchaonSubjugatesChaosFaction true
            #(request))
    (request)))

{: start}
