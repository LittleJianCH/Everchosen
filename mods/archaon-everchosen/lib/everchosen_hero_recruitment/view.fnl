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
  "Re-query the known native recruitment controls without a UI tree scan."
  (let [panel (find_uicomponent (core:get_ui_root) :character_panel)
        parent (and panel (find_uicomponent panel :lords_and_agents_holder
                                            :agent_parent))
        frame (and panel
                   (find_uicomponent panel :character_panel_info_holder))
        agents (and parent (find_uicomponent parent :list_box))
        selection (and panel
                       (find_uicomponent panel :general_selection_panel))
        footer (and panel (find_uicomponent panel :footer))
        confirm (and footer (find_uicomponent footer :button_confirm))]
    (when (and parent frame agents selection footer confirm
               (or include-hidden? (and (panel:Visible) (parent:Visible))))
      {: panel : parent
       : frame : agents
       :native-capacity (find_uicomponent parent :dy_agent_cap)
       :capacity (find_uicomponent parent :everchosen_hero_families
                   :everchosen_hero_capacity)
       :load-character (find_uicomponent panel :footer :button_load_character)
       : confirm
       :raise (find_uicomponent panel :footer :button_raise)
       : footer
       :blocked (find_uicomponent panel :footer
                  :everchosen_hero_confirm_blocked)
       :private (find_uicomponent parent :everchosen_hero_families)
       : selection
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
    :ui/everchosen/hero_families controls.parent)
  (core:get_or_create_component :everchosen_hero_confirm_blocked
    :ui/everchosen/hero_confirm_blocked controls.footer))

(fn reserve-frame [controls state]
  ;; Prepare once on opening; neither family nor settlement cycling resizes it.
  (when controls.native-capacity
    ;; Native selection callbacks own the class counter, even between frames.
    (set state.capacity-opacity (controls.native-capacity:Opacity))
    (controls.native-capacity:SetOpacity 0))
  (set state.frame-height (controls.frame:Height))
  (set state.header-height (controls.parent:Height))
  (set state.agents-height (controls.agents:Height))
  (common.call_context_command
    (.. frame-context ".ListLayoutContext.SetSizeToContents(false)"))
  (controls.frame:Resize (controls.frame:Width)
    (+ state.frame-height (- header-height state.header-height)))
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(false)"))
  ;; Native ResizeToFitTarget reads this hidden list's height on selection.
  (controls.agents:Resize 810 header-height)
  (controls.parent:Resize 810 header-height)
  (when controls.load-character
    (set state.load-character
      {:address (controls.load-character:Address)
       :visible (controls.load-character:Visible)})
    (controls.load-character:SetVisible false)))

(fn show-page [controls entries number pages selected]
  (controls.private:SetVisible true)
  (controls.agents:SetVisible false)
  (for [index 1 (. (world.static-data) :hero_recruitment :page_size)]
    (let [button (find_uicomponent controls.private (.. prefix "slot_" index))
          group (. entries index)]
      (button:SetVisible (not (not group)))
      (when group
        (: (find_uicomponent button :label) :SetStateText
           (common.get_localised_string group.name-key))
        (: (find_uicomponent button :icon) :SetImagePath group.icon 0)
        (button:SetTooltipText
          (common.get_localised_string group.description-key) "" true)
        (button:SetState (if (= group.key selected) :selected :active)))))
  (: (find_uicomponent controls.private :everchosen_hero_page) :SetStateText
     (string.format (common.get_localised_string :everchosen_hero_page)
                    number pages))
  (: (find_uicomponent controls.private :everchosen_hero_prev)
     :SetState (if (> number 1) :active :inactive))
  (: (find_uicomponent controls.private :everchosen_hero_next)
     :SetState (if (< number pages) :active :inactive)))

(fn release-buttons [controls state]
  (each [id saved (pairs state.blocked)]
    (let [button (find_uicomponent controls.footer id)]
      (when (and button (= (button:Address) saved.address))
        (button:SetVisible saved.visible))))
  (set state.blocked {})
  (when controls.blocked (controls.blocked:SetVisible false)))

(fn gate [controls state enabled? reason]
  ;; Only our disabled copy changes state. The native buttons retain all of
  ;; their engine-owned affordability, building, and candidate conditions.
  (if enabled?
      (release-buttons controls state)
      (do
        (each [_ button (ipairs [controls.confirm controls.raise])]
          (when button
            (when (not (. state.blocked (button:Id)))
              (tset state.blocked (button:Id)
                {:address (button:Address) :visible (button:Visible)}))
            (button:SetVisible false)))
        (when controls.blocked
          (let [proxy controls.blocked
                (x y) (controls.confirm:Position)]
            (proxy:Resize (controls.confirm:Width) (controls.confirm:Height))
            (proxy:MoveTo x y)
            (proxy:SetState :inactive)
            (: (find_uicomponent proxy :button_txt) :SetState :inactive)
            (: (find_uicomponent proxy :button_txt) :SetStateText
               (common.get_localised_string :everchosen_hero_recruit_label))
            (proxy:SetTooltipText
              (common.get_localised_string
                (or reason :everchosen_hero_recruit_pending)) "" true)
            (proxy:SetVisible true))))))

(fn block [controls state]
  (controls.selection:SetInteractive false)
  (gate controls state false))

(fn hide-types [controls]
  ;; The native 73x450 column is fixed; mask only its inner button list.
  (when controls.types (controls.types:SetVisible false)))

(fn show-types [controls]
  (when controls.types (controls.types:SetVisible true)))

(fn mask-selection [controls state]
  ;; Keep layout and native callbacks alive while the class default changes.
  (when (= state.selection-opacity nil)
    (set state.selection-opacity (controls.selection:Opacity)))
  (controls.selection:SetOpacity 0))

(fn reveal-selection [controls state]
  (when state.selection-opacity
    (controls.selection:SetOpacity state.selection-opacity)))

(fn restore-types [controls state]
  (each [subtype address (pairs state.hidden)]
    (let [button (and controls.types
                     (find_uicomponent controls.types subtype))]
      (when (and button (= (button:Address) address))
        (button:SetVisible true))))
  (set state.hidden {}))

(fn filter-types [controls state group]
  ;; Read native child visibility in one synchronous, masked update. Restore
  ;; only this family, rather than exposing every other family for a frame.
  (show-types controls)
  (each [subtype address (pairs state.hidden)]
    (when (. group.members subtype)
      (let [button (and controls.types
                       (find_uicomponent controls.types subtype))]
        (when (and button (= (button:Address) address))
          (button:SetVisible true)))
      (tset state.hidden subtype nil)))
  (each [_ button (ipairs (children controls.types))]
    (when (and (. state.native-subtypes (button:Id))
               (not (. group.members (button:Id))) (button:Visible))
      (tset state.hidden (button:Id) (button:Address))
      (button:SetVisible false)))
  (when controls.types (controls.types:Layout))
  (hide-types controls))

(fn selection-matches? [controls group require-candidates?]
  (let [list (find_uicomponent controls.selection :character_list :list_box)
        cards (icollect [_ card (ipairs (children list))]
                (when (card:Visible) card))]
    (and (or (not require-candidates?) (> (length cards) 0))
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

(fn matches? [controls group]
  "Require a matching selected subtype and a nonempty matching candidate list."
  (selection-matches? controls group true))

(fn settled? [controls group]
  "Allow an empty pool, but never show another family's native candidates."
  (selection-matches? controls group false))

(fn show-capacity [controls state group snapshot]
  (when controls.capacity
    (controls.capacity:SetState
      (if (>= snapshot.used snapshot.limit) :maxed :NewState))
    (controls.capacity:SetStateText
      (string.format "%d/%d" snapshot.used snapshot.limit))
    (controls.capacity:SetTooltipText
      (common.get_localised_string group.description-key) "" true)
    (controls.capacity:SetVisible true)))

(fn close [controls state]
  ;; A queued native hire may still read its selected subtype after closing.
  ;; Restore those buttons on the next open, never while submitting the hire.
  (when controls.private (controls.private:SetVisible false))
  (when controls.native-capacity
    (controls.native-capacity:SetOpacity state.capacity-opacity))
  (controls.agents:SetVisible true)
  (controls.selection:SetInteractive true)
  (reveal-selection controls state)
  (show-types controls)
  (release-buttons controls state)
  (when (and controls.load-character state.load-character
             (= (controls.load-character:Address) state.load-character.address))
    (controls.load-character:SetVisible state.load-character.visible))
  (controls.parent:Resize 810 state.header-height)
  (controls.agents:Resize 810 state.agents-height)
  (controls.frame:Resize (controls.frame:Width) state.frame-height)
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(true)"))
  (common.call_context_command
    (.. frame-context ".ListLayoutContext.SetSizeToContents(true)")))

{: controls : children : clicked? : create : reserve-frame : show-page
 : gate : block : hide-types : show-types : restore-types : filter-types
 : matches? : settled? : mask-selection : reveal-selection : show-capacity
 : close}
