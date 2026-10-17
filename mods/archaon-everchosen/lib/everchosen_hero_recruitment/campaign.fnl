(local world (include :everchosen_core.world))
(local rules (include :everchosen_hero_recruitment.rules))
(local view (include :everchosen_hero_recruitment.view))
(local capacity-data (include :everchosen_hero_capacity.data))

(local prefix "everchosen_hero_")

;; The live panel and its previous hidden instance retain their fixed layout.
(var session nil)
(var closed-session nil)
;; Delayed native selection commands belong to one panel generation.
(var generation 0)
;; One native recruitment command may await its character creation event.
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

(fn same-panel? [state controls]
  (and state (= state.address (controls.panel:Address))
       (= state.frame (controls.frame:Address))
       (= state.parent (controls.parent:Address))))

(fn selected-class [controls]
  (accumulate [found nil agent _ (pairs (. (config) :classes))
               &until found]
    (let [button (find_uicomponent controls.agents agent)]
      (when (and button (rules.selected? (button:CurrentState))) agent))))

(fn run [callback argument]
  (let [(ok? error) (pcall callback argument)]
    (when (not ok?)
      (set generation (+ generation 1))
      (when session
        (let [controls (view.controls true)]
          (when controls
            (view.hide-types controls)
            (view.block controls session))))
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

(fn refresh-gate [state]
  (when (current? state)
    (let [controls (view.controls)
          group (group-by-key state state.selected)
          provider (capacity)
          snapshot (and group (provider.snapshot group.subtypes))
          full? (and snapshot (>= snapshot.used snapshot.limit))]
      (when snapshot (view.show-capacity controls state group snapshot))
      (view.gate controls state
        (and (not state.busy?) (not recruiting) (not (provider.pending))
             (provider.ready) snapshot (not full?)
             (= (selected-class controls) group.agent)
             (view.matches? controls group))
        (when full? :everchosen_hero_capacity_full)))))

(fn finish-selection [state]
  (when (and (current? state) (not ((. (capacity) :pending))))
    (let [controls (view.controls)
          group (group-by-key state state.selected)]
      (view.filter-types controls state group)
      (if (view.settled? controls group)
          (do
            (view.show-types controls)
            (view.reveal-selection controls state)
            (set state.busy? false)
            (set state.phase nil)
            (controls.selection:SetInteractive true)
            (refresh-gate state)
            (render state))
          (later finish-selection state 0.1)))))

(fn choose-subtype [state]
  (when (current? state)
    (let [controls (view.controls)
          group (group-by-key state state.selected)
          _ (do (view.filter-types controls state group)
                (view.show-types controls))
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
      (when (and selected (not (rules.selected? (selected:CurrentState))))
        (selected:SimulateLClick))
      (view.hide-types controls)
      (set state.phase :finish)
      (if selected
          (later finish-selection state 0.1)
          (do
            (set state.busy? false)
            (view.show-types controls)
            (controls.selection:SetInteractive true)
            (view.gate controls state false :everchosen_hero_unavailable)
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
          (view.filter-types controls state group)
          (if (and button
                   (or (rules.selectable? (button:CurrentState))
                       (rules.selected? (button:CurrentState))))
              (do
                (when (not (rules.selected? (button:CurrentState)))
                  ;; Preserve the native pool, portraits, traits and hire command.
                  (controls.agents:SetVisible true)
                  (button:SimulateLClick)
                  (controls.agents:SetVisible false))
                (view.hide-types controls)
                (set state.phase :subtype)
                (later choose-subtype state 0.1))
              (do
                (set state.busy? false)
                (view.gate controls state false)))))))

(fn select-family [state group]
  (when (and (current? state) group (not state.busy?))
    (set state.selected group.key)
    (set state.busy? true)
    (set state.phase :class)
    (view.block (view.controls) state)
    (view.mask-selection (view.controls) state)
    (view.hide-types (view.controls))
    (render state)
    (refresh-gate state)
    (navigate-family state)))

(fn initialise-selection [state]
  (when (current? state)
    (let [controls (view.controls)
          selected
          (or (group-by-key state state.selected)
              (accumulate [found nil _ button
                           (ipairs (view.children controls.types))
                           &until found]
                (when (rules.selected? (button:CurrentState))
                  (let [record (. (config) :subtypes (button:Id))]
                    (when record (group-by-key state record.family)))))
              (group-by-key state :wh_main_chs_exalted_hero)
              (. state.groups 1))]
      (set state.page
        (accumulate [page 1 index group (ipairs state.groups)]
          (if (= group.key selected.key)
              (math.ceil
                (/ index (. (world.static-data) :hero_recruitment :page_size)))
              page)))
      (select-family state selected))))

(fn begin []
  (when (world.host)
    (let [all-controls (view.controls true)
          controls (view.controls)
          previous (or session closed-session)]
      (if controls
          (do
            (if (same-panel? previous controls)
                (do
                  (set session previous)
                  (set session.generation generation)
                  (set session.busy? false)
                  (set session.phase nil))
                (do
                  (view.create controls)
                  (let [groups (rules.catalog (. (config) :families))]
                    (set session
                      {: groups :page 1 :hidden {} :blocked {}
                       :generation generation :busy? false
                       :address (controls.panel:Address)
                       :frame (controls.frame:Address)
                       :parent (controls.parent:Address)
                       :confirmers
                       (collect [_ button
                                 (ipairs [controls.confirm controls.raise])]
                         (values (button:Address) true))
                       :native-subtypes
                       (accumulate
                         [known (collect [subtype _
                                          (pairs (. (config) :subtypes))]
                                  (values subtype true))
                          _ family (pairs (. (config) :families))]
                         (do
                           (each [_ subtype
                                  (ipairs family.promoted_subtypes)]
                             (tset known subtype true))
                           known))}))
                  (view.reserve-frame controls session)))
            (set closed-session nil)
            (view.hide-types controls)
            (view.block controls session)
            (render session)
            (initialise-selection session)
            true)
          (when (and all-controls (same-panel? previous all-controls))
            ;; The next native lord view may share the outer panel components.
            (view.restore-types all-controls previous)
            (view.close all-controls previous)
            (set session nil)
            (set closed-session nil))))))

(fn close []
  (set generation (+ generation 1))
  (when session
    ;; Do not alter native selected subtype/card context while its queued hire
    ;; processes the click. Reuse or clean this hidden layout at the next open.
    (set closed-session session)
    (set session nil)))

(fn request []
  (set generation (+ generation 1))
  (when (not (begin))
    (let [ticket generation]
      ;; Some native callbacks create the controls just after PanelOpened.
      (cm:callback #(when (= ticket generation) (run begin nil)) 0.1))))

(fn confirmation [context]
  (let [state (or session closed-session)]
    (when (and state
               (or (= context.string :button_confirm)
                   (= context.string :button_raise))
               (. state.confirmers
                  (: (UIComponent context.component) :Address)))
      (let [group (group-by-key state state.selected)
            provider (capacity)
            snapshot (provider.snapshot group.subtypes)
            host (world.host)]
        (out (.. "[Everchosen hero recruitment] Confirm " group.key
                 " used=" (tostring (and snapshot snapshot.used))
                 " limit=" (tostring (and snapshot snapshot.limit))
                 " class=" group.agent
                 " cap=" (tostring (and host (host:agent_cap group.agent)))))
        ;; The creation event may already have synchronously queued refresh.
        (when (not (provider.pending)) (set recruiting group.members))
        ;; The compiled native callback may still read this button's state.
        ;; Defer our visual gate until the current click has finished dispatch.
        (when (current? session) (later refresh-gate session 0.05))
        true))))

(fn click [context]
  (when (not (confirmation context))
    (when (and (current? session) (not session.busy?))
      (let [id context.string
            controls (view.controls)
            slot (tonumber (string.match id "^everchosen_hero_slot_(%d+)$"))]
        (if (and slot (view.clicked? controls.private context))
            (select-family session (. session.page-entries slot))
            (and (= id :everchosen_hero_prev)
                 (view.clicked? controls.private context))
            (do (set session.page (- session.page 1)) (render session))
            (and (= id :everchosen_hero_next)
                 (view.clicked? controls.private context))
            (do (set session.page (+ session.page 1)) (render session))
            (and (or (= id :button_cycle_left) (= id :button_cycle_right))
                 (view.clicked? controls.footer context))
            (request)
            (do
              (refresh-gate session)
              (later refresh-gate session 0.05)))))))

(fn capacity-updating []
  (when (current? session) (view.block (view.controls) session)))

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
  (let [subtype (: (context:character) :character_subtype_key)]
    (when (. (config) :subtypes subtype)
      (out (.. "[Everchosen hero recruitment] CharacterRecruited " subtype)))
    (when (and recruiting (. recruiting subtype)) (set recruiting nil)))
  (when (current? session)
    (view.block (view.controls) session)
    (later refresh-gate session 0.1)))

(fn turn-start []
  ;; A normal hire is immediate; no UI command remains pending next own turn.
  (when recruiting
    (when (current? session) (view.block (view.controls) session))
    (set recruiting nil)
    ((. (capacity) :request))))

(fn hover [context]
  (when (and (current? session)
             (or (= context.string :button_confirm)
                 (= context.string :button_raise)
                 (= context.string :everchosen_hero_confirm_blocked)))
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
