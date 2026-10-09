(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local settings (include :everchosen_chieftains.settings))

(fn add-level-options [mod]
  (mod:add_new_section :levels "Target count / 目标人数")
  ;; The first chieftain has no rank requirement, so it has no option.
  (for [slot 2 (length data.heroes)]
    (let [option (mod:add_new_option (rules.level-key slot) :slider)]
      (option:set_text (.. "Chieftain " slot " rank / 第 " slot " 名酋长等级"))
      (option:set_tooltip_text
        "Rank thresholds determine total count, not hero identity. Equal thresholds unlock multiple slots; the first slot has no rank requirement.\n阈值决定总人数，不绑定英雄；相同阈值同时解锁，首名无等级要求。")
      (option:slider_set_min_max 1 data.max-rank)
      (option:slider_set_step_size 1)
      (option:slider_set_precision 0)
      (option:set_default_value (. data.levels slot)))))

(fn add-priority-options [mod]
  (mod:add_new_section :priority "Recruitment priority / 补充顺序")
  (let [choices (icollect [_ hero (ipairs data.heroes)]
                  {:key hero.subtype :text hero.name})]
    (each [slot hero (ipairs data.heroes)]
      (let [option (mod:add_new_option (rules.priority-key slot) :dropdown)]
        (option:set_text (.. "Priority " slot " / 优先级 " slot))
        (option:set_tooltip_text
          "Duplicates keep their first position; omitted heroes follow in default order.\n重复项保留首次位置，遗漏英雄按默认顺序补在末尾。")
        (option:add_dropdown_values choices)
        (option:set_default_value hero.subtype)))))

(fn register []
  (let [mct (settings.get-mct)]
    (when mct
      (let [mod (mct:register_mod data.mod-key)]
        (mod:set_title "Tamurkhan Chieftain Progression / 塔木尔汗酋长成长")
        (mod:set_description
          "Tamurkhan's rank determines Archaon's target chieftain count. Wounded heroes count; only missing heroes are added.\n塔木尔汗等级决定艾查恩应拥有的酋长人数。受伤酋长计入人数，只补缺、不删除。")
        (add-level-options mod)
        (add-priority-options mod)))))

{: register}
