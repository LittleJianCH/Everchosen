(local world (include :everchosen_core.world))
(local rules (include :everchosen_hero_recruitment.rules))
(local view (include :everchosen_hero_recruitment.view))

(local prefix "everchosen_hero_")

;; Only the current panel's navigation and in-flight UI commands live here.
(var session nil)
;; Guards listener registration within this script session.
(var started? false)
;; Invalidates delayed panel-open requests when the panel closes or refreshes.
(var generation 0)
;; The next class is selected only after the previous native update is read.
(var collect-class nil)

(fn current? [state]
  (and state (= session state) (world.host) (view.controls)))

(fn restore-session [state]
  (let [controls (view.controls true)]
    (when controls (view.restore controls state))))

(fn run [callback argument]
  (let [(ok? error) (pcall callback argument)]
    (when (not ok?)
      ;; A failed UI command must not leave the native page masked.
      (let [failed-state session]
        (set session nil)
        (set generation (+ generation 1))
        (when failed-state
          (let [(restored? cleanup-error) (pcall restore-session failed-state)]
            (when (not restored?)
              (out (.. "[Everchosen hero recruitment] UI cleanup: "
                       (tostring cleanup-error)))))))
      (out (.. "[Everchosen hero recruitment] " (tostring error))))))

(fn later [callback state delay]
  (cm:callback #(when (current? state) (run callback state)) delay))

(fn render [state]
  (let [controls (view.controls)
        size (. (world.static-data) :hero_recruitment :page_size)
        (entries page pages) (rules.page state.groups state.page size)]
    (set state.page page)
    (set state.page-entries entries)
    (view.show-page controls entries page pages state.selected)))

(fn selected-group [state]
  (accumulate [found nil _ group (ipairs state.groups) &until found]
    (when (= group.key state.selected) group)))

(fn finish-selection [state]
  (when (current? state)
    (let [controls (view.controls)
          group (selected-group state)]
      (view.reserve controls)
      (view.filter-types controls state group)
      (if (and (= (: (find_uicomponent controls.agents group.agent)
                     :CurrentState) :selected)
               (view.matches? controls group))
          (view.unblock controls state)
          (out (.. "[Everchosen hero recruitment] Native candidates did not "
                   "match " group.key "; recruitment remains hidden")))
      (set state.busy? false)
      (render state))))

(fn choose-subtype [state]
  (when (current? state)
    (let [controls (view.controls)
          group (selected-group state)
          candidates
          (icollect [_ subtype (ipairs group.subtypes)]
            (let [button (and controls.types
                             (find_uicomponent controls.types subtype))]
              (when (and button (button:Visible)
                         (rules.selectable? (button:CurrentState)))
                button)))
          selected
          (or (accumulate [selected nil _ button (ipairs candidates)
                           &until selected]
                (when (= (button:CurrentState) :selected) button))
              (. candidates 1))]
      (view.filter-types controls state group)
      (if (or group.native? selected)
          (do
            (view.unblock controls state)
            (when selected (selected:SimulateLClick))
            (view.block controls state)
            (later finish-selection state 0.1))
          (do
            (set state.busy? false)
            (: (find_uicomponent controls.private :everchosen_hero_page)
               :SetStateText
               (common.get_localised_string :everchosen_hero_unavailable))
            (out (.. "[Everchosen hero recruitment] No selectable subtype: "
                     group.key)))))))

(fn select-family [state group]
  (when (and (current? state) group (not group.disabled?)
             (not state.busy?))
    (let [controls (view.controls)
          agent (find_uicomponent controls.agents group.agent)]
      (when (rules.selectable? (agent:CurrentState))
        (set state.selected group.key)
        (set state.busy? true)
        (view.restore-types controls state)
        (view.unblock controls state)
        ;; Restore visibility for the native click, retaining its disabled state.
        (controls.agents:SetVisible true)
        (agent:SimulateLClick)
        (view.block controls state)
        (view.reserve controls)
        (render state)
        (later choose-subtype state 0.1)))))

(fn complete-catalog [state]
  (let [config (. (world.static-data) :hero_recruitment)]
    (set state.groups (rules.catalog state.members config.subtypes))
    ;; A native class with no subtype controls still retains its own entry.
    (each [_ agent (ipairs state.agents)]
      (when (not (. state.observed agent))
        (let [controls (view.controls)
              button (find_uicomponent controls.agents agent)
              name (: (find_uicomponent button :label) :GetStateText)]
          (table.insert state.groups
            {:key (.. "native:" agent) : agent : name :native? true
             :disabled? (not (rules.selectable? (button:CurrentState)))
             :icon (. config.icons agent) :subtypes [] :members {}}))))
    (set state.busy? false)
    (render state)
    (let [preferred
          (or (accumulate [found nil _ group (ipairs state.groups)
                           &until found]
                (when (and (not group.disabled?)
                           (or (= group.key state.preferred)
                               (. group.members state.initial-subtype)))
                  group))
              (accumulate [found nil _ group (ipairs state.groups)
                           &until found]
                (when (not group.disabled?) group)))]
      (if preferred (select-family state preferred)
          (view.unblock (view.controls) state)))
    (out (.. "[Everchosen hero recruitment] Catalogued "
             (length state.groups) " hero families"))))

(fn scan-class [state]
  (when (current? state)
    (if (> state.index (length state.agents))
        (complete-catalog state)
        (let [controls (view.controls)
              agent (. state.agents state.index)
              button (find_uicomponent controls.agents agent)]
          (view.restore-types controls state)
          (view.unblock controls state)
          (controls.agents:SetVisible true)
          (when (rules.selectable? (button:CurrentState))
            (button:SimulateLClick))
          (view.block controls state)
          (view.reserve controls)
          (later collect-class state 0.05)))))

(set collect-class
  (fn [state]
    (when (current? state)
      (let [controls (view.controls)
            agent (. state.agents state.index)]
        (each [_ button (ipairs (view.children controls.types))]
          (when (and (= (: (find_uicomponent controls.agents agent)
                            :CurrentState) :selected)
                     (button:Visible)
                     (= (button:GetProperty :agent_type_key) agent))
            (let [subtype (button:Id)
                  config (. (world.static-data) :hero_recruitment)
                  meta (. config.subtypes subtype)
                  record (when (not meta) (cco :CcoAgentSubtypeRecord subtype))
                  name (when record (record:Call :OnscreenNameOverride))
                  icon (when record (record:Call :SmallIcon))]
              (table.insert state.members
                {: agent : subtype
                 :name (if (and name (not= name "")) name
                           (: (find_uicomponent
                                (find_uicomponent controls.agents agent)
                                :label) :GetStateText))
                 :icon (if (and icon (not= icon "")) icon
                           (. config.icons agent))})
              (tset state.observed agent true))))
        (set state.index (+ state.index 1))
        (scan-class state)))))

(fn begin []
  (when (world.host)
    (let [controls (view.controls)]
      (when controls
        (let [preferred (and session session.selected)]
          (when session (view.restore controls session))
          (view.create controls)
          (set session
            {: preferred :groups [] :members [] :observed {}
             :hidden {} :index 1 :page 1 :busy? true
             :initial-subtype
             (accumulate [selected nil _ button
                          (ipairs (view.children controls.types))
                          &until selected]
               (when (= (button:CurrentState) :selected) (button:Id)))
             :agents
             (icollect [_ button (ipairs (view.children controls.agents))]
               (let [agent (button:GetProperty :agent_type_key)]
                 (when (and agent (not= agent "")) agent)))})
          (let [controls (view.controls)]
            (controls.private:SetVisible true)
            (render session)
            (: (find_uicomponent controls.private :everchosen_hero_page)
               :SetStateText
               (common.get_localised_string :everchosen_hero_loading)))
          (scan-class session))))))

(fn close []
  (set generation (+ generation 1))
  (when session
    (let [closed-state session]
      (set session nil)
      (restore-session closed-state))))

(fn request []
  (close)
  (let [ticket generation]
    (cm:callback #(when (= ticket generation) (run begin nil)) 0.2)))

(fn click [context]
  (when (and session (not session.busy?) (current? session))
    (let [id context.string
          controls (view.controls)
          slot (tonumber (string.match id "^everchosen_hero_slot_(%d+)$"))
          group (selected-group session)]
      (if (and slot (view.clicked? controls.private context))
          (select-family session (. session.page-entries slot))
          (and (= id :everchosen_hero_prev)
               (view.clicked? controls.private context))
          (do (set session.page (- session.page 1)) (render session))
          (and (= id :everchosen_hero_next)
               (view.clicked? controls.private context))
          (do (set session.page (+ session.page 1)) (render session))
          (and (or (= id :button_cycle_left) (= id :button_cycle_right)
                   (= id :button_confirm))
               (view.clicked?
                 (find_uicomponent controls.panel :footer) context))
          (request)
          (and group (. group.members id)
               (view.clicked? controls.types context))
          (let [state session]
            (later finish-selection state 0.1))))))

(fn start []
  (when (and (world.host) (not started?))
    (set started? true)
    (core:add_listener (.. prefix "opened") :PanelOpenedCampaign
      #(= $1.string :character_panel)
      #(run request nil) true)
    (core:add_listener (.. prefix "closed") :PanelClosedCampaign
      #(= $1.string :character_panel)
      #(run close nil) true)
    (core:add_listener (.. prefix "click") :ComponentLClickUp true
      #(run click $1) true)))

{: start}
