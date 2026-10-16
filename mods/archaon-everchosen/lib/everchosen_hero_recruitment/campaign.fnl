(local world (include :everchosen_core.world))
(local rules (include :everchosen_hero_recruitment.rules))
(local view (include :everchosen_hero_recruitment.view))
(local capacity-data (include :everchosen_hero_capacity.data))

(local prefix "everchosen_hero_")

;; Only the current panel and its outstanding native selection live here.
(var session nil)
;; A closed or rebuilt panel invalidates all its delayed UI commands.
(var generation 0)
;; One native private-page recruitment command may await its creation event.
(var recruiting nil)

(fn current? [state]
  (and state (= session state) (= state.generation generation)
       (world.host) (view.controls)))

(fn capacity []
  (assert (core:get_static_object capacity-data.provider)))

(fn config []
  (assert (core:get_static_object capacity-data.config)))

(fn group-by-key [state key]
  (accumulate [found nil _ group (ipairs state.groups) &until found]
    (when (= group.key key) group)))

(fn selected-class [controls]
  (accumulate [found nil agent _ (pairs (. (config) :native_page))
               &until found]
    (let [button (find_uicomponent controls.agents agent)]
      (when (and button (rules.selected? (button:CurrentState))) agent))))

(fn run [callback argument]
  (let [(ok? error) (pcall callback argument)]
    (when (not ok?)
      (set generation (+ generation 1))
      (when session
        (let [controls (view.controls true)]
          (when controls (view.block controls))))
      (out (.. "[Everchosen hero recruitment] " (tostring error))))))

