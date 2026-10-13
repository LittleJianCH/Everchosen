;; Commands and their observable results are separate. These fixtures check
;; allocation bookkeeping, not engine execution or Cco tree availability.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))

(fn scenario [subtype levels refund?]
  (let [s {: levels :points 5 :commands [] :sent 0 :objects {}}
        character {:cqi (fn [] 7)
                   :has_skill (fn [_ key] (> (or (. s.levels key) 0) 0))}
        env (setmetatable
              {:cm {:add_first_tick_callback (fn [])
                    :add_pre_first_tick_callback (fn [])
                    :char_lookup_str
                    (fn [_ actor]
                      (assert.equals character actor)
                      ;; Native char_lookup_str returns nil after script_error.
                      (when (not s.rejected?) :character_cqi:7))
                    :remove_skill_point
                    (fn [_ lookup key]
                      (assert.equals :character_cqi:7 lookup)
                      (table.insert s.commands [:remove key]))
                    :add_skill
                    (fn [_ actor key ignore-requirements? ignore-points?]
                      (assert.equals character actor)
                      (assert.is_true ignore-requirements?)
                      (table.insert s.commands [:add key ignore-points?]))}
               :core {:get_static_object (fn [_ key] (. s.objects key))
                      :add_static_object (fn [_ key value]
                                           (tset s.objects key value))}
               :cco
               (fn [kind id]
                 (assert.equals :CcoCampaignCharacter kind)
                 (assert.equals 7 id)
                 {:Call (fn [_ expression]
                          (if (= expression :SkillPointsAvailable) s.points
                              s.unavailable? nil
                              (let [key (expression:match
                                          "Key == \"([^\"]+)\"")]
                                (assert key)
                                (when (not (. (or s.hidden {}) key))
                                  (or (. s.levels key) 0)))))})}
              {:__index _G})]
    (set s.reload
      (fn []
        (set env.package {:preload {} :loaded {}})
        (set env.require
          (fn [key]
            (when (not (. env.package.loaded key))
              (tset env.package.loaded key
                    ((assert (. env.package.preload key)))))
            (. env.package.loaded key)))
        (each [_ file (ipairs [:everchosen_core_data.lua
                               :everchosen_archaon.lua])]
          ((setfenv (assert (loadfile (.. root
            "/build/archaon-everchosen/script/campaign/mod/" file))) env)))
        (set s.module (env.require :everchosen_subjugation.skills))))
    (s.reload)
    (set s.capture #(set s.plan (s.module.capture character
      (. s.objects :everchosen_core_data :subjugation
         :skill_slots subtype))))
    (set s.advance #(s.module.advance character s.plan (fn [])))
    (set s.confirm
      (fn []
        (each [_ [action key free?] (ipairs s.commands)]
          (set s.sent (+ s.sent 1))
          (if (= action :remove)
              (do (tset s.levels key (- (. s.levels key) 1))
                  (when refund? (set s.points (+ s.points 1))))
              (do (tset s.levels key (+ (or (. s.levels key) 0) 1))
                  (when (not free?) (set s.points (- s.points 1))))))
        (set s.commands [])))
    s))

(fn finish [s]
  (assert.is_false (s.advance))
  (let [queued (length s.commands)]
    (assert.is_false (s.advance))
    (assert.equals queued (length s.commands)))
  (s.confirm)
  (assert.is_false (s.advance))
  (s.confirm)
  (assert.is_true (s.advance))
  (assert.equals 5 s.points)
  (assert.is_true (s.advance))
  (assert.equals 0 (length s.commands)))

