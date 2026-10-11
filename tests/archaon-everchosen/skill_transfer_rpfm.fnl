;; CA wrappers and AK argument contracts; observed state is supplied manually.
;; This cannot establish Cco availability or skill removal inside the engine.
(local old :wh3_dlc23_skill_chd_campaign_post_battle)
(local new :wh_main_skill_chs_lord_campaign_ruination)
(local state {:old 2 :new 0 :points 4})
(local host (rpfm.faction {:key :wh_main_chs_chaos :is_human false}))
(local lord (rpfm.character
              {:faction host :character_subtype_key :wh3_dlc23_chd_astragoth
               :cqi 101 :command_queue_index 101
               :has_skill #(> (if (= $1 old) state.old
                                  (= $1 new) state.new 0) 0)}))
(set _G.cco
  (fn [kind id]
    (rpfm.assert_equal kind :CcoCampaignCharacter)
    (rpfm.assert_equal id 101)
    {:Call (fn [_ expression]
             (if (= expression :SkillPointsAvailable) state.points
                 (expression:find old 1 true) state.old
                 (expression:find new 1 true) state.new
                 0))}))

(rpfm.test "skill conversion reaches AK APIs through native CA wrappers"
  (fn []
    (let [skills (require :everchosen_subjugation.skills)
          data (core:get_static_object :everchosen_inheritance_data)
          plan (skills.capture lord
                 data.subjugation.skill_slots.wh3_dlc23_chd_astragoth)]
      (rpfm.assert_equal (skills.advance lord plan (fn [])) false)
      (rpfm.assert_called :remove_skill_point :character_cqi:101 old)
      (rpfm.assert_equal (length (rpfm.calls_to :remove_skill_point)) 2)
      (set state.old 0)
      (set state.points 6)
      (rpfm.assert_equal (skills.advance lord plan (fn [])) false)
      (rpfm.assert_called :add_skill lord new true false)
      (rpfm.assert_equal (length (rpfm.calls_to :add_skill)) 2)
      (set state.new 2)
      (set state.points 4)
      (rpfm.assert_equal (skills.advance lord plan (fn [])) true)
      (rpfm.assert_not_called :force_reset_skills))))
