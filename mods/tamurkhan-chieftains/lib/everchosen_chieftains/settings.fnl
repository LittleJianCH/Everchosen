(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))

(fn get-mct []
  "The MCT interface, or nil when the Mod Configuration Tool is not loaded."
  (if (= :function (type _G.get_mct)) (_G.get_mct)))

(fn read []
  "The current config; options MCT cannot supply use their defaults."
  (let [mct (get-mct)
        mod (and mct (mct:get_mod_by_key data.mod-key))]
    (rules.configure
      (fn [key fallback]
        (let [option (and mod (mod:get_option_by_key key))]
          (or (and option (option:get_finalized_setting)) fallback))))))

{: get-mct : read}
