(local data (include :everchosen_inheritance.data))
(local rules (include :everchosen_inheritance.rules))
(local world (include :everchosen_core.world))

(local recipients-key (.. data.prefix "blessing_recipients"))

(fn eligible? [faction host]
  (and host (world.valid? faction) (not (faction:is_dead))
       (faction:is_vassal_of host)))

(fn relevant? [faction]
  (let [tracked (or (cm:get_saved_value recipients-key) {})]
    (and (world.valid? faction)
         (or (world.host? faction) (. tracked (faction:name))
             (eligible? faction (world.host))))))

(fn sync-faction [faction host bundles]
  "Keep tracking eligible recipients and those with effects still to remove."
  (let [eligible (eligible? faction host)]
    (each [god bundle (pairs bundles)]
      (let [wanted? (and eligible
                         (cm:get_saved_value (rules.state-key god)))
            present? (faction:has_effect_bundle bundle)]
        (if (and wanted? (not present?))
            (cm:apply_effect_bundle bundle (faction:name) 0)
            (and (not wanted?) present?)
            (cm:remove_effect_bundle bundle (faction:name)))))
    (or eligible
        (accumulate [found false _ bundle (pairs bundles) &until found]
          (faction:has_effect_bundle bundle)))))

(fn sync []
  (let [host (world.host)]
    (when host
      (let [tracked (or (cm:get_saved_value recipients-key) {})
            generated (world.static-data)]
        ;; Include extinct former recipients when removing our effects.
        (cm:set_saved_value recipients-key
          (collect [faction (world.factions)]
            (when (and (world.valid? faction)
                       (or (. tracked (faction:name))
                           (eligible? faction host)))
              (let [(ok? retain?)
                    (pcall sync-faction faction host generated.blessings)]
                (when (not ok?)
                  (out (.. "[Everchosen blessings] " (tostring retain?))))
                (when (or (not ok?) retain?)
                  (values (faction:name) true))))))))))

{: sync : relevant?}
