;; Native candidate generation, prices and class-cap arithmetic are observed
;; inputs. Only the real recruitment controller and targeted view rules run.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local updating :ScriptEventEverchosenHeroCapacityUpdating)
(local ready :ScriptEventEverchosenHeroCapacityReady)

(fn native-list [children]
  {:ChildCount #(length children)
   :Find (fn [_ index] (. children (+ index 1)))})

(fn scenario [pending?]
  (let [s {:queue [] :listeners {} :logs [] :class-clicks []
           :subtype-clicks [] :enabled? false :pending? pending?
           :prepares 0 :creates 0 :closes 0 :restores 0
           :mutations 0
           :selected-class :wizard :selected-subtype :chaos-fire
           :snapshots {:a-sorcerer {:used 0 :limit 1}
                       :b-alluress {:used 0 :limit 1}
                       :c-shaman {:used 1 :limit 1}
                       :d-castellan {:used 0 :limit 1}}}
        families
        {:a-sorcerer {:agent :wizard :subtypes [:chaos-fire]
                     :promoted_subtypes [:marked-fire]}
         :b-alluress {:agent :engineer :subtypes [:slaanesh]
                     :promoted_subtypes []}
         :c-shaman {:agent :wizard :subtypes [:fire :death]
                   :promoted_subtypes []}
         :d-castellan {:agent :engineer :subtypes [:castellan]
                      :promoted_subtypes []}}
        metadata {:chaos-fire {:family :a-sorcerer}
                  :slaanesh {:family :b-alluress}
                  :fire {:family :c-shaman} :death {:family :c-shaman}
                  :castellan {:family :d-castellan}}
        config {: families :subtypes metadata
                :classes {:wizard :wizard-cap :engineer :engineer-cap}}
        objects {:everchosen_hero_capacity_data config}
        provider {:pending #(not (not s.pending?))
                  :ready #(not s.pending?)
                  :request (fn []
                             (set s.requested? true)
                             (set s.pending? true))
                  :snapshot #(let [record (. metadata (. $1 1))]
                               (. s.snapshots record.family))}
        agents {:kind :agents :SetVisible (fn [])}
        types (collect [_ subtype
                        (ipairs [:chaos-fire :slaanesh :fire :death :castellan])]
                (values subtype
                  {:Id (fn [] subtype) :Visible (fn [] true)
                   :CurrentState #(if (= subtype s.selected-subtype)
                                      :selected :active)
                   :SimulateLClick (fn []
                     (table.insert s.subtype-clicks subtype)
                     (set s.selected-subtype subtype))}))
        confirm {:Address (fn [] 4)}
        controls {: agents : types : confirm :private {:kind :private}
                  :panel {:Address (fn [] 1)}
                  :frame {:Address (fn [] 2)}
                  :parent {:Address (fn [] 3)}
                  :footer {:kind :footer}
                  :selection {:SetInteractive
                              #(set s.mutations (+ s.mutations 1))}}
        host {:agent_cap (fn [] 2)}
        world {:host (fn [] host) :host? (fn [] true)
               :static-data #(do {:hero_recruitment {:page_size 2}})}
        view {:controls (fn [] controls)
              :create #(set s.creates (+ s.creates 1))
              :reserve-frame #(set s.prepares (+ s.prepares 1))
              :close #(set s.closes (+ s.closes 1))
              :restore-types #(set s.restores (+ s.restores 1))
              :filter-types (fn []) :show-capacity (fn [])
              :block (fn []
                       (set s.mutations (+ s.mutations 1))
                       (set s.enabled? false))
              :gate (fn [_ _ enabled? reason]
                      (set s.mutations (+ s.mutations 1))
                      (set s.enabled? (not (not enabled?)))
                      (set s.reason reason))
              :matches? (fn [] true)
              :children (fn [parent]
                          (assert.equals types parent)
                          (icollect [_ subtype
                                     (ipairs [:chaos-fire :slaanesh :fire
                                              :death :castellan])]
                            (. types subtype)))
              :clicked? (fn [parent context] (= parent.kind context.origin))
              :show-page (fn [_ entries page pages selected]
                           (set s.groups entries)
                           (set s.page page)
                           (set s.pages pages)
                           (set s.selected selected))}
        env (setmetatable
          {:package {:preload {} :loaded {}}
           :out #(table.insert s.logs $1)
           :UIComponent (fn [component] component)
           :find_uicomponent
           (fn [parent ...]
             (accumulate [target parent _ id (ipairs [...])]
               (and target (. target id))))
           :common {:get_localised_string (fn [key] key)}
           :core {:get_static_object
                  (fn [_ key]
                    (if (= key :everchosen_hero_family_capacity) provider
                        (. objects key)))
                  :add_static_object #(tset objects $2 $3)
                  :add_listener (fn [_ _ event predicate callback]
                                  (tset s.listeners event
                                        {: predicate : callback}))}
           :cm {:add_first_tick_callback (fn [])
                :add_pre_first_tick_callback (fn [])
                :callback #(table.insert s.queue $2)}}
          {:__index _G})]
    (each [_ agent (ipairs [:wizard :engineer])]
      (tset agents agent
        {:CurrentState #(if (= agent s.selected-class) :selected_hover :active)
         :SimulateLClick (fn []
                           (table.insert s.class-clicks agent)
                           (set s.selected-class agent))}))
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile
      (or (os.getenv :EVERCHOSEN_HERO_RECRUITMENT_ENTRY)
          (.. root
            "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua"))))
      env))
    (set s.native-view-loader
      (assert (. env.package.preload :everchosen_hero_recruitment.view)))
    (tset env.package.preload :everchosen_core.world (fn [] world))
    (tset env.package.preload :everchosen_hero_recruitment.view (fn [] view))
    (each [_ key (ipairs [:everchosen_core.world
                          :everchosen_hero_recruitment.view
                          :everchosen_hero_recruitment.campaign])]
      (tset env.package.loaded key nil))
    (set s.native-view (s.native-view-loader))
    ((. (env.require :everchosen_hero_recruitment.campaign) :start))
    (set s.emit
      (fn [event context]
        (let [listener (assert (. s.listeners event))]
          (when (or (= true listener.predicate) (listener.predicate context))
            (listener.callback context)))))
    (set s.click
      #(s.emit :ComponentLClickUp
        {:string $1 :origin $2 :component confirm}))
    (set s.step #((assert (table.remove s.queue 1))))
    (set s.drain
      (fn []
        ;; Bound callbacks so a controller retry loop fails this fixture.
        (var remaining 40)
        (while (and (. s.queue 1) (> remaining 0))
          (set remaining (- remaining 1))
          (s.step))
        (assert.same [] s.queue (table.concat s.logs "\n"))))
    (set s.hire
      (fn [subtype]
        (s.emit :CharacterRecruited
          {:character (fn [] {:character_subtype_key (fn [] subtype)
                              :faction (fn [] host)})})))
    (s.emit :PanelOpenedCampaign {:string :character_panel})
    s))

