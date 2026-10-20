(local mod-key :pwd5032_dynamic_movement)
(local prefix (.. "mct_" mod-key "_"))
(local dropdowns [:movement_preset :territory_mode :climate_mode])
(local pages {:Settings :page_movement
              "Naval, Hero & Debug" :page_naval})
(local lock-reasons
  {"Enable Custom Profile to edit" :lock_custom
   "Disable Custom Profile to use presets" :lock_preset
   "Enable Hero Movement to edit" :lock_hero
   "Flat Bonus Mode active — Baseline applies to all" :lock_flat
   "Enable Custom Profile first" :lock_flat_custom
   "Flat Hero Bonus Mode active — Baseline applies to all" :lock_hero_flat
   "Enable Hero Movement first" :lock_hero_flat_enabled
   "Enable Custom Territory Profile to edit" :lock_territory_custom
   "Disable Custom Territory Profile to use presets" :lock_territory_preset
   "Enable Custom Climate Profile to edit" :lock_climate_custom
   "Disable Custom Climate Profile to use presets" :lock_climate_preset})

;; Preserve each scoped getter when translating its displayed lock reason.
(local lock-getters {})

(fn translated-lock-reason [option]
  (let [reason ((. lock-getters option) option)
        suffix (. lock-reasons reason)]
    (if suffix (common.get_localised_string (.. prefix suffix)) reason)))

(fn initialise [context]
  (let [mod (: (context:mct) :get_mod_by_key mod-key)]
    (when mod
      (each [_ key (ipairs dropdowns)]
        (let [option (mod:get_option_by_key key)]
          (each [_ value (ipairs (option:get_values))]
            (let [value-prefix (.. prefix key "_" value.key)]
              (set value.text (.. value-prefix "_text"))
              (set value.tt (.. value-prefix "_tooltip"))))))
      (each [_ option (pairs (mod:get_options))]
        (when (not (. lock-getters option))
          (tset lock-getters option option.get_lock_reason)
          (set option.get_lock_reason translated-lock-reason))))))

(fn translate-pages [context]
  (let [mod (: (context:mct) :get_mod_by_key mod-key)]
    (when mod
      (each [_ page (ipairs (mod:get_settings_pages))]
        (let [suffix (. pages (page:get_key))
              row (page:get_row_uic)
              title (and suffix row (find_uicomponent row :dy_title))]
          ;; Page keys also route the original mod's locking callbacks.
          (when title
            (title:SetStateText
              (common.get_localised_string (.. prefix suffix)))))))))

(fn register []
  (core:add_listener :everchosen_strategic_movement_zh_init
                     :MctInitialized true initialise true)
  (core:add_listener :everchosen_strategic_movement_zh_pages
                     :MctPanelOpened true translate-pages true))

{: register}
