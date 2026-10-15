(local faction-key :wh_main_chs_chaos)
(local bundle-key :everchosen_hero_capacity_test)

(fn start []
  (when (and (cm:is_new_game)
             (= (cm:get_campaign_name) :main_warhammer)
             (not (cm:is_multiplayer)))
    (let [faction (cm:get_faction faction-key)]
      (when (and faction (not (faction:is_null_interface))
                 (faction:is_human))
        ;; Duration zero is permanent; ordinary reloads retain this bundle.
        (cm:apply_effect_bundle bundle-key faction-key 0)
        (out "[Everchosen hero capacity test] Applied opening capacity.")))))

(cm:add_first_tick_callback start)
