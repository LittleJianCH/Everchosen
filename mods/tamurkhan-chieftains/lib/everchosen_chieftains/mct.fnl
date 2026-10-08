(local data (include :everchosen_chieftains.data))
(local settings (include :everchosen_chieftains.settings))

(fn register []
  (local mct (settings.get-mct))
  (when mct
    (local mod (mct:register_mod data.mod-key))
    (mod:set_title "Tamurkhan Chieftain Progression / 塔木尔汗酋长成长")
    (mod:set_description
      "Tamurkhan's rank determines Archaon's target chieftain count. Wounded heroes count; only missing heroes are added.\n塔木尔汗等级决定艾查恩应拥有的酋长人数。受伤酋长计入人数，只补缺、不删除。")
    (mod:add_new_section :levels "Target count / 目标人数")
    (for [i 2 (# data.heroes)]
      (local option (mod:add_new_option (.. :level_ i) :slider))
      (option:set_text (.. "Chieftain " i " rank / 第 " i " 名酋长等级"))
      (option:set_tooltip_text
        "Rank thresholds determine total count, not hero identity. Equal thresholds unlock multiple slots; the first slot has no rank requirement.\n阈值决定总人数，不绑定英雄；相同阈值同时解锁，首名无等级要求。")
      (option:slider_set_min_max 1 25)
      (option:slider_set_step_size 1)
      (option:slider_set_precision 0)
      (option:set_default_value (. data.levels i)))
    (mod:add_new_section :priority "Recruitment priority / 补充顺序")
    (local choices [])
    (each [_ hero (ipairs data.heroes)]
      (table.insert choices {:key hero.subtype :text hero.name}))
    (each [i hero (ipairs data.heroes)]
      (local option (mod:add_new_option (.. :priority_ i) :dropdown))
      (option:set_text (.. "Priority " i " / 优先级 " i))
      (option:set_tooltip_text
        "Duplicates keep their first position; omitted heroes follow in default order.\n重复项保留首次位置，遗漏英雄按默认顺序补在末尾。")
      (option:add_dropdown_values choices)
      (option:set_default_value hero.subtype))))

{: register}