(describe "Positional skill transfer"
  (fn []
    (it "stops before mutations when the native character lookup is rejected"
      (fn []
        (let [s (scenario :wh2_dlc17_bst_taurox
                  {:wh_dlc03_skill_bst_lord_campaign_corruption 1} true)]
          (s.capture)
          (set s.rejected? true)
          (assert.has_error s.advance)
          (assert.equals :remove s.plan.stage)
          (assert.equals 0 (length s.commands))
          (assert.equals 1 s.levels.wh_dlc03_skill_bst_lord_campaign_corruption)
          (assert.equals 5 s.points)
          (set s.rejected? false)
          (finish s))))
    (it "keeps Beastmen allocations by position when a skill moves slots"
      (fn []
        (let [s (scenario :wh_dlc03_bst_khazrak
                  {:wh_dlc03_skill_bst_lord_gargantian_hooves 1
                   :wh_main_skill_chs_lord_campaign_dark_apothecary 2
                   :wh_dlc03_skill_bst_lord_campaign_corruption 1
                   :wh_dlc03_skill_bst_lord_gathering_of_beasts 2
                   :personal_combat 3} true)]
          (s.capture)
          (set s.hidden {:wh_dlc03_skill_bst_lord_gargantian_hooves true})
          (finish s)
          (assert.equals
            2 s.levels.wh3_dlc20_skill_chs_lord_campaign_blessed_by_evil)
          (assert.equals
            2 s.levels.wh3_dlc20_skill_chs_lord_campaign_devoted_of_chaos)
          (assert.equals
            1 s.levels.wh_main_skill_chs_lord_campaign_dark_apothecary)
          (assert.equals 1 s.levels.wh_main_skill_all_lord_campaign_route_marcher)
          (assert.equals 0 s.levels.wh_dlc03_skill_bst_lord_campaign_corruption)
          (assert.equals 0 s.levels.wh_dlc03_skill_bst_lord_gathering_of_beasts)
          (assert.equals 3 s.levels.personal_combat))))
    (it "keeps Wulfrik's blue-line and World Walker investments without refunds"
      (fn []
        (let [s (scenario :wh_dlc08_nor_wulfrik
                  {:wh_dlc08_skill_nor_lords_campaign_norse_resilience 1
                   :wh_dlc08_skill_nor_wulfrik_campaign_devourers_of_flesh 1
                   :wh_dlc08_skill_nor_wulfrik_unique_world_walker 1
                   :wh_dlc08_skill_nor_wulfrik_unique_eternal_challenger 1}
                  false)]
          (s.capture) (finish s)
          (assert.equals
            1 s.levels.wh3_dlc20_skill_chs_lord_campaign_devoted_of_chaos)
          (assert.equals
            1 s.levels.wh_main_skill_chs_lord_campaign_unholy_resilience)
          (assert.equals 1 s.levels.everchosen_subjugation_world_walker)
          (assert.equals
            0 s.levels.wh_dlc08_skill_nor_wulfrik_unique_world_walker)
          (assert.equals
            1 s.levels.wh_dlc08_skill_nor_wulfrik_unique_eternal_challenger))))
    (it "keeps Taurox's adapted unique points and neighbouring skills"
      (fn []
        (let [s (scenario :wh2_dlc17_bst_taurox
                  {:wh2_dlc17_skill_bst_taurox_unique_favoured_of_the_skull_throne 1
                   :wh2_dlc17_skill_bst_taurox_unique_drowned_in_blood 1
                   :wh2_dlc17_skill_bst_taurox_unique_titans_of_the_deep_forest 1
                   :wh2_dlc17_skill_bst_taurox_unique_daemonic_vigour 1}
                  true)]
          (s.capture) (finish s)
          (assert.equals
            0 s.levels.wh2_dlc17_skill_bst_taurox_unique_titans_of_the_deep_forest)
          (assert.equals 1 s.levels.everchosen_subjugation_titans_of_the_deep_forest)
          (assert.equals
            0 s.levels.wh2_dlc17_skill_bst_taurox_unique_drowned_in_blood)
          (assert.equals 1 s.levels.everchosen_subjugation_drowned_in_blood)
          (assert.equals
            1 s.levels.wh2_dlc17_skill_bst_taurox_unique_favoured_of_the_skull_throne)
          (assert.equals
            1 s.levels.wh2_dlc17_skill_bst_taurox_unique_daemonic_vigour)
          (assert.equals 4 s.sent))))
    (it "keeps Zhatan's Subjugator point and neighbouring unique skills"
      (fn []
        (let [s (scenario :wh3_dlc23_chd_zhatan
                  {:wh3_dlc23_skill_chd_zhatan_brutality_of_zharr 1
                   :wh3_dlc23_skill_chd_zhatan_subjugator 1
                   :wh3_dlc23_skill_chd_zhatan_laughing_killer 1}
                  false)]
          (s.capture) (finish s)
          (assert.equals 0 s.levels.wh3_dlc23_skill_chd_zhatan_subjugator)
          (assert.equals 1 s.levels.everchosen_subjugation_subjugator)
          (assert.equals 1 s.levels.wh3_dlc23_skill_chd_zhatan_brutality_of_zharr)
          (assert.equals 1 s.levels.wh3_dlc23_skill_chd_zhatan_laughing_killer)
          (assert.equals 2 s.sent))))
    (it "resumes a save between prince conversion phases without duplicates"
      (fn []
        (let [s (scenario :wh3_main_dae_daemon_prince
                  {:wh3_main_skill_dae_slaanesh_campaign_hero_success_chance 3
                   :personal_spell 2} true)]
          (s.capture) (s.advance) (s.confirm)
          (s.reload)
          (assert.is_false (s.advance))
          (s.confirm)
          (assert.is_true (s.advance))
          (assert.equals 3 s.levels.everchosen_daemon_skill_slaanesh_1_2)
          (assert.equals 2 s.levels.personal_spell)
          (assert.equals 5 s.points)
          (assert.equals 6 s.sent))))
    (it "does not mutate skills if the native allocation cannot be read"
      (fn []
        (let [s (scenario :wh3_main_dae_daemon_prince
                  {:wh3_main_skill_dae_slaanesh_campaign_hero_success_chance 1}
                  true)]
          (set s.unavailable? true)
          (assert.has_error s.capture)
          (assert.equals 0 (length s.commands)))))))
