;; Exercise CA's event, countdown and dilemma code with AK typed objects.
;; Force creation and camera completion are boundaries, not engine simulations.
(local host-key :wh_main_chs_chaos)
(local enemy-key :wh_dlc08_nor_norsca)
(local host (rpfm.faction {:key host-key :is_human false}))
(local enemy (rpfm.faction {:key enemy-key :is_human false :is_dead true
                            :culture :wh_dlc08_nor_norsca
                            :confederation_in_progress false}))
(local killer (rpfm.faction {:key :wh_main_emp_empire :is_human false}))
(local army (rpfm.object :MILITARY_FORCE_SCRIPT_INTERFACE
                        {:command_queue_index 100 :faction host}))
(local enemy-army (rpfm.object :MILITARY_FORCE_SCRIPT_INTERFACE
                              {:command_queue_index 200 :faction enemy}))
(local archaon (rpfm.character
                {:faction host :cqi 101 :command_queue_index 101
                 :character_subtype_key :wh_main_chs_archaon
                 :military_force army :in_settlement false :is_wounded false
                 :is_besieging false}))
(rpfm.mock host :faction_leader archaon)
(rpfm.mock host :character_list [archaon])
(local observed {:turn 1 :spawned 0})

(fn start []
  (assert (cm:load_global_script
            :script/campaign/wh3_dlc29_archaon_subjugation))
  (let [manager (. (core:get_env) :archaon_subjugation)]
    (manager:initialise)
    (rpfm.mock host :is_human true)
    (rpfm.mock (cm:model) :turn_number #(do observed.turn))
    (rpfm.mock (cm:model) :random_int (fn [minimum maximum] minimum))
    (rpfm.mock (cm:model) :has_military_force_command_queue_index true)
    (rpfm.mock (cm:model) :military_force_for_command_queue_index enemy-army)
    ;; Keep native roster generation; supply the separately observed force.
    (set manager.spawn_enemy_mf
      (fn [_ key units attacker]
        (rpfm.assert_equal key enemy-key)
        (rpfm.assert_equal attacker army)
        (assert (units:find "nor_" 1 true))
        (set observed.spawned (+ observed.spawned 1))
        200))
    (set cm.scroll_camera_with_cutscene_to_character
      (fn [_ duration callback cqi] (callback)))
    (let [extension (require :everchosen_subjugation.campaign)]
      (extension.start))
    manager))

(rpfm.test "death countdown survives serialization and offers a native battle"
  (fn []
    (let [manager (start)
          dilemmas manager.config.dilemma_type_to_key_list
          event :ScriptEventFightDeadChaosFactionDilemma]
      (rpfm.fire :FactionDeath {:faction enemy :killer killer})
      (let [(remaining turn) (cm:report_turns_until_countdown_event
                              host-key event enemy-key)]
        (assert (and (>= remaining 3) (<= remaining 10)))
        ;; These are the same serializers used by CA's save/load callbacks.
        (let [saved (cm:turn_countdown_events_to_string)]
          (set cm.turn_countdown_events {})
          (cm:turn_countdown_events_from_string saved))
        (set observed.turn turn)
        (cm:check_turn_countdown_events host-key)
        (rpfm.assert_equal observed.spawned 1)
        (rpfm.assert_called :add_target :default army)
        (rpfm.assert_called :add_target :target_military_1 enemy-army)
        (rpfm.assert_equal
          (length (rpfm.calls_to :launch_custom_dilemma_from_builder)) 1)
        (rpfm.fire :DilemmaChoiceMadeEvent
          {:dilemma dilemmas.fight_dead_chaos_faction
           :choice 0})
        (rpfm.assert_called :force_attack_of_opportunity
                           100 200 false true true)))))