(describe "unified native-candidate hero recruitment"
  (fn []
    (it "requires a nonempty matching native candidate list"
      (fn []
        (let [s (scenario)
              group {:members {:fire true :death true}}
              controls {:selection {}
                        :types (native-list
                                 [{:Id (fn [] :fire)
                                   :CurrentState (fn [] :selected_hover)}])}]
          (assert.is_falsy (s.native-view.matches? controls group))
          (set controls.selection.character_list {:list_box (native-list [])})
          (assert.is_falsy (s.native-view.matches? controls group))
          (let [observed {:subtype :fire}
                character {:Call (fn [_ query]
                                   (assert.equals :AgentSubtypeRecordContext.Key
                                                  query)
                                   observed.subtype)}
                card {:Visible (fn [] true)
                      :GetContextObject (fn [_ context]
                                          (assert.equals :CcoCampaignCharacter
                                                         context)
                                          character)}]
            (set controls.selection.character_list.list_box
              (native-list [card]))
            (assert.is_truthy (s.native-view.matches? controls group))
            (set observed.subtype :castellan)
            (assert.is_falsy (s.native-view.matches? controls group))))))
    (it "shows its own disabled copy without changing native recruitment state"
      (fn []
        (let [s (scenario)
              observed {:native-visible? true :native-state :active}
              native {:Id (fn [] :button_confirm) :Address (fn [] 12)
                      :Visible #(do observed.native-visible?)
                      :SetVisible #(set observed.native-visible? $2)
                      :CurrentState #(do observed.native-state)
                      :SetState #(error "Native state belongs to the engine")
                      :Width (fn [] 100) :Height (fn [] 20)
                      :Position (fn [] (values 10 30))}
              proxy {:Resize (fn []) :MoveTo (fn [])
                     :SetState #(set observed.proxy-state $2)
                     :SetVisible #(set observed.proxy-visible? $2)
                     :SetTooltipText #(set observed.tooltip $2)
                     :button_txt {:SetState #(set observed.label-state $2)
                                  :SetStateText (fn [])}}
              controls {:confirm native :blocked proxy
                        :footer {:button_confirm native}}
              state {:blocked {}}]
          (s.native-view.gate controls state false :everchosen_hero_capacity_full)
          (assert.is_false observed.native-visible?)
          (assert.is_true observed.proxy-visible?)
          (assert.equals :inactive observed.proxy-state)
          (assert.equals :inactive observed.label-state)
          (assert.equals :everchosen_hero_capacity_full observed.tooltip)
          (assert.equals :active (native:CurrentState))
          ;; Native affordability can change while our own quota blocks input.
          (set observed.native-state :inactive)
          (s.native-view.gate controls state true)
          (assert.is_true observed.native-visible?)
          (assert.is_false observed.proxy-visible?)
          (assert.equals :inactive (native:CurrentState)))))
    (it "prepares once immediately and paginates all families in one catalog"
      (fn []
        (let [s (scenario)]
          (assert.equals 1 s.prepares)
          (assert.equals 1 s.creates)
          (s.drain)
          (assert.same [] s.class-clicks)
          (assert.same [] s.subtype-clicks)
          (assert.equals :a-sorcerer s.selected)
          (assert.same [:a-sorcerer :b-alluress]
                       (icollect [_ group (ipairs s.groups)] group.key))
          (assert.equals 2 s.pages)
          (s.click :everchosen_hero_next :private)
          (assert.same [:c-shaman :d-castellan]
                       (icollect [_ group (ipairs s.groups)] group.key))
          (s.click :everchosen_hero_slot_1 :private)
          (s.drain)
          (assert.same [:fire] s.subtype-clicks)
          (s.click :everchosen_hero_slot_2 :private)
          (s.drain)
          (assert.same [:engineer] s.class-clicks)
          (assert.same [:fire :castellan] s.subtype-clicks)
          (s.click :button_cycle_right :footer)
          (s.drain)
          (assert.equals 1 s.prepares)
          (assert.equals 1 s.creates)
          (assert.equals 0 s.closes)
          (assert.equals :d-castellan s.selected))))
    (it "blocks a full family while another family has room"
      (fn []
        (let [s (scenario true)]
          (assert.is_false s.enabled?)
          (assert.same [] s.class-clicks)
          (assert.same [] s.subtype-clicks)
          (set s.pending? false)
          (s.emit ready {})
          (s.drain)
          (assert.is_true s.enabled?)
          (s.click :everchosen_hero_next :private)
          (s.click :everchosen_hero_slot_1 :private)
          (s.drain)
          (assert.is_false s.enabled?)
          (assert.equals :everchosen_hero_capacity_full s.reason)
          (s.click :everchosen_hero_slot_2 :private)
          (s.drain)
          (assert.is_true s.enabled?)
          (set s.pending? true)
          (s.emit updating {})
          (assert.is_false s.enabled?)
          (set s.pending? false)
          (s.emit ready {})
          (assert.is_true s.enabled?))))
    (it "keeps a late native confirmation locked through closing and reopening"
      (fn []
        (let [s (scenario)]
          (set s.snapshots.c-shaman {:used 0 :limit 1})
          (s.drain)
          (s.click :everchosen_hero_next :private)
          (s.click :everchosen_hero_slot_1 :private)
          (s.drain)
          (let [restores s.restores]
            (s.emit :PanelClosedCampaign {:string :character_panel})
            (assert.equals restores s.restores)
            (assert.equals 0 s.closes))
          ;; The engine may close before Lua receives this exact button event.
          (let [mutations s.mutations]
            (s.click :button_confirm :footer)
            (assert.equals mutations s.mutations))
          (s.emit :PanelOpenedCampaign {:string :character_panel})
          (s.drain)
          (assert.is_false s.enabled?)
          (assert.equals 1 s.prepares)
          (s.emit ready {})
          (s.hire :castellan)
          (s.drain)
          (assert.is_false s.enabled?)
          (s.hire :fire)
          (s.drain)
          (assert.is_true s.enabled?)
          ;; Leave the original native button intact for the rest of its click
          ;; dispatch. Our latch gates only the next deferred UI refresh.
          (let [mutations s.mutations]
            (s.click :button_confirm :footer)
            (assert.equals mutations s.mutations))
          (assert.is_true s.enabled?)
          (s.drain)
          (assert.is_false s.enabled?)
          (s.emit ready {})
          (assert.is_false s.enabled?)
          (s.emit :FactionTurnStart {:faction (fn [] true)})
          (assert.is_true s.requested?)
          (assert.is_false s.enabled?)
          (set s.pending? false)
          (s.emit ready {})
          (assert.is_true s.enabled?))))))
