(local world (include :everchosen_core.world))

(local mount :lotet_archaon_dorghar)
(local bundle :lotet_dorghar_artifact_set)
(local native-set :wh3_main_ancillary_set_chs_archaon)
(local artifacts [:wh_main_anc_armour_the_armour_of_morkar
                  :wh_main_anc_enchanted_item_the_crown_of_domination
                  :wh_main_anc_talisman_the_eye_of_sheerian
                  :wh_main_anc_weapon_the_slayer_of_kings])

(fn archaon? [character]
  (and (world.valid? character)
       (character:character_subtype :wh_main_chs_archaon)))

(fn sync [character]
  (when (archaon? character)
    (let [complete? (and (character:has_ancillary mount)
                         (not (character:has_ancillary_set native-set))
                         (accumulate [all? true _ key (ipairs artifacts)]
                           (and all? (character:has_ancillary key))))
          applied? (character:has_effect_bundle bundle)]
      (if complete?
          (when (not applied?)
            (cm:apply_effect_bundle_to_character bundle character 0))
          (when applied?
            (cm:remove_effect_bundle_from_character bundle character))))))

(fn sync-current [cqi]
  (sync (cm:get_character_by_cqi cqi)))

(fn changed [context]
  ;; Equipment settles after the event; never retain its character interface.
  (let [cqi (: (context:character) :command_queue_index)]
    (cm:callback #(sync-current cqi) 0.1)))

(fn selected [context] (sync (context:character)))
(fn relevant? [context] (archaon? (context:character)))

(fn start []
  ;; Keep the standalone script's event and listener identifiers.
  (each [_ event (ipairs [:CharacterArmoryItemEquipped
                          :CharacterArmoryItemUnequipped
                          :CharacterAncillaryGained])]
    (core:add_listener (.. "lotet_dorghar_" event) event relevant? changed true))
  (each [_ event (ipairs [:CharacterTurnStart :CharacterSelected])]
    (core:add_listener (.. "lotet_dorghar_" event) event relevant? selected true)))

{: start}
