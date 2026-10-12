;;; Prepare vassal factions and successors before transferring their lords.

(local world (include :everchosen_core.world))
(local scope (include :everchosen_core.data))
(local state (include :everchosen_subjugation.state))

(fn unused-client? [client]
  (and (world.valid? client) (not (client:is_human))
       (client:is_dead) (= (client:num_regions) 0)
       (= (: (client:character_list) :num_items) 0)
       (= (: (client:military_force_list) :num_items) 0)
       (not (client:was_confederated))
       (not (world.valid? (client:master)))))

(fn available-client? [culture]
  (let [key (. (state.cultures) culture :faction)
        client (cm:get_faction key)]
    (and (world.valid? client) (not (client:is_human))
         (= (client:culture) culture)
         (or (. (state.saved state.clients-key) key) (unused-client? client)))))

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
  (let [pending (state.saved state.pending-key)
        operation (. pending source-key)]
    (when operation
      ;; A delivered callback ends this creation request, even on failure.
      (set operation.creating false)
      (cm:set_saved_value state.pending-key pending)
      (let [leader (and cqi (cm:get_character_by_cqi cqi))]
        (when (world.valid? leader) (cm:randomise_character_name leader))))))

(fn prepare-client [source operation pending]
  (let [client (cm:get_faction operation.client)
        culture (. (state.cultures) operation.culture)]
    (assert (world.valid? client)
            (.. "Client is absent from campaign startpos: " operation.client))
    (assert (not (client:is_human)) "Client faction is human controlled")
    ;; Recheck immediately before activation: another mod may have used it
    ;; since the dilemma opened. A live native faction is never taken over.
    (when (not (. (state.saved state.clients-key) operation.client))
      (assert (unused-client? client) "Client faction is already in use"))
    (if (has-leader? client)
        (let [master (client:master)]
          (assert (or (not (world.valid? master)) (world.host? master))
                  "Client has another overlord")
          (when (not (client:is_vassal_of (world.host)))
            (cm:force_make_vassal scope.host operation.client true))
          (client:is_vassal_of (world.host)))
        (when (not operation.creating)
          (let [region (location source)]
            (assert region "No location for client faction leader")
            (let [(x y)
                  (cm:find_valid_spawn_location_for_character_from_settlement
                    operation.client region false true)]
              (assert (and x y (not= x -1)) "No client leader spawn position")
              (let [claimed (state.saved state.clients-key)]
                (when (not (. claimed operation.client))
                  (cm:change_localised_faction_name
                    operation.client culture.name)
                  (tset claimed operation.client true)
                  (cm:set_saved_value state.clients-key claimed)))
              (set operation.creating true)
              (cm:set_saved_value state.pending-key pending)
              (cm:awaken_faction_from_death client)
              (cm:create_force_with_general operation.client nil region x y
                :general culture.general "" "" "" "" true
                #(created (source:name) $1))))
          false))))

(fn prepare-successor [source operation pending]
  "Keep Daniel's original faction; a new leader must precede his transfer."
  (if (and (has-leader? source)
           (not= (: (source:faction_leader) :character_subtype_key)
                 (. (state.targets) operation.source :subtype)))
      (do
        (when (and (not (source:is_vassal_of (world.host)))
                   (not= operation.vassal-turn (cm:turn_number)))
          (set operation.vassal-turn (cm:turn_number))
          (cm:set_saved_value state.pending-key pending)
          (cm:force_make_vassal scope.host operation.source true))
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
          (cm:set_saved_value state.pending-key pending)
          (cm:create_force_with_general operation.source nil region x y
            :general (. (state.cultures) operation.culture :general)
            "" "" "" "" true #(created operation.source $1)))
        false)))

{: available-client? : prepare-client : prepare-successor}
