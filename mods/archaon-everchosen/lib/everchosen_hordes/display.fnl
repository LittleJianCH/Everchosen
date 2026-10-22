(local shared (include :everchosen_core.world))
(local data (include :everchosen_hordes.data))
(local rules (include :everchosen_hordes.rules))

(fn check-query [context expression expected]
  (let [(ok? value) (pcall context.Call context expression)]
    (when (or (not ok?) (not= value expected))
      (out (.. "[Everchosen horde display] " expression
               " expected=" (tostring expected)
               " actual=" (tostring value))))))

(fn check []
  ;; Query one known record and one private list, never traverse live UI trees.
  ;; Building previews must resolve even before a campaign lord is selected.
  (when (shared.host)
    (let [config (data.config)
          building (. (rules.sorted-keys config.buildings) 1)
          units (. config.buildings building)
          unit (. units 1)
          context (cco :CcoCampaignRoot "")
          record (.. "DatabaseRecordContext(\"CcoMainUnitRecord\", \""
                     unit "\")")]
      (check-query context (.. record ".Key") unit)
      (check-query context (.. "EverchosenHordeUI.Capacity(" record ")")
                   (. config.units unit :cap))
      (check-query context
        (.. "EverchosenHordeUI.Pairs(DatabaseRecordContext("
            "\"CcoBuildingLevelRecord\", \"" building "\")).Size")
        (length units)))))

{:check (shared.guarded "Everchosen horde display" check)}
