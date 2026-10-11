(local world (include :everchosen_inheritance.world))
(local inheritance (include :everchosen_inheritance.data))
(local skills (include :everchosen_subjugation.skills))

(local prefix "everchosen_subjugation_")
(local pending-key (.. prefix "pending"))
(local done-key (.. prefix "completed"))
(local challenge-key (.. prefix "challenges"))
(local clients-key (.. prefix "claimed_clients"))

;; Native adapters and the command guard belong to this Lua session only.
(var originals nil)
(var busy? false)
;; A submitted skill phase schedules its own confirmation tick.
(var tick nil)

(fn log [message]
  (out (.. "[Everchosen subjugation] " message)))

(fn config []
  (. (core:get_static_object :everchosen_inheritance_data) :subjugation))

(fn targets [] (. (config) :targets))
(fn cultures [] (. (config) :cultures))

(fn saved [key]
  (or (cm:get_saved_value key) {}))

(fn native [] (. (core:get_env) :archaon_subjugation))

(fn character [family-id]
  (let [family (cm:get_family_member_by_cqi family-id)]
    (when (world.valid? family) (family:character))))

(fn owned? [family-id faction-key]
  (let [lord (character family-id)]
    (and (world.valid? lord) (world.valid? (lord:faction))
         (= (: (lord:faction) :name) faction-key))))

(fn unused-client? [client]
  (and (world.valid? client) (not (client:is_human))
       (client:is_dead) (= (client:num_regions) 0)
       (= (: (client:character_list) :num_items) 0)
       (= (: (client:military_force_list) :num_items) 0)
       (not (client:was_confederated))
       (not (world.valid? (client:master)))))

(fn available-client? [culture]
  (let [key (. (cultures) culture :faction)
        client (cm:get_faction key)]
    (and (world.valid? client) (not (client:is_human))
         (= (client:culture) culture)
         (or (. (saved clients-key) key) (unused-client? client)))))

(fn eligible? [source]
  (let [target (and (world.valid? source)
                    (. (targets) (source:name)))]
    (and (world.host) target (not (source:is_human))
         (= (source:culture) target.culture)
         (or (source:is_dead) target.keep_faction
             (available-client? target.culture))
         (not (. (saved done-key) (source:name)))
         (not (. (world.owned (world.host)) target.subtype))
         (not (accumulate [protected? false _ key
                           (ipairs (cm:get_human_factions)) &until protected?]
                (source:is_vassal_of (cm:get_faction key)))))))

(fn members [source]
  "Snapshot family IDs before confederation mutates the character list."
  (let [culture (source:culture)
        subtypes (collect [_ target (pairs (targets))]
                   (when (= target.culture culture)
                     (values target.subtype true)))]
    (icollect [lord (world.items (source:character_list))]
      (when (and (world.valid? lord)
                 (. subtypes (lord:character_subtype_key))
                 (= (: (lord:faction) :name) (source:name)))
        (: (lord:family_member) :command_queue_index)))))

(fn has-leader? [faction]
  (and (world.valid? faction) (faction:has_faction_leader)
       (let [leader (faction:faction_leader)]
         (and (world.valid? leader) (world.valid? (leader:faction))
              (= (: (leader:faction) :name) (faction:name))
              (leader:character_type :general)
              (not= (leader:character_subtype_key) "")))))

(fn location [source]
  (if (> (source:num_regions) 0)
      (: (: (source:region_list) :item_at 0) :name)
      (accumulate [found nil lord (world.items (source:character_list))
                   &until found]
        (when (and (world.valid? lord) (lord:has_region))
          (: (lord:region) :name)))))

(fn created [source-key cqi]
  (let [pending (saved pending-key)
        operation (. pending source-key)]
    (when operation
      ;; A delivered callback ends this specific creation request, even on failure.
      (set operation.creating false)
      (cm:set_saved_value pending-key pending)
      (let [leader (and cqi (cm:get_character_by_cqi cqi))]
        (when (world.valid? leader) (cm:randomise_character_name leader))))))

