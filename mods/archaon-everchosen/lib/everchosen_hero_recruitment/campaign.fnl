(local world (include :everchosen_core.world))

(local prefix "everchosen_hero_group_")
(local columns 3)
(local layout-context
  (.. "RootComponent.ChildContext(\"character_panel\")"
      ".ChildContext(\"agent_parent\").ChildContext(\"list_box\")"
      ".ListLayoutContext"))

;; Guards listener registration within this script session.
(var started? false)

(fn refresh []
  (when (world.host)
    (let [panel (find_uicomponent (core:get_ui_root) :character_panel)
          list (and panel
                    (find_uicomponent panel :lords_and_agents_holder
                      :agent_parent :list_box))]
      ;; The player may close the panel before the deferred update runs.
      (when (and list (panel:Visible))
        (let [updated
              (accumulate [count 0 agent icon
                           (pairs (. (world.static-data) :hero_groups))]
                (let [group (find_uicomponent list agent)]
                  (if group
                      (let [key (.. prefix agent)
                            tooltip-key (.. key "_tooltip")
                            text (common.get_localised_string key)
                            label (find_uicomponent group :label)]
                        (label:SetStateText text key)
                        (group:SetTooltipText
                          (common.get_localised_string tooltip-key)
                          tooltip-key true)
                        (: (find_uicomponent group :icon)
                           :SetImagePath icon 0)
                        (+ count (if (= (label:GetStateText) text) 1 0)))
                      count)))]
          (common.call_context_command
            (.. layout-context ".SetItemsPerRow(" columns ")"))
          (list:Layout)
          (out (.. "[Everchosen hero recruitment] Labels updated: " updated
                   "; columns: "
                   (tostring (common.get_context_value :CcoCampaignRoot ""
                     (.. layout-context ".ItemsPerRow"))))))))))

(local safely-refresh (world.guarded "Everchosen hero recruitment" refresh))

(fn request []
  ;; CharacterRecruitmentPanelCallback creates and fills the native tabs.
  ;; Update after it finishes, without replacing buttons or their states.
  (cm:callback safely-refresh 0.2))

(fn start []
  (when (and (world.host) (not started?))
    (set started? true)
    (core:add_listener (.. prefix "opened") :PanelOpenedCampaign
      #(= $1.string :character_panel) request true)))

{: start}
