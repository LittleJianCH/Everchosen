(local world (include :everchosen_core.world))

(local prefix "everchosen_hero_")
(local list-context
  (.. "RootComponent.ChildContext(\"character_panel\")"
      ".ChildContext(\"agent_parent\").ChildContext(\"list_box\")"))

(fn controls [include-hidden?]
  "Re-query native controls instead of keeping UI objects across callbacks."
  (let [panel (find_uicomponent (core:get_ui_root) :character_panel)
        parent (and panel (find_uicomponent panel :lords_and_agents_holder
                                            :agent_parent))]
    (when (and parent
               (or include-hidden? (and (panel:Visible) (parent:Visible))))
      {: panel : parent
       :agents (find_uicomponent parent :list_box)
       :private (find_uicomponent parent :everchosen_hero_families)
       :selection (find_uicomponent panel :general_selection_panel)
       :types (find_uicomponent panel :general_selection_panel
                :lore_select_parent :wizard_type :type_list)})))

(fn children [parent]
  "Read one known UI list; this does not traverse the rest of the UI tree."
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

(fn reserve [controls]
  ;; ResizeToFitTarget keeps the native header aligned to its list_box.
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(false)"))
  (controls.agents:Resize 810 122)
  (controls.parent:Resize 810 122)
  (controls.agents:SetVisible false))

(fn create [controls]
  (core:get_or_create_component :everchosen_hero_families
    :ui/everchosen/hero_families controls.parent))

(fn show-page [controls entries number pages selected]
  (let [private controls.private
        config (. (world.static-data) :hero_recruitment)]
    (for [index 1 config.page_size]
      (let [button (find_uicomponent private (.. prefix "slot_" index))
            group (. entries index)]
        (button:SetVisible (not (not group)))
        (when group
          (let [name (if group.name-key
                         (common.get_localised_string group.name-key)
                         group.name)]
            (: (find_uicomponent button :label) :SetStateText name)
            (: (find_uicomponent button :icon) :SetImagePath group.icon 0)
            (button:SetTooltipText
              (.. name "\n" (common.get_localised_string
                               :everchosen_hero_shared_capacity)) "" true)
            (button:SetState (if group.disabled? :inactive
                                (= group.key selected) :selected
                                :active))))))
    (: (find_uicomponent private :everchosen_hero_page) :SetStateText
       (string.format (common.get_localised_string :everchosen_hero_page)
                      number pages))
    (: (find_uicomponent private :everchosen_hero_prev)
       :SetState (if (> number 1) :active :inactive))
    (: (find_uicomponent private :everchosen_hero_next)
       :SetState (if (< number pages) :active :inactive))))

(fn block [controls state]
  ;; Hide parent containers during native navigation. Individual confirmation
  ;; buttons keep the visibility/enabled state last assigned by the engine.
  (when (not state.blocked)
    (set state.blocked
      (icollect [_ id (ipairs [:general_selection_panel :footer])]
        (let [part (find_uicomponent controls.panel id)]
          {: id :address (part:Address) :visible (part:Visible)}))))
  (each [_ saved (ipairs state.blocked)]
    (: (find_uicomponent controls.panel saved.id) :SetVisible false)))

(fn unblock [controls state]
  (each [_ saved (ipairs (or state.blocked []))]
    (let [part (find_uicomponent controls.panel saved.id)]
      (when (= (part:Address) saved.address)
        (part:SetVisible saved.visible))))
  (set state.blocked nil))

(fn restore-types [controls state]
  ;; Restore only buttons hidden by this selector, leaving other mods' gates.
  (each [subtype address (pairs state.hidden)]
    (let [button (and controls.types
                     (find_uicomponent controls.types subtype))]
      (when (and button (= (button:Address) address))
        (button:SetVisible true))))
  (set state.hidden {}))

(fn filter-types [controls state group]
  (restore-types controls state)
  (each [_ button (ipairs (children controls.types))]
    (when (and (= (button:GetProperty :agent_type_key) group.agent)
               (not (. group.members (button:Id))) (button:Visible))
      (tset state.hidden (button:Id) (button:Address))
      (button:SetVisible false)))
  (when controls.types (controls.types:Layout)))

(fn matches? [controls group]
  "Require a native selected subtype and verifiable, matching candidate cards."
  (let [list (find_uicomponent controls.selection :character_list :list_box)]
    (and (or group.native?
             (accumulate [selected false _ button
                          (ipairs (children controls.types)) &until selected]
               (and (. group.members (button:Id))
                    (or (= (button:CurrentState) :selected)
                        (= (button:CurrentState) :selected_inactive)))))
         (accumulate [matches true _ card (ipairs (children list))
                      &until (not matches)]
           (if (card:Visible)
               (let [character (card:GetContextObject :CcoCampaignCharacter)]
                 (and character
                      (if group.native?
                          (= (character:Call :AgentRecordContext.Key)
                             group.agent)
                          (. group.members
                             (character:Call :AgentSubtypeRecordContext.Key)))))
               true)))))

(fn restore [controls state]
  (restore-types controls state)
  (unblock controls state)
  (when controls.private (controls.private:SetVisible false))
  (controls.agents:SetVisible true)
  (common.call_context_command
    (.. list-context ".ListLayoutContext.SetSizeToContents(true)"))
  (controls.agents:Layout))

{: controls : children : clicked? : reserve : create : show-page : block : unblock
 : restore-types : filter-types : matches? : restore}
