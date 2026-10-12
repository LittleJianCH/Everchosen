;;; Native manager adapters, lord transfers and operation scheduling.

(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local skills (include :everchosen_subjugation.skills))
(local state (include :everchosen_subjugation.state))
(local clients (include :everchosen_subjugation.clients))

;; Native adapters and the command guard belong to this Lua session only.
(var originals nil)
(var busy? false)
;; A submitted skill phase schedules its own confirmation tick.
(var tick nil)

(fn log [message]
  (out (.. "[Everchosen subjugation] " message)))

(fn eligible? [source]
  (let [target (and (world.valid? source)
                    (. (state.targets) (source:name)))]
    (and (world.host) target (not (source:is_human))
         (= (source:culture) target.culture)
         (or (source:is_dead) target.keep_faction
             (clients.available-client? target.culture))
         (not (. (state.saved state.done-key) (source:name)))
         (not (. (world.owned (world.host)) target.subtype))
         (not (accumulate [protected? false _ key
                           (ipairs (cm:get_human_factions)) &until protected?]
                (source:is_vassal_of (cm:get_faction key)))))))

(fn members [source]
  "Snapshot family IDs before confederation mutates the character list."
  (let [culture (source:culture)
        subtypes (collect [_ target (pairs (state.targets))]
                   (when (= target.culture culture)
                     (values target.subtype true)))]
    (icollect [lord (world.items (source:character_list))]
      (when (and (world.valid? lord)
                 (. subtypes (lord:character_subtype_key))
                 (= (: (lord:faction) :name) (source:name)))
        (: (lord:family_member) :command_queue_index)))))

(fn transfer [operation pending]
  (each [_ id (ipairs operation.members)]
    (when (and (not (state.owned? id scope.host))
               (not= (. operation.transfers id) (cm:turn_number)))
      (let [lord (state.character id)]
        (let [expected (if (or operation.dead operation.keep_faction)
                           operation.source operation.client)
              owner (and (world.valid? lord) (lord:faction))]
          (assert (state.owned? id expected)
            (.. "Accepted lord ownership mismatch: family=" id
                ", expected=" expected ", actual="
                (if (world.valid? owner) (owner:name) "no character"))))
        (when (not (. operation.skills id))
          (tset operation.skills id
            (skills.capture lord
              (. (state.config) :skill_slots (lord:character_subtype_key)))))
        (tset operation.transfers id (cm:turn_number))
        (cm:set_saved_value state.pending-key pending)
        ;; As in CA's monogod path: acquire the lord, not his defeated army.
        (when (lord:is_alive)
          (cm:kill_character (cm:char_lookup_str (lord:cqi)) true))
        (let [current (state.character id)]
          (assert (world.valid? current) "Lord unavailable after convalescence")
          (cm:reassign_character (current:cqi)
                                 (: (world.host) :command_queue_index))
          (cm:stop_character_convalescing (: (state.character id) :cqi)))))))

