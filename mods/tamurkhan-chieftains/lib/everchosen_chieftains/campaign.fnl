;;; Game-event adapter: create and initialize one missing hero at a time.

(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local settings (include :everchosen_chieftains.settings))
(local world (include :everchosen_chieftains.world))
(local ticket-key (.. data.mod-key "_active_ticket"))

;; Configuration can change when MCT finalizes its settings.
(var config nil)
;; The saved intent survives ordinary loads of this version's campaigns.
(var pending nil)
;; Runtime guards coalesce events and allow a command's result to settle.
(var queued? false)
(var waiting? false)

;; Forward declaration: a confirmed result requests the next reconcile.
(var request nil)

(fn log [message]
  (out (.. "[" data.mod-key "] " message)))

(fn keep-ticket [ticket]
  (set pending ticket)
  ;; Native 9.0.3 campaign_manager saves primitive tables automatically.
  (cm:set_saved_value ticket-key (or ticket false)))

(fn host-faction []
  (let [faction (cm:get_faction data.faction)]
    (if (world.valid? faction) faction)))

(fn issue-init [character action]
  (let [lookup (cm:char_lookup_str (character:command_queue_index))]
    (if (= action.kind :ancillary)
        (cm:force_add_ancillary character action.key true true)
        (= action.kind :trait)
        (cm:force_add_trait lookup action.key true 1)
        ;; Native 9.0.3 wraps level_up_agent_rank: this is a level increment.
        (cm:add_agent_experience lookup action.amount true))))

(fn verify-init [ticket]
  (when (= pending ticket)
    (set waiting? false)
    (request)))

(fn initialize [character ticket]
  (let [hero (. rules.by-subtype ticket.subtype)
        action (world.next-init-action character hero ticket.rank)
        attempt ticket.attempt
        turn (cm:turn_number)]
    (if (not action)
        (do (keep-ticket nil) (request))
        (or (and (= action.kind :experience) ticket.rank-issued?)
            (and attempt (= attempt.kind action.kind)
                 (= attempt.key action.key) (= attempt.turn turn)))
        (log (.. "Initialization awaiting observed " action.kind
                 " result: " ticket.subtype))
        (do
          ;; Persist before issuing any command. Retry missing equipment or
          ;; traits at most once per turn, including across save/load.
          (set ticket.attempt {:kind action.kind :key action.key : turn})
          ;; Level increments cannot be safely retried after an uncertain
          ;; result, even if a command threw or the campaign was reloaded.
          (when (= action.kind :experience)
            (set ticket.rank-issued? true))
          (keep-ticket ticket)
          (set waiting? true)
          (let [(ok? err) (pcall issue-init character action)]
            (when (not ok?)
              (log (.. "Initialization command failed: " (tostring err)))))
          (cm:callback #(verify-init ticket) 1)))))

(fn finish [character ticket]
  (when (and (= pending ticket) (= ticket.phase :spawning)
             (world.ours? character ticket.subtype))
    (set ticket.phase :initializing)
    ;; Initialization belongs to this character, not a later same-subtype
    ;; transfer or replacement. Always re-query ownership before commands.
    (set ticket.character-cqi (character:command_queue_index))
    (keep-ticket ticket)
    (request)))

(fn issue-spawn [owner subtype location]
  (let [owner-cqi (owner:command_queue_index)]
    (if location.character
        (cm:spawn_unique_agent_at_character
          owner-cqi subtype (location.character:command_queue_index) true)
        (cm:spawn_unique_agent_at_region
          owner-cqi subtype (location.region:cqi) true))))

(fn confirm-spawn [ticket]
  (when (and (= pending ticket) (= ticket.phase :spawning))
    (request)))

(fn spawn [owner ticket characters]
  (let [turn (cm:turn_number)
        ;; Restoring an intent must not bypass the host ownership rule.
        location (and (. characters data.tamurkhan)
                      (not= ticket.spawn-turn turn)
                      (world.spawn-location owner characters))]
    (when location
      (set ticket.spawn-turn turn)
      (keep-ticket ticket)
      (let [(ok? err) (pcall issue-spawn owner ticket.subtype location)]
        (when (not ok?)
          (log (.. "Spawn command failed: " (tostring err)))))
      ;; A command's return is not proof of ownership. Keep the saved intent
      ;; for late events, loads, or a retry on a later host turn.
      (cm:callback #(confirm-spawn ticket) 5))))

(fn reconcile-ticket [owner characters ticket]
  (let [character (. characters ticket.subtype)]
    (if (= ticket.phase :spawning)
        (if character
            (finish character ticket)
            (spawn owner ticket characters))
        (when (and character (not waiting?)
                   (= (character:command_queue_index) ticket.character-cqi))
          (initialize character ticket)))))

(fn reconcile []
  (let [owner (host-faction)
        characters (and owner (world.owned owner))
        tamurkhan (and characters (. characters data.tamurkhan))]
    (when owner
      (if pending
          (reconcile-ticket owner characters pending)
          (when tamurkhan
            (let [rank (tamurkhan:rank)
                  subtype (rules.next-missing rank config characters)]
              (when subtype
                (let [ticket {: subtype :phase :spawning
                              :rank (math.min data.spawn-rank-cap rank)}]
                  (keep-ticket ticket)
                  (spawn owner ticket characters)))))))))

(set request
     (fn []
       (when (not queued?)
         (set queued? true)
         ;; Native transfers and spawn events can precede settled ownership.
         (cm:callback (fn []
                        (set queued? false)
                        (reconcile))
                      0.2))))

(fn reload-config []
  (set config (settings.read))
  (request))

(fn listen [suffix event condition callback]
  (core:add_listener (.. data.mod-key "_" suffix) event condition
    (world.guarded data.mod-key callback) true))

(fn start []
  (when (host-faction)
    (set config (settings.read))
    (set pending (or (cm:get_saved_value ticket-key) nil))
    (listen :spawn :UniqueAgentSpawned
            (fn [context]
              (let [details (context:unique_agent_details)]
                (and pending (= pending.phase :spawning)
                     (world.ours? (details:character) pending.subtype))))
            (fn [context]
              (let [details (context:unique_agent_details)]
                (finish (details:character) pending))))
    (listen :rank :CharacterRankUp
            (fn [context]
              (let [character (context:character)]
                (or (world.ours? character data.tamurkhan)
                    (and pending
                         (world.ours? character pending.subtype)))))
            #(request))
    (listen :turn :FactionTurnStart
            #(= (: ($1:faction) :name) data.faction)
            #(request))
    (each [_ event (ipairs [:MctInitialized :MctFinalized])]
      (listen event event true reload-config))
    (listen :subjugation :ScriptEventArchaonSubjugatesChaosFaction true
            #(request))
    (request)))

{: start}
