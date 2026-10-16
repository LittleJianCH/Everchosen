(local world (include :everchosen_core.world))
(local rules (include :everchosen_hero_recruitment.rules))

(local prefix "everchosen_hero_")
(local list-context
  (.. "RootComponent.ChildContext(\"character_panel\")"
      ".ChildContext(\"agent_parent\").ChildContext(\"list_box\")"))
(local frame-context
  (.. "RootComponent.ChildContext(\"character_panel\")"
      ".ChildContext(\"character_panel_info_holder\")"))
(local header-height 122)

(fn controls [include-hidden?]
  "Re-query only the native recruitment controls used by the two pages."
  (let [panel (find_uicomponent (core:get_ui_root) :character_panel)
        parent (and panel (find_uicomponent panel :lords_and_agents_holder
                                            :agent_parent))]
    (when (and parent
               (or include-hidden? (and (panel:Visible) (parent:Visible))))
      {: panel : parent
       :frame (find_uicomponent panel :character_panel_info_holder)
       :agents (find_uicomponent parent :list_box)
       :capacity (find_uicomponent parent :dy_agent_cap)
       :load-character (find_uicomponent panel :footer :button_load_character)
       :confirm (find_uicomponent panel :footer :button_confirm)
       :raise (find_uicomponent panel :footer :button_raise)
       :private (find_uicomponent parent :everchosen_hero_families)
       :selection (find_uicomponent panel :general_selection_panel)
       :types (find_uicomponent panel :general_selection_panel
                :lore_select_parent :wizard_type :type_list)})))

(fn children [parent]
  "Read one known UI list, without traversing the rest of the UI tree."
  (if parent
      (fcollect [index 0 (- (parent:ChildCount) 1)]
        (UIComponent (parent:Find index)))
      []))

(fn clicked? [parent context]
  (and parent
       (let [target (find_uicomponent parent context.string)]
         (and target
              (= (target:Address)
                 (: (UIComponent context.component) :Address))))))

(fn create [controls]
  (core:get_or_create_component :everchosen_hero_families
    :ui/everchosen/hero_families controls.parent))

(fn reserve-frame [controls state]
  ;; Freeze one outer frame once; switching pages never hides its layout rows.
  (set state.frame-height (controls.frame:Height))
  (set state.header-height (controls.parent:Height))
  (common.call_context_command
    (.. frame-context ".ListLayoutContext.SetSizeToContents(false)"))
  (controls.frame:Resize (controls.frame:Width)
    (+ state.frame-height (- header-height state.header-height)))
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(false)"))
  (controls.parent:Resize 810 header-height)
  (when controls.load-character
    (set state.load-character
      {:address (controls.load-character:Address)
       :visible (controls.load-character:Visible)})
    (controls.load-character:SetVisible false)))

(fn show-page [controls entries number pages selected private?]
  (controls.private:SetVisible true)
  (controls.agents:SetVisible (not private?))
  (for [index 1 (. (world.static-data) :hero_recruitment :page_size)]
    (let [button (find_uicomponent controls.private (.. prefix "slot_" index))
          group (and private? (. entries index))]
      (button:SetVisible (not (not group)))
      (when group
        (: (find_uicomponent button :label) :SetStateText
           (common.get_localised_string group.name-key))
        (: (find_uicomponent button :icon) :SetImagePath group.icon 0)
        (button:SetTooltipText
          (common.get_localised_string group.description-key) "" true)
        (button:SetState (if (= group.key selected) :selected :active)))))
  (let [mode (find_uicomponent controls.private :everchosen_hero_mode)]
    (: (find_uicomponent mode :label) :SetStateText
       (common.get_localised_string
         (if private? :everchosen_hero_native_page
                      :everchosen_hero_private_page))))
  (each [_ id (ipairs [:everchosen_hero_page :everchosen_hero_prev
                      :everchosen_hero_next])]
    (: (find_uicomponent controls.private id) :SetVisible private?))
  (: (find_uicomponent controls.private :everchosen_hero_page) :SetStateText
     (string.format (common.get_localised_string :everchosen_hero_page)
                    number pages))
  (: (find_uicomponent controls.private :everchosen_hero_prev)
     :SetState (if (> number 1) :active :inactive))
  (: (find_uicomponent controls.private :everchosen_hero_next)
     :SetState (if (< number pages) :active :inactive)))

