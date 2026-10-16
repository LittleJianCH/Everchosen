;; Native bonus and parent-cap readings are supplied observations. This fixture
;; does not emulate engine arithmetic, UI refresh, or recruitment enforcement.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local bundle-key :everchosen_hero_capacity_limits)
(local controller-key :everchosen_hero_capacity_controller)
(local updating :ScriptEventEverchosenHeroCapacityUpdating)
(local ready :ScriptEventEverchosenHeroCapacityReady)
(local failed :ScriptEventEverchosenHeroCapacityFailed)
(local config
  {:bundle bundle-key
   :families {:alluress {:agent :engineer :subtypes [:shadow :slaanesh]}
              :castellan {:agent :engineer :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :agent :engineer}
              :slaanesh {:family :alluress :agent :engineer}
              :castellan {:family :castellan :agent :engineer}}
   :classes {:engineer :engineer-cap}
   :native_page {:engineer :alluress}
   :counted_subtypes {:shadow :engineer :slaanesh :engineer
                      :castellan :engineer}
   :external {:marker_path "unused-test-marker"} :skills []
   :native_families {}})

(fn reading [bonuses parent-cap parent-bonus]
  {: bonuses : parent-cap :parent-bonus (or parent-bonus 0)})

(fn round [baseline verified]
  {: baseline :verified (reading baseline.bonuses verified)})

(fn fixture [new? rounds fixture-config]
  (let [s {:queue [] :listeners {} :logs [] :applied [] :removed [] :events []
           :opening 0 :characters [] :present? (not new?) :rounds rounds
           :registrations 0 :controllers 0 :ui-starts 0 :baseline-reads 0}
        host {:is_null_interface (fn [] false)
              :name (fn [] :wh_main_chs_chaos) :is_human (fn [] true)}
        objects {:everchosen_hero_capacity_data (or fixture-config config)
                 :everchosen_core_data {}}
        cm {:get_campaign_name (fn [] :main_warhammer)
            :is_multiplayer (fn [] false) :is_new_game (fn [] new?)
            :get_faction (fn [] host)
            :get_saved_value (fn [] (error "Capacity must be re-derived"))
            :set_saved_value (fn [] (error "Capacity must not be persisted"))
            :add_first_tick_callback (fn [_ callback] (set s.start callback))
            :callback (fn [_ callback] (table.insert s.queue callback))
            :apply_effect_bundle (fn [_ key faction turns]
              (assert.equals :everchosen_hero_capacity_test key)
              (assert.equals :wh_main_chs_chaos faction)
              (assert.equals 0 turns)
              (set s.opening (+ s.opening 1)))
            :remove_effect_bundle (fn [_ key]
              (assert.equals bundle-key key)
              (table.insert s.removed key)
              (set s.present? false)
              (when s.refreshing?
                (set s.refreshing? false)
                (set s.round (assert (table.remove s.rounds 1)))
                (set s.reading s.round.baseline)))
            :create_new_custom_effect_bundle
            (fn [_ key]
              (assert.equals bundle-key key)
              (let [bundle {:effects {}}]
                (set bundle.add_effect
                  (fn [_ key scope value]
                    (assert.equals :faction_to_faction_own_unseen scope)
                    (tset bundle.effects key value)))
                (set bundle.set_duration (fn [_ turns] (assert.equals 0 turns)))
                bundle))
            :apply_custom_effect_bundle_to_faction
            (fn [_ bundle faction]
              (assert.equals host faction)
              (table.insert s.applied bundle)
              (set s.present? true)
              (set s.reading s.round.verified))}
        env (setmetatable
          {:package {:preload {} :loaded {}} : cm
           :out #(table.insert s.logs $1)
           :common {:vfs_exists (fn [] false)}
           :core {:get_static_object (fn [_ key] (. objects key))
                  :add_static_object (fn [_ key value]
                    (when (= key controller-key)
                      (set s.controllers (+ s.controllers 1)))
                    (tset objects key value))
                  :add_listener (fn [_ name event predicate callback]
                    (set s.registrations (+ s.registrations 1))
                    (tset s.listeners event {: name : predicate : callback}))
                  :trigger_custom_event (fn [_ event]
                    (table.insert s.events event)
                    (when (= event updating) (set s.refreshing? true)))}}
          {:__index _G})]
    (set host.character_list
      (fn [] {:num_items (fn [] (length s.characters))
              :item_at (fn [_ index] (. s.characters (+ index 1)))}))
    (set host.bonus_values
      (fn [] {:agent_value
              (fn [_ agent bonus]
                (assert.equals :engineer agent)
                (assert.equals :cap bonus)
                s.reading.parent-bonus)
              :agent_subtype_value
              (fn [_ subtype bonus]
                (assert.is_false s.present?)
                (assert.equals :cap bonus)
                (assert (. s.reading.bonuses subtype)))}))
    (set host.agent_subtype_cap
      (fn [] (error "Unlimited native subtype caps cannot enforce families")))
    (set host.agent_cap
      (fn [_ agent]
        (assert.equals :engineer agent)
        (when (not s.present?)
          (set s.baseline-reads (+ s.baseline-reads 1)))
        s.reading.parent-cap))
    (set s.characters
      [{:character_subtype_key (fn [] :shadow) :faction (fn [] host)
        :is_null_interface (fn [] false) :is_wounded (fn [] true)}])
    ;; The shared selector is only a boundary here, not a mock game UI.
    (tset env.package.preload :everchosen_hero_recruitment.campaign
      (fn [] {:start #(set s.ui-starts (+ s.ui-starts 1))}))
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile
      (or (os.getenv :EVERCHOSEN_HERO_CAPACITY_ENTRY)
          (.. root
            "/build/hero-capacity-test/script/campaign/mod/everchosen_hero_capacity_test.lua"))))
      env))
    (set s.provider (fn [] objects.everchosen_hero_family_capacity))
    (set s.snapshot (fn [subtypes] ((. (s.provider) :snapshot) subtypes)))
    (set s.other-start
      (fn []
        ;; Main and test entry points can carry a copy of the same module.
        (tset env.package.loaded :everchosen_hero_capacity.campaign nil)
        (let [capacity (env.require :everchosen_hero_capacity.campaign)]
          (capacity.start))))
    (set s.drain (fn []
                  (while (. s.queue 1) ((table.remove s.queue 1)))))
    (set s.refresh
      (fn []
        (let [event (. s.listeners :BuildingCompleted)]
          (event.callback {}))
        (s.drain)))
    s))