(fn later [callback state delay]
  (cm:callback #(when (current? state) (run callback state)) delay))

(fn render [state]
  (let [controls (view.controls)
        private (icollect [_ group (ipairs state.groups)]
                  (when group.private? group))
        size (. (world.static-data) :hero_recruitment :page_size)
        (entries page pages) (rules.page private state.page size)]
    (set state.page page)
    (set state.page-entries entries)
    (view.native-labels controls state.groups state)
    (view.show-page controls entries page pages state.selected state.private?)))

(fn refresh-gate [state]
  (when (current? state)
    (let [controls (view.controls)
          group (group-by-key state state.selected)
          provider (capacity)
          snapshot (and group (provider.snapshot group.subtypes))]
      (when snapshot (view.show-capacity controls state group snapshot))
      (view.gate controls
        (and (not state.busy?) (not recruiting) (not (provider.pending))
             (provider.ready) snapshot (< snapshot.used snapshot.limit)
             (= (selected-class controls) group.agent)
             (view.matches? controls group))))))

(fn finish-selection [state]
  (when (and (current? state) (not ((. (capacity) :pending))))
    (let [controls (view.controls)
          group (group-by-key state state.selected)]
      (view.filter-types controls state group)
      (set state.busy? false)
      (set state.phase nil)
      (controls.selection:SetInteractive true)
      (refresh-gate state)
      (render state))))

(fn choose-subtype [state]
  (when (current? state)
    (let [controls (view.controls)
          group (group-by-key state state.selected)
          candidates
          (icollect [_ subtype (ipairs group.subtypes)]
            (let [button (and controls.types
                             (find_uicomponent controls.types subtype))]
              (when (and button (button:Visible)
                         (rules.selectable? (button:CurrentState)))
                button)))
          selected
          (or (accumulate [found nil _ button (ipairs candidates)
                           &until found]
                (when (rules.selected? (button:CurrentState)) button))
              (. candidates 1))]
      (view.filter-types controls state group)
      (when (and selected (not (rules.selected? (selected:CurrentState))))
        (selected:SimulateLClick))
      (set state.phase :finish)
      ;; Return to native rules only after its retained subtype is selected.
      (when (not state.private?) ((. (capacity) :set-private) false))
      (if selected
          (later finish-selection state 0.1)
          (do
            (set state.busy? false)
            (controls.selection:SetInteractive true)
            (view.gate controls false)
            (: (find_uicomponent controls.private :everchosen_hero_page)
               :SetStateText
               (common.get_localised_string :everchosen_hero_unavailable)))))))

(fn navigate-family [state]
  (when (current? state)
    (if ((. (capacity) :pending))
        (later navigate-family state 0.1)
        (let [group (group-by-key state state.selected)
              controls (view.controls)
              button (find_uicomponent controls.agents group.agent)]
          (assert ((. (capacity) :ready))
                  "Native hero capacity has not been verified")
          (view.restore-types controls state)
          (if (and button
                   (or (rules.selectable? (button:CurrentState))
                       (rules.selected? (button:CurrentState))))
              (do
                (when (not (rules.selected? (button:CurrentState)))
                  ;; Native callbacks own the pool, costs, portraits and traits.
                  (controls.agents:SetVisible true)
                  (button:SimulateLClick)
                  (controls.agents:SetVisible (not state.private?)))
                (set state.phase :subtype)
                (later choose-subtype state 0.1))
              (do
                (set state.busy? false)
                (view.gate controls false)))))))

(fn select-family [state group]
  (when (and (current? state) group (not state.busy?))
    (set state.selected group.key)
    (set state.busy? true)
    (set state.phase :class)
    (view.block (view.controls))
    (when state.private? ((. (capacity) :set-private) true))
    (render state)
    (navigate-family state)))

(fn native-group [state agent]
  (group-by-key state (. (config) :native_page agent)))

(fn change-mode [state]
  (let [group (group-by-key state state.selected)]
    (if state.private?
        (do
          (set state.private? false)
          (select-family state (native-group state group.agent)))
        (let [private
              (or (group-by-key state state.last-private)
                  (accumulate [found nil _ candidate (ipairs state.groups)
                               &until found]
                    (when candidate.private? candidate)))]
          (set state.private? true)
          (select-family state private)))))

(fn initialise-selection [state]
  (when (current? state)
    (let [controls (view.controls)
          agent (or (selected-class controls)
                    (accumulate [found nil candidate _
                                 (pairs (. (config) :native_page))
                                 &until found]
                      (let [button
                            (find_uicomponent controls.agents candidate)]
                        (when (and button
                                   (rules.selectable? (button:CurrentState)))
                          candidate))))]
      (when agent (select-family state (native-group state agent))))))

(fn begin []
  (when (world.host)
    (let [controls (view.controls)]
      (when controls
        (when session (view.restore controls session))
        (view.create controls)
        (let [groups (rules.catalog (. (config) :families))]
          (set session
            {: groups :page 1 :hidden {} :labels {} :private? false
             :generation generation :busy? false
             :native-subtypes
             (collect [subtype _ (pairs (. (config) :subtypes))]
               (values subtype true))}))
        (view.reserve-frame controls session)
        (view.block controls)
        (render session)
        (later initialise-selection session 0.05)))))

(fn close []
  (set generation (+ generation 1))
  (when session
    (let [closed session
          controls (view.controls true)]
      (set session nil)
      (when controls (view.restore controls closed))
      ((. (capacity) :set-private) false))))

(fn request []
  (set generation (+ generation 1))
  (let [controls (view.controls)]
    (when controls (view.block controls)))
  (let [ticket generation]
    (cm:callback #(when (= ticket generation) (run begin nil)) 0.1)))

(fn click [context]
  (when (and (current? session) (not session.busy?))
    (let [id context.string
          controls (view.controls)
          slot (tonumber (string.match id "^everchosen_hero_slot_(%d+)$"))]
      (if (and (= id :everchosen_hero_mode)
               (view.clicked? controls.private context))
          (change-mode session)
          (and session.private? slot (view.clicked? controls.private context))
          (let [group (. session.page-entries slot)]
            (when group
              (set session.last-private group.key)
              (select-family session group)))
          (and session.private? (= id :everchosen_hero_prev)
               (view.clicked? controls.private context))
          (do (set session.page (- session.page 1)) (render session))
          (and session.private? (= id :everchosen_hero_next)
               (view.clicked? controls.private context))
          (do (set session.page (+ session.page 1)) (render session))
          (and (not session.private?) (. (config) :native_page id)
               (view.clicked? controls.agents context))
          (select-family session (native-group session id))
          (and (or (= id :button_cycle_left) (= id :button_cycle_right))
               (view.clicked? (find_uicomponent controls.panel :footer) context))
          (request)
          (and session.private?
               (or (= id :button_confirm) (= id :button_raise))
               (view.clicked? (find_uicomponent controls.panel :footer) context))
          (do
            ;; A synchronous creation event may already have queued refresh.
            (when (not ((. (capacity) :pending)))
              (set recruiting
                (. (group-by-key session session.selected) :members)))
            (view.block controls))
          (do
            (refresh-gate session)
            (later refresh-gate session 0.05))))))

(fn capacity-updating []
  (when (current? session) (view.block (view.controls))))

(fn capacity-ready []
  (when (current? session)
    (if (= session.phase :finish)
        (finish-selection session)
        (not session.phase)
        (do
          (: (. (view.controls) :selection) :SetInteractive true)
          (refresh-gate session)
          (render session)))))

(fn recruited [context]
  (when (and recruiting
             (. recruiting (: (context:character) :character_subtype_key)))
    (set recruiting nil))
  (when (current? session)
    ;; The creation event disables the next click before a delayed cap refresh.
    (view.block (view.controls))
    (later refresh-gate session 0.1)))

(fn turn-start []
  ;; A normal hire is immediate; no UI command remains pending next own turn.
  (when recruiting
    (when (current? session) (view.block (view.controls)))
    (set recruiting nil)
    ((. (capacity) :request))))

(fn hover [context]
  (when (and (current? session)
             (or (= context.string :button_confirm)
                 (= context.string :button_raise)))
    (refresh-gate session)))

(fn start []
  (when (and (world.host)
             (not (core:get_static_object capacity-data.ui-controller)))
    (core:add_static_object capacity-data.ui-controller true)
    (core:add_listener (.. prefix "capacity_updating")
      capacity-data.updating true #(run capacity-updating nil) true)
    (core:add_listener (.. prefix "capacity_ready")
      capacity-data.ready true #(run capacity-ready nil) true)
    (core:add_listener (.. prefix "capacity_failed")
      capacity-data.failed true #(run capacity-updating nil) true)
    (core:add_listener (.. prefix "opened") :PanelOpenedCampaign
      #(= $1.string :character_panel) #(run request nil) true)
    (core:add_listener (.. prefix "closed") :PanelClosedCampaign
      #(= $1.string :character_panel) #(run close nil) true)
    (core:add_listener (.. prefix "click") :ComponentLClickUp true
      #(run click $1) true)
    (core:add_listener (.. prefix "hover") :ComponentMouseOn true
      #(run hover $1) true)
    (core:add_listener (.. prefix "recruited") :CharacterRecruited
      #(world.host? (: ($1:character) :faction)) #(run recruited $1) true)
    (core:add_listener (.. prefix "turn_start") :FactionTurnStart
      #(world.host? ($1:faction)) #(run turn-start nil) true)))

{: start}
