(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))

(fn get-mct []
  (and (= :function (type _G.get_mct)) (_G.get_mct)))

(fn read []
  (local mct (get-mct))
  (local mod (and mct (mct:get_mod_by_key data.mod-key)))
  (rules.configure
    (fn [key fallback]
      (local option (and mod (mod:get_option_by_key key)))
      (local value (and option (option:get_finalized_setting)))
      (if (or (= value nil) (= value false)) fallback value))))

{: read : get-mct}
