;; The native UI and capacity provider are observation boundaries here.
;; The fixture never invents candidate generation, pricing or cap arithmetic.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local mode :everchosen_hero_mode)
(local updating :ScriptEventEverchosenHeroCapacityUpdating)
(local ready :ScriptEventEverchosenHeroCapacityReady)

(fn native-list [children]
  {:ChildCount #(length children)
   :Find (fn [_ index] (. children (+ index 1)))})

(fn scenario [pending?]
  (let [s {:queue [] :listeners {} :logs [] :class-clicks []
           :subtype-clicks [] :enabled? false :pending? pending?
           :selected-class :wizard :selected-subtype :chaos-fire
           :snapshots {:sorcerer {:used 0 :limit 1}
                       :alluress {:used 0 :limit 1}
                       :a-shaman {:used 1 :limit 1}
                       :b-castellan {:used 0 :limit 1}}}
        families
        {:sorcerer {:agent :wizard :private false :subtypes [:chaos-fire]}
         :alluress {:agent :engineer :private false :subtypes [:slaanesh]}
         :a-shaman {:agent :wizard :private true :subtypes [:fire :death]}
         :b-castellan {:agent :engineer :private true :subtypes [:castellan]}}
        metadata {:chaos-fire {:family :sorcerer}
                  :slaanesh {:family :alluress}
                  :fire {:family :a-shaman} :death {:family :a-shaman}
                  :castellan {:family :b-castellan}}
        config {: families :subtypes metadata
                :native_page {:wizard :sorcerer :engineer :alluress}}
        objects {:everchosen_hero_capacity_data config}
        provider {:pending #(not (not s.pending?))
                  :ready #(not s.pending?)
                  :set-private #(set s.private? $1)
                  :request (fn []
                             (set s.requested? true)
                             (set s.pending? true))
                  :snapshot #(let [record (. metadata (. $1 1))]
                               (. s.snapshots record.family))}
        agents {:kind :agents :SetVisible (fn [])}
        types (collect [_ subtype
                        (ipairs [:chaos-fire :slaanesh :fire :death :castellan])]
                (values subtype
                  {:Visible (fn [] true)
                   :CurrentState #(if (= subtype s.selected-subtype)
                                      :selected :active)
                   :SimulateLClick (fn []
                     (table.insert s.subtype-clicks subtype)
                     (set s.selected-subtype subtype))}))
        controls {: agents : types :private {:kind :private}
                  :panel {:footer {:kind :footer}}
                  :selection {:SetInteractive (fn [])}}
        world {:host (fn [] true) :host? (fn [] true)
               :static-data #(do {:hero_recruitment {:page_size 8}})}
        view {:controls (fn [] controls) :create (fn [])
              :reserve-frame (fn []) :restore (fn [])
              :restore-types (fn []) :filter-types (fn [])
              :native-labels (fn []) :show-capacity (fn [])
              :block #(set s.enabled? false)
              :gate (fn [_ enabled?] (set s.enabled? (not (not enabled?))))
              :matches? (fn [] true)
              :clicked? (fn [parent context] (= parent.kind context.origin))
              :show-page (fn [_ entries _ _ selected private?]
                           (set s.groups entries)
                           (set s.selected selected)
                           (set s.rendered-private? private?))}
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
    (set s.native-matches? (. (s.native-view-loader) :matches?))
    ((. (env.require :everchosen_hero_recruitment.campaign) :start))
    (set s.emit
      (fn [event context]
        (let [listener (assert (. s.listeners event))]
          (when (or (= true listener.predicate) (listener.predicate context))
            (listener.callback context)))))
    (set s.click #(s.emit :ComponentLClickUp {:string $1 :origin $2}))
    (set s.step #((assert (table.remove s.queue 1))))
    (set s.drain
      (fn []
        (var remaining 40)
        (while (and (. s.queue 1) (> remaining 0))
          (set remaining (- remaining 1))
          (s.step))
        (assert.same [] s.queue (table.concat s.logs "\n"))))
    (set s.hire
      (fn [subtype]
        (s.emit :CharacterRecruited
          {:character (fn [] {:character_subtype_key (fn [] subtype)
                              :faction (fn [] true)})})))
    (s.emit :PanelOpenedCampaign {:string :character_panel})
    s))

(describe "native candidate recruitment through two hero pages"
  (fn []
    (it "requires a nonempty matching native candidate list"
      (fn []
        (let [s (scenario)
              group {:members {:fire true :death true}}
              controls {:selection {}
                        :types (native-list
                                 [{:Id (fn [] :fire)
                                   :CurrentState (fn [] :selected_hover)}])}]
          (assert.is_falsy (s.native-matches? controls group))
          (set controls.selection.character_list {:list_box (native-list [])})
          (assert.is_falsy (s.native-matches? controls group))
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
            (assert.is_truthy (s.native-matches? controls group))
            (set observed.subtype :castellan)
            (assert.is_falsy (s.native-matches? controls group))))))
    (it "opens the current native family and only switches requested classes"
      (fn []
        (let [s (scenario)]
          (s.drain)
          (assert.same [] s.class-clicks)
          (assert.same [] s.subtype-clicks)
          (assert.equals :sorcerer s.selected)
          (assert.is_false s.rendered-private?)
          (s.click mode :private)
          (s.drain)
          (assert.is_true s.private?)
          (assert.is_true s.rendered-private?)
          (assert.same [:fire] s.subtype-clicks)
          (assert.same [:a-shaman :b-castellan]
                       (icollect [_ group (ipairs s.groups)] group.key))
          (s.click :everchosen_hero_slot_2 :private)
          (s.drain)
          (assert.same [:engineer] s.class-clicks)
          (assert.same [:fire :castellan] s.subtype-clicks)
          (s.click mode :private)
          (s.drain)
          (assert.equals :alluress s.selected)
          (assert.is_false s.private?)
          (assert.same [:engineer] s.class-clicks)
          (assert.same [:fire :castellan :slaanesh] s.subtype-clicks))))
    (it "gates pending and full families while another private family has room"
      (fn []
        (let [s (scenario true)]
          (s.step)
          (s.step)
          (assert.same [] s.class-clicks)
          (assert.same [] s.subtype-clicks)
          (assert.is_false s.enabled?)
          (set s.pending? false)
          (s.emit ready {})
          (s.drain)
          (assert.is_true s.enabled?)
          (s.click mode :private)
          (s.drain)
          (assert.equals :a-shaman s.selected)
          (assert.is_false s.enabled?)
          (s.click :everchosen_hero_slot_2 :private)
          (s.drain)
          (assert.is_true s.enabled?)
          (set s.pending? true)
          (s.emit updating {})
          (assert.is_false s.enabled?)
          (set s.pending? false)
          (s.emit ready {})
          (assert.is_true s.enabled?))))
    (it "locks in-flight hiring through refreshes and revalidates on a new turn"
      (fn []
        (let [s (scenario)]
          (set s.snapshots.a-shaman {:used 0 :limit 1})
          (s.drain)
          (s.click mode :private)
          (s.drain)
          (assert.is_true s.enabled?)
          (s.click :button_confirm :footer)
          (assert.is_false s.enabled?)
          (s.emit ready {})
          (s.hire :castellan)
          (s.drain)
          (s.click :everchosen_hero_slot_2 :private)
          (s.drain)
          (assert.is_false s.enabled?)
          (s.hire :fire)
          (s.drain)
          (assert.is_true s.enabled?)
          ;; A rejected native command may have no creation event. The next
          ;; host turn requires a fresh verified reading before retrying.
          (s.click :button_confirm :footer)
          (assert.is_false s.enabled?)
          (s.emit :FactionTurnStart {:faction (fn [] true)})
          (assert.is_true s.requested?)
          (assert.is_false s.enabled?)
          (set s.pending? false)
          (s.emit ready {})
          (assert.is_true s.enabled?))))))