(fn native-labels [controls groups state]
  (each [_ group (ipairs groups)]
    (when (not group.private?)
      (let [button (find_uicomponent controls.agents group.agent)]
        (when button
          (let [label (find_uicomponent button :label)]
            (when (not (. state.labels group.agent))
              (tset state.labels group.agent
                {:address (button:Address) :text (label:GetStateText)
                 :tooltip (button:GetTooltipText)}))
            (label:SetStateText (common.get_localised_string group.name-key)))
          (: (find_uicomponent button :icon) :SetImagePath group.icon 0)
          (button:SetTooltipText
            (common.get_localised_string group.description-key) "" true))))))

(fn gate [controls enabled?]
  ;; Native active/inactive states continue to enforce funds and buildings.
  (each [_ button (ipairs [controls.confirm controls.raise])]
    (when button
      (button:SetInteractive
        (and enabled? (rules.selectable? (button:CurrentState)))))))

(fn block [controls]
  (controls.selection:SetInteractive false)
  (gate controls false))

(fn restore-types [controls state]
  (each [subtype address (pairs state.hidden)]
    (let [button (and controls.types
                     (find_uicomponent controls.types subtype))]
      (when (and button (= (button:Address) address))
        (button:SetVisible true))))
  (set state.hidden {}))

(fn filter-types [controls state group]
  (restore-types controls state)
  (each [_ button (ipairs (children controls.types))]
    (when (and (. state.native-subtypes (button:Id))
               (not (. group.members (button:Id))) (button:Visible))
      (tset state.hidden (button:Id) (button:Address))
      (button:SetVisible false)))
  (when controls.types (controls.types:Layout)))

(fn matches? [controls group]
  "Require the selected subtype and every visible native candidate to match."
  (let [list (find_uicomponent controls.selection :character_list :list_box)
        cards (icollect [_ card (ipairs (children list))]
                (when (card:Visible) card))]
    (and (> (length cards) 0)
         (accumulate [selected false _ button
                     (ipairs (children controls.types)) &until selected]
           (and (. group.members (button:Id))
                (rules.selected? (button:CurrentState))))
         (accumulate [matches true _ card (ipairs cards)
                      &until (not matches)]
           (let [character (card:GetContextObject :CcoCampaignCharacter)]
             (and character
                  (. group.members
                    (character:Call :AgentSubtypeRecordContext.Key))))))))

(fn show-capacity [controls state group snapshot]
  (when controls.capacity
    (controls.capacity:SetVisible true)
    (controls.capacity:SetState
      (if (>= snapshot.used snapshot.limit) :maxed :NewState))
    (controls.capacity:SetStateText
      (string.format "%d/%d" snapshot.used snapshot.limit))
    (controls.capacity:SetTooltipText
      (common.get_localised_string group.description-key) "" true)))

(fn restore [controls state]
  (restore-types controls state)
  (when controls.private (controls.private:SetVisible false))
  (controls.agents:SetVisible true)
  (controls.selection:SetInteractive true)
  (gate controls true)
  (each [agent saved (pairs state.labels)]
    (let [button (find_uicomponent controls.agents agent)]
      (when (and button (= (button:Address) saved.address))
        (: (find_uicomponent button :label) :SetStateText saved.text)
        (button:SetTooltipText saved.tooltip "" true))))
  (when (and controls.load-character state.load-character
             (= (controls.load-character:Address) state.load-character.address))
    (controls.load-character:SetVisible state.load-character.visible))
  (controls.parent:Resize 810 state.header-height)
  (controls.frame:Resize (controls.frame:Width) state.frame-height)
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(true)"))
  (common.call_context_command
    (.. frame-context ".ListLayoutContext.SetSizeToContents(true)"))
  (controls.agents:Layout)
  (controls.frame:Layout))

{: controls : children : clicked? : create : reserve-frame : show-page
 : native-labels : gate : block : restore-types : filter-types : matches?
 : show-capacity : restore}