(fn finish [source operation pending]
  (when (and
          (accumulate [all? true _ id (ipairs operation.members)
                       &until (not all?)]
            (state.owned? id scope.host))
          (accumulate [ready? true _ id (ipairs operation.members)]
            (let [plan (assert (. operation.skills id)
                               "Missing pre-transfer skill allocation")
                  before plan.stage
                  done? (skills.advance (state.character id) plan
                          #(cm:set_saved_value state.pending-key pending))]
              (when (and (not done?) (not= before plan.stage))
                (cm:callback tick 0.2))
              (and done? ready?))))
    (when operation.dead
      (assert (= (source:num_regions) 0)
              "Challenge source acquired territory; refuse faction cleanup")
      ;; Native battle cleanup may already have destroyed this empty faction.
      ;; Killing it again produces no FactionDeath to consume CA's suppression
      ;; flag, so the next real death would lose its challenge countdown.
      (when (not (source:is_dead))
        (let [persistent (. (state.native) :persistent)]
          (set persistent.suppress_faction_death_event true))
        (cm:kill_faction (source:name))))
    (let [done (state.saved state.done-key)
          challenges (state.saved state.challenge-key)]
      (tset done (source:name) true)
      (tset challenges (source:name) nil)
      (tset pending (source:name) nil)
      (cm:set_saved_value state.done-key done)
      (cm:set_saved_value state.challenge-key challenges)
      (cm:set_saved_value state.pending-key pending)
      (core:trigger_event :ScriptEventArchaonSubjugatesChaosFaction
                           (source:name))
      (log (.. "Confirmed lord transfer: " (source:name))))))

(fn advance [operation pending]
  (let [source (cm:get_faction operation.source)]
    (assert (world.valid? source) "Accepted source faction unavailable")
    (if (= operation.stage :transfer)
        (do (transfer operation pending) (finish source operation pending))
        operation.dead
        (do
          (when (source:is_dead)
            (assert (not= (: (state.native)
                             :resurrect_enemy_faction_legendary_lord
                             operation.source) -1)
                    "Could not recover the existing legendary lord"))
          (set operation.members (members source))
          (assert (> (length operation.members) 0)
                  "No accepted lord to transfer")
          (set operation.stage :transfer)
          (cm:set_saved_value state.pending-key pending)
          ;; A resurrected, landless faction can be cleaned up on the next tick.
          ;; Follow the native challenge flow and transfer in this same event.
          (transfer operation pending)
          (finish source operation pending))
        operation.keep_faction
        (when (clients.prepare-successor source operation pending)
          (cm:change_localised_faction_name operation.source
            (. (state.cultures) operation.culture :name))
          (set operation.stage :transfer)
          (cm:set_saved_value state.pending-key pending))
        (let [client (cm:get_faction operation.client)]
          (if (and (world.valid? client)
                   (source:was_confederated_by_faction client))
              (do
                (set operation.stage :transfer)
                (cm:set_saved_value state.pending-key pending))
              (do
                (assert (not (source:is_dead))
                        "Living source disappeared before client merger")
                (when (and (clients.prepare-client source operation pending)
                           (not= operation.merge-turn (cm:turn_number)))
                  ;; The receiving faction has its own leader before any LL
                  ;; leaves. Ordinary armies and settlements stay in the merger.
                  (let [payload (cm:create_payload)]
                    ;; AK's fourth argument converts agent types. Unlike CA's
                    ;; transfer-before-merger path, our LLs are still here.
                    ;; Preserve their identity through this same-culture merger.
                    (assert (= (client:culture) (source:culture))
                            "Client merger crosses cultures")
                    (payload:form_confederation client source false false)
                    (set operation.merge-turn (cm:turn_number))
                    (cm:set_saved_value state.pending-key pending)
                    (cm:apply_payload payload client)))))))))

(set tick (fn []
  (when (and (world.host) (not busy?))
    (let [pending (state.saved state.pending-key)
          keys (icollect [key _ (pairs pending)] key)]
      (table.sort keys)
      (when (> (length keys) 0)
        (set busy? true)
        (let [(ok? error) (pcall advance (. pending (. keys 1)) pending)]
          (set busy? false)
          (when (not ok?) (log (tostring error)))))))))

(fn request []
  ;; Allow CA's queued creation, confederation and character commands to settle.
  (each [_ delay (ipairs [0.2 0.5 1 2 3 5])]
    (cm:callback tick delay)))

(fn accept [manager source]
  (if (. (state.targets) (source:name))
      (when (eligible? source)
        (let [pending (state.saved state.pending-key)
              key (source:name)
              culture (source:culture)]
          (when (not (. pending key))
            (let [dead? (or (source:is_dead)
                            (. (state.saved state.challenge-key) key))
                  family-ids (if dead? [] (members source))]
              (assert (or dead? (> (length family-ids) 0))
                      "No target lord in accepted faction")
              (tset pending key {:source key :culture culture
                                  :keep_faction
                                  (. (state.targets) key :keep_faction)
                                  :client (. (state.cultures) culture :faction)
                                  :members family-ids :dead (or dead? false)
                                  :stage :merge :creating false :transfers {}
                                  :skills {}})
              (cm:set_saved_value state.pending-key pending)
              (when (. (state.targets) key :keep_faction)
                (core:trigger_event
                  :ScriptEventEverchosenTransferAccepted key))))
          (request)))
      (originals.accept manager source)))

(fn dilemma [manager winner source]
  (when (or (not (. (state.targets) (source:name)))
            (and (world.host? winner) (eligible? source)))
    (originals.dilemma manager winner source)))

(fn challenge [manager key]
  (when (or (not (. (state.targets) key))
            (and (not (. (state.saved state.pending-key) key))
                 (eligible? (cm:get_faction key))))
    (originals.challenge manager key)))

(fn spawn [manager key units force]
  (let [extended? (. (state.targets) key)
        dead? (and extended? (: (cm:get_faction key) :is_dead))
        result (originals.spawn manager key units force)]
    (when (and dead? (not= result -1))
      (let [challenges (state.saved state.challenge-key)]
        (tset challenges key true)
        (cm:set_saved_value state.challenge-key challenges)))
    result))

(fn clear-dead-challenges []
  (cm:set_saved_value state.challenge-key
    (collect [key flag (pairs (state.saved state.challenge-key))]
      (when (or (. (state.saved state.pending-key) key)
                (not (: (cm:get_faction key) :is_dead)))
        (values key flag)))))

(fn cleanup [manager]
  ;; Native cleanup sees only the temporary challenge faction. Accepted live
  ;; factions are merged separately and never become its enemy_force_cqi.
  (originals.cleanup manager)
  (cm:callback clear-dead-challenges 0.5))

(fn start []
  (when (and (world.host) (not originals))
    (let [manager (state.native)
          extension (state.config)
          setup manager.config]
      (set originals {:accept manager.subjugate_chaos_faction
                      :dilemma manager.trigger_archaon_confederation_dilemma
                      :challenge
                      manager.trigger_archaon_fight_dead_chaos_faction_dilemma
                      :spawn manager.spawn_enemy_mf
                      :cleanup manager.cleanup_post_battle})
      (each [key target (pairs extension.targets)]
        (tset setup.faction_key_to_leader_subtype_list key
              {:subtype_key target.subtype})
        (tset setup.extra_character_subtypes_to_transfer_on_vassalize key
          (collect [_ other (pairs extension.targets)]
            (when (= target.culture other.culture)
              (values other.subtype true)))))
      (each [culture client (pairs extension.cultures)]
        (tset setup.culture_key_to_subjugation_type_list culture :everchosen)
        (tset setup.culture_key_to_vassal_owner_data_list culture
              {:faction_key client.faction :general_subtype_key client.general})
        ;; Challenge rosters use generator-validated native unit keys.
        (tset setup.battle_setup.unit_types culture client.units))
      (set setup.dilemma_type_to_key_list.everchosen extension.dilemma)
      (set manager.subjugate_chaos_faction accept)
      (set manager.trigger_archaon_confederation_dilemma dilemma)
      (set manager.trigger_archaon_fight_dead_chaos_faction_dilemma challenge)
      (set manager.spawn_enemy_mf spawn)
      (set manager.cleanup_post_battle cleanup)
      (core:add_listener (.. state.prefix "turn") :FactionTurnStart
                         #(world.host? ($1:faction)) request true)
      (request))))

{: start}
