(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local settings (include :everchosen_chieftains.settings))

;; MCT resolves these keys through .loc, allowing text-only translations.
(fn text-key [suffix] (.. "mct_" data.mod-key "_" suffix))

(fn add-level-options [mod]
  (mod:add_new_section :levels (text-key :levels_section_text))
  ;; The first chieftain has no rank requirement, so it has no option.
  (for [slot 2 (length data.heroes)]
    (let [key (rules.level-key slot)
          option (mod:add_new_option key :slider)]
      (option:set_text (text-key (.. key "_text")))
      (option:set_tooltip_text (text-key :levels_tooltip))
      (option:slider_set_min_max 1 data.max-rank)
      (option:slider_set_step_size 1)
      (option:slider_set_precision 0)
      (option:set_default_value (. data.levels slot)))))

(fn add-priority-options [mod]
  (mod:add_new_section :priority (text-key :priority_section_text))
  (let [choices (icollect [_ hero (ipairs data.heroes)]
                  {:key hero.subtype :text hero.name-key})]
    (each [slot hero (ipairs data.heroes)]
      (let [key (rules.priority-key slot)
            option (mod:add_new_option key :dropdown)]
        (option:set_text (text-key (.. key "_text")))
        (option:set_tooltip_text (text-key :priority_tooltip))
        (option:add_dropdown_values choices)
        (option:set_default_value hero.subtype)))))

(fn register []
  (let [mct (settings.get-mct)]
    (when mct
      (let [mod (mct:register_mod data.mod-key)]
        (mod:set_title (text-key :title))
        (mod:set_description (text-key :description))
        (add-level-options mod)
        (add-priority-options mod)))))

{: register}
