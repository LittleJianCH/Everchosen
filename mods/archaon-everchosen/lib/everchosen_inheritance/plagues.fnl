(local scope (include :everchosen_core.data))
(local data (include :everchosen_inheritance.data))
(local world (include :everchosen_core.world))

;; Wrap the native shuffle once per script session; CA owns its saved tables.
(var original-randomise nil)

(fn refresh-context [manager faction]
  (let [name (faction:name)
        info (. manager.plague_faction_info name)
        unlock (. manager.plague_button_unlock name)]
    (common.set_context_value (.. "random_plague_component_list_" name)
                              info.current_symptoms_list)
    (common.set_context_value (.. "random_plague_creation_count_" name)
                              info.plague_creation_counter)
    (common.set_context_value (.. "unlock_plague_button_" name)
                              unlock.infections_gained)))

(fn randomise [manager faction]
  (original-randomise manager faction)
  (when (and (world.host? faction)
             (cm:get_saved_value data.nur-flag))
    (manager:festus_symptom_swap
      (. manager.plague_faction_info scope.host))
    (refresh-context manager faction)))

(fn install []
  (when (not original-randomise)
    (set original-randomise nurgle_plagues.randomise_symptom_location)
    (set nurgle_plagues.randomise_symptom_location randomise)))

(fn unlock [faction]
  (let [manager nurgle_plagues
        name (faction:name)
        infections (world.resource faction manager.pr_key)]
    ;; Re-entry after a partial setup must not discard an existing recipe.
    (when (not (. manager.plague_faction_info name))
      (let [info {:max_blessed_symptoms 1
                  :current_symptoms_list (manager:copy_symptom_table)
                  :plague_creation_counter
                  manager.plague_creation_base_counter}]
        (manager:festus_symptom_swap info)
        (tset manager.plague_faction_info name info)
        (cm:set_plague_component_state faction manager.starting_symptom_key
                                       :UNLOCKED true)
        (cm:set_plague_component_state faction
                                       manager.starting_blessed_symptom_key
                                       :BLESSED true)))
    (let [info (or (. manager.plague_button_unlock name)
                   {:button_locked true :infections_gained 0
                    :infections_end_of_last_turn (infections:value)})]
      (set info.infections_gained
           (math.max info.infections_gained manager.pr_required_to_unlock))
      (tset manager.plague_button_unlock name info)
      (manager:toggle_plagues_button faction info false false))
    (refresh-context manager faction)
    (let [flag (world.resource faction data.nur-flag)]
      (when (< (flag:value) 1)
        (cm:faction_add_pooled_resource name data.nur-flag :other 1)))))

{: install : unlock}
