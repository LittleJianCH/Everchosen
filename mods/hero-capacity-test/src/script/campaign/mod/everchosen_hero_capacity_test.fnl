(local faction-key :wh_main_chs_chaos)
(local bundle-key :everchosen_hero_capacity_test)
(local capacity (include :everchosen_hero_capacity.campaign))

(fn start []
  (when (and (= (cm:get_campaign_name) :main_warhammer)
             (not (cm:is_multiplayer)))
    (let [faction (cm:get_faction faction-key)]
      (when (and faction (not (faction:is_null_interface))
                 (faction:is_human))
        (when (cm:is_new_game)
          ;; Duration zero is permanent; ordinary reloads retain this bundle.
          (cm:apply_effect_bundle bundle-key faction-key 0)
          (out "[Everchosen hero capacity test] Applied opening capacity."))
        (capacity.start)))))

(cm:add_first_tick_callback start)