(fn prepare-client [source operation pending]
  (let [client (cm:get_faction operation.client)
        culture (. (cultures) operation.culture)]
    (assert (world.valid? client)
            (.. "Client is absent from campaign startpos: " operation.client))
    (assert (not (client:is_human)) "Client faction is human controlled")
    ;; Recheck immediately before activation: another mod may have used it
    ;; since the dilemma opened. A live native faction is never taken over.
    (when (not (. (saved clients-key) operation.client))
      (assert (unused-client? client) "Client faction is already in use"))
    (if (has-leader? client)
        (let [master (client:master)]
          (assert (or (not (world.valid? master)) (world.host? master))
                  "Client has another overlord")
          (when (not (client:is_vassal_of (world.host)))
            (cm:force_make_vassal inheritance.host operation.client true))
          (client:is_vassal_of (world.host)))
        (when (not operation.creating)
          (let [region (location source)]
            (assert region "No location for client faction leader")
            (let [(x y) (cm:find_valid_spawn_location_for_character_from_settlement
                          operation.client region false true)]
              (assert (and x y (not= x -1)) "No client leader spawn position")
              (let [claimed (saved clients-key)]
                (when (not (. claimed operation.client))
                  (cm:change_localised_faction_name operation.client culture.name)
                  (tset claimed operation.client true)
                  (cm:set_saved_value clients-key claimed)))
              (set operation.creating true)
              (cm:set_saved_value pending-key pending)
              (cm:awaken_faction_from_death client)
              (cm:create_force_with_general operation.client nil region x y
                :general culture.general "" "" "" "" true
                #(created (source:name) $1))))
          false))))

(fn prepare-successor [source operation pending]
  "Keep Daniel's original faction; a new leader must precede his transfer."
  (if (and (has-leader? source)
           (not= (: (source:faction_leader) :character_subtype_key)
                 (. (targets) operation.source :subtype)))
      (do
        (when (and (not (source:is_vassal_of (world.host)))
                   (not= operation.vassal-turn (cm:turn_number)))
          (set operation.vassal-turn (cm:turn_number))
          (cm:set_saved_value pending-key pending)
          (cm:force_make_vassal inheritance.host operation.source true))
        (source:is_vassal_of (world.host)))
      (when (and (not operation.creating)
                 (not= operation.successor-turn (cm:turn_number)))
        (let [region (location source)
              (x y) (cm:find_valid_spawn_location_for_character_from_settlement
                      operation.source region false true)]
          (assert (and region x y (not= x -1))
                  "No successor spawn position")
          (set operation.creating true)
          (set operation.successor-turn (cm:turn_number))
          (cm:set_saved_value pending-key pending)
          (cm:create_force_with_general operation.source nil region x y
            :general (. (cultures) operation.culture :general)
            "" "" "" "" true #(created operation.source $1)))
        false)))

(fn transfer [operation pending]
  (each [_ id (ipairs operation.members)]
    (when (and (not (owned? id inheritance.host))
               (not= (. operation.transfers id) (cm:turn_number)))
      (let [lord (character id)]
        (let [expected (if (or operation.dead operation.keep_faction)
                           operation.source operation.client)
              owner (and (world.valid? lord) (lord:faction))]
          (assert (owned? id expected)
            (.. "Accepted lord ownership mismatch: family=" id
                ", expected=" expected ", actual="
                (if (world.valid? owner) (owner:name) "no character"))))
        (when (not (. operation.skills id))
          (tset operation.skills id
            (skills.capture lord
              (. (config) :skill_slots (lord:character_subtype_key)))))
        (tset operation.transfers id (cm:turn_number))
        (cm:set_saved_value pending-key pending)
        ;; As in CA's monogod path: acquire the lord, not his defeated army.
        (when (lord:is_alive)
          (cm:kill_character (cm:char_lookup_str (lord:cqi)) true))
        (let [current (character id)]
          (assert (world.valid? current) "Lord unavailable after convalescence")
          (cm:reassign_character (current:cqi)
                                 (: (world.host) :command_queue_index))
          (cm:stop_character_convalescing (: (character id) :cqi)))))))

(fn finish [source operation pending]
  (when (and
          (accumulate [all? true _ id (ipairs operation.members)
                       &until (not all?)]
            (owned? id inheritance.host))
          (accumulate [ready? true _ id (ipairs operation.members)]
            (let [plan (assert (. operation.skills id)
                               "Missing pre-transfer skill allocation")
                  before plan.stage
                  done? (skills.advance (character id) plan
                          #(cm:set_saved_value pending-key pending))]
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
        (let [persistent (. (native) :persistent)]
          (set persistent.suppress_faction_death_event true))
        (cm:kill_faction (source:name))))
    (let [done (saved done-key)
          challenges (saved challenge-key)]
      (tset done (source:name) true)
      (tset challenges (source:name) nil)
      (tset pending (source:name) nil)
      (cm:set_saved_value done-key done)
      (cm:set_saved_value challenge-key challenges)
      (cm:set_saved_value pending-key pending)
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
            (assert (not= (: (native) :resurrect_enemy_faction_legendary_lord
                                     operation.source) -1)
                    "Could not recover the existing legendary lord"))
          (set operation.members (members source))
          (assert (> (length operation.members) 0) "No accepted lord to transfer")
          (set operation.stage :transfer)
          (cm:set_saved_value pending-key pending)
          ;; A resurrected, landless faction can be cleaned up on the next tick.
          ;; Follow the native challenge flow and transfer in this same event.
          (transfer operation pending)
          (finish source operation pending))
        operation.keep_faction
        (when (prepare-successor source operation pending)
          (cm:change_localised_faction_name operation.source
            (. (cultures) operation.culture :name))
          (set operation.stage :transfer)
          (cm:set_saved_value pending-key pending))
        (let [client (cm:get_faction operation.client)]
          (if (and (world.valid? client)
                   (source:was_confederated_by_faction client))
              (do
                (set operation.stage :transfer)
                (cm:set_saved_value pending-key pending))
              (do
                (assert (not (source:is_dead))
                        "Living source disappeared before client merger")
                (when (and (prepare-client source operation pending)
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
                    (cm:set_saved_value pending-key pending)
                    (cm:apply_payload payload client)))))))))

(set tick (fn []
  (when (and (world.host) (not busy?))
    (let [pending (saved pending-key)
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
  (if (. (targets) (source:name))
      (when (eligible? source)
        (let [pending (saved pending-key)
              key (source:name)
              culture (source:culture)]
          (when (not (. pending key))
            (let [dead? (or (source:is_dead) (. (saved challenge-key) key))
                  family-ids (if dead? [] (members source))]
              (assert (or dead? (> (length family-ids) 0))
                      "No target lord in accepted faction")
              (tset pending key {:source key :culture culture
                                  :keep_faction
                                  (. (targets) key :keep_faction)
                                  :client (. (cultures) culture :faction)
                                  :members family-ids :dead (or dead? false)
                                  :stage :merge :creating false :transfers {}
                                  :skills {}})
              (cm:set_saved_value pending-key pending)
              (when (. (targets) key :keep_faction)
                (core:trigger_event :ScriptEventEverchosenTransferAccepted key))))
          (request)))
      (originals.accept manager source)))

(fn dilemma [manager winner source]
  (when (or (not (. (targets) (source:name)))
            (and (world.host? winner) (eligible? source)))
    (originals.dilemma manager winner source)))

(fn challenge [manager key]
  (when (or (not (. (targets) key))
            (and (not (. (saved pending-key) key))
                 (eligible? (cm:get_faction key))))
    (originals.challenge manager key)))

(fn spawn [manager key units force]
  (let [extended? (. (targets) key)
        dead? (and extended? (: (cm:get_faction key) :is_dead))
        result (originals.spawn manager key units force)]
    (when (and dead? (not= result -1))
      (let [challenges (saved challenge-key)]
        (tset challenges key true)
        (cm:set_saved_value challenge-key challenges)))
    result))

(fn clear-dead-challenges []
  (cm:set_saved_value challenge-key
    (collect [key flag (pairs (saved challenge-key))]
      (when (or (. (saved pending-key) key)
                (not (: (cm:get_faction key) :is_dead)))
        (values key flag)))))

(fn cleanup [manager]
  ;; Native cleanup sees only the temporary challenge faction. Accepted live
  ;; factions are merged separately and never become its enemy_force_cqi.
  (originals.cleanup manager)
  (cm:callback clear-dead-challenges 0.5))

(fn start []
  (when (and (world.host) (not originals))
    (let [manager (native)
          extension (config)
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
      (core:add_listener (.. prefix "turn") :FactionTurnStart
                         #(world.host? ($1:faction)) request true)
      (request))))

{: start}