(describe "shared hero-family capacity controller"
  (fn []
    (it "opens one private-page slot and restores native accounting on close"
      (fn []
        (let [baseline (reading {:shadow 1 :slaanesh 1 :castellan 1} 6)
              s (fixture true [(round baseline 1) (round baseline 2)
                               (round baseline 1)])]
          (s.start)
          (assert.is_truthy ((. (s.provider) :pending)))
          (assert.is_falsy ((. (s.provider) :ready)))
          (assert.same [updating] s.events)
          (assert.equals 1 (length s.removed))
          (s.drain)
          (assert.same [updating ready] s.events)
          (assert.same {:used 1 :limit 1} (s.snapshot [:shadow :slaanesh]))
          (assert.same {:used 0 :limit 1} (s.snapshot [:castellan]))
          (assert.same {:engineer-cap -5} (. s.applied 1 :effects))
          ((. (s.provider) :set-private) true)
          (assert.is_falsy ((. (s.provider) :ready)))
          (s.drain)
          (assert.is_truthy ((. (s.provider) :ready)))
          (assert.same {:engineer-cap -4} (. s.applied 2 :effects))
          (assert.same {:used 1 :limit 1} (s.snapshot [:shadow :slaanesh]))
          (assert.same {:used 0 :limit 1} (s.snapshot [:castellan]))
          ;; Selecting a family must not recalculate native capacities.
          ((. (s.provider) :set-private) true)
          (assert.same [] s.queue)
          (assert.equals 2 (length s.applied))
          ((. (s.provider) :set-private) false)
          (s.drain)
          (assert.same {:engineer-cap -5} (. s.applied 3 :effects))
          (assert.equals 1 s.opening)
          (assert.equals 1 s.ui-starts))))
    (it "masks immediately after a private hire and compensates its actual use"
      (fn []
        (let [baseline (reading {:shadow 1 :slaanesh 1 :castellan 1} 6)
              s (fixture true [(round baseline 1) (round baseline 2)
                               (round baseline 3) (round baseline 2)])]
          (s.start)
          (s.drain)
          ((. (s.provider) :set-private) true)
          (s.drain)
          (let [host (: (. s.characters 1) :faction)
                hired {:character_subtype_key (fn [] :castellan)
                       :faction (fn [] host)
                       :is_null_interface (fn [] false)
                       :is_wounded (fn [] false)}]
            (table.insert s.characters hired)
            ((. s.listeners :CharacterRecruited :callback)
              {:character (fn [] hired)}))
          (assert.is_falsy ((. (s.provider) :ready)))
          (assert.equals updating (. s.events (length s.events)))
          (assert.is_nil (s.snapshot [:castellan]))
          (s.drain)
          (assert.same {:used 1 :limit 1} (s.snapshot [:castellan]))
          (assert.same {:used 1 :limit 1} (s.snapshot [:shadow :slaanesh]))
          (assert.same {:engineer-cap -3} (. s.applied 3 :effects))
          ((. (s.provider) :set-private) false)
          (s.drain)
          (assert.same {:engineer-cap -4} (. s.applied 4 :effects)))))
    (it "removes its negative adjustment before re-reading changed sources"
      (fn []
        (let [first (reading {:shadow 1 :slaanesh 1 :castellan 1} 7)
              changed (reading {:shadow 2 :slaanesh 2 :castellan 0} 9)
              s (fixture true [(round first 1)
                               (round changed 2) (round first 1)])]
          (s.start)
          (s.drain)
          (assert.same {:engineer-cap -6} (. s.applied 1 :effects))
          (s.refresh)
          (assert.same {:used 1 :limit 2} (s.snapshot [:shadow :slaanesh]))
          (assert.same {:engineer-cap -7} (. s.applied 2 :effects))
          (s.refresh)
          (assert.same {:used 1 :limit 1} (s.snapshot [:shadow :slaanesh]))
          (assert.same {:engineer-cap -6} (. s.applied 3 :effects))
          (assert.equals 3 s.baseline-reads))))
    (it "re-derives a normal load without another grant or counting its bundle"
      (fn []
        (let [test-config (collect [key value (pairs config)]
                            (values key value))
              baseline (reading {:shadow 1 :slaanesh 1 :castellan 1} 3 2)]
          (set test-config.native_families {:engineer [:alluress]})
          (let [s (fixture false [(round baseline 2)] test-config)]
            (s.start)
            (s.drain)
            (assert.equals 0 s.opening)
            (assert.equals 1 (length s.removed))
            (assert.same {:used 1 :limit 2} (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 1} (s.snapshot [:castellan]))
            (assert.same {:engineer-cap -1} (. s.applied 1 :effects))
            (assert.same [] s.logs)))))
    (it "keeps failed reads unready and retries only on a relevant event"
      (fn []
        (let [baseline (reading {:shadow 1 :slaanesh 1 :castellan 1} 0)
              s (fixture true [(round baseline 0) (round baseline 1)])]
          (s.start)
          (s.drain)
          (assert.is_falsy ((. (s.provider) :ready)))
          (assert.is_nil (s.snapshot [:castellan]))
          (assert.is_false s.present?)
          (assert.same [updating failed] s.events)
          (assert.equals 2 (length s.removed))
          (assert.same [] s.queue)
          (assert.is_truthy (string.find (table.concat s.logs "\n")
                              "Native hero capacity did not reach target"))
          (let [registered s.registrations]
            (s.refresh)
            (assert.equals registered s.registrations)
            (assert.is_truthy ((. (s.provider) :ready)))
            (assert.same {:used 0 :limit 1} (s.snapshot [:castellan]))
            (assert.equals 1 s.opening)))))
    (it "shares one controller between main and test without duplicate listeners"
      (fn []
        (let [baseline (reading {:shadow 1 :slaanesh 1 :castellan 1} 0)
              s (fixture true [(round baseline 1) (round baseline 1)])]
          (s.other-start)
          (let [registered s.registrations]
            (s.start)
            (s.drain)
            (assert.is_true (> registered 0))
            (assert.equals registered s.registrations)
            (assert.equals 1 s.controllers)
            (assert.equals 1 s.opening)
            (assert.equals 1 (length s.applied))
            (assert.same {:used 0 :limit 1} (s.snapshot [:castellan]))))))))
