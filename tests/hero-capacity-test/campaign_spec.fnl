;; Native cap and bonus readings are supplied observations. This fixture does
;; not model engine arithmetic or prove that recruitment limits are enforced.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local bundle-key :everchosen_hero_capacity_limits)
(local saved-key :everchosen_hero_capacity_state)
(local controller-key :everchosen_hero_capacity_controller)
(local config
  {:bundle bundle-key
   :families {:alluress {:agent :engineer :subtypes [:shadow :slaanesh]}
              :castellan {:agent :engineer :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :agent :engineer
                       :effect :shadow-cap :base -1}
              :slaanesh {:family :alluress :agent :engineer
                         :effect :slaanesh-cap :base -1}
              :castellan {:family :castellan :agent :engineer
                          :effect :castellan-cap :base -1}}
   :classes {:engineer :engineer-cap}
   :counted_subtypes {:shadow :engineer :slaanesh :engineer
                      :castellan :engineer}
   :external {:marker_path "unused-test-marker"} :skills []
   :native_families {}})

(fn observation [shadow slaanesh castellan bonuses parent-cap parent-bonus]
  {:caps {: shadow : slaanesh : castellan} : bonuses : parent-cap
   :parent-bonus (or parent-bonus 0)})

(fn fixture [new? saved observations initial fixture-config]
  (let [s {:queue [] :listeners {} :logs [] :applied [] :removed []
           :opening 0 :characters [] :saved saved :present? (not= saved nil)
           :reading initial :observations observations :registrations 0
           :controllers 0}
        host {:is_null_interface (fn [] false)
              :name (fn [] :wh_main_chs_chaos) :is_human (fn [] true)
              :has_effect_bundle (fn [_ key]
                                   (assert.equals bundle-key key)
                                   s.present?)}
        objects {:everchosen_hero_capacity_data (or fixture-config config)}
        cm {:get_campaign_name (fn [] :main_warhammer)
            :is_multiplayer (fn [] false) :is_new_game (fn [] new?)
            :get_faction (fn [] host)
            :get_saved_value (fn [_ key]
                               (assert.equals saved-key key) s.saved)
            :set_saved_value (fn [_ key value]
                               (assert.equals saved-key key)
                               (assert (not= value nil)
                                       "Native saved values cannot be nil")
                               (set s.saved value))
            :clear_saved_value (fn [_ key]
                                 (assert.equals saved-key key)
                                 (set s.saved nil))
            :add_first_tick_callback (fn [_ callback] (set s.start callback))
            :callback (fn [_ callback] (table.insert s.queue callback))
            :apply_effect_bundle (fn [_ key faction turns]
              (assert.equals :everchosen_hero_capacity_test key)
              (assert.equals :wh_main_chs_chaos faction)
              (assert.equals 0 turns)
              (set s.opening (+ s.opening 1)))
            :remove_effect_bundle (fn [_ key]
                                    (table.insert s.removed key)
                                    (set s.present? false))
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
              (set s.reading (assert (table.remove s.observations 1))))}
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
                    (tset s.listeners event {: name : predicate : callback}))}}
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
                (assert.equals :cap bonus)
                (assert (. s.reading.bonuses subtype)))}))
    (set host.agent_subtype_cap
      (fn [_ subtype] (assert (. s.reading.caps subtype))))
    (set host.agent_cap
      (fn [_ agent]
        (assert.equals :engineer agent)
        s.reading.parent-cap))
    (set s.characters
      [{:character_subtype_key (fn [] :shadow) :faction (fn [] host)
        :is_null_interface (fn [] false) :is_wounded (fn [] true)}])
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile (.. root
      "/build/hero-capacity-test/script/campaign/mod/everchosen_hero_capacity_test.lua")))
      env))
    (set s.provider (fn [] objects.everchosen_hero_family_capacity))
    (set s.snapshot
      (fn [subtypes] ((. (s.provider) :snapshot) subtypes)))
    (set s.other-start
      (fn []
        ;; Another pack may bundle a second copy of the same controller.
        (tset env.package.loaded :everchosen_hero_capacity.campaign nil)
        (let [capacity (env.require :everchosen_hero_capacity.campaign)]
          (capacity.start))))
    (set s.drain (fn []
                  (while (. s.queue 1) ((table.remove s.queue 1)))))
    (set s.refresh
      (fn [reading]
        (set s.reading reading)
        (let [event (. s.listeners :BuildingCompleted)]
          (event.callback {}))
        (s.drain)))
    s))

(fn measured-readings []
  [(observation 1 1 1 {:shadow 2 :slaanesh 2 :castellan 2} 0)
   (observation 2 2 2 {:shadow 3 :slaanesh 3 :castellan 3} 0)
   (observation 1 0 1 {:shadow 2 :slaanesh 1 :castellan 2} 2)])

(describe "shared hero-family capacity controller"
  (fn []
    (it "counts wounded heroes and removes its override from changing sources"
      (fn []
        (let [observations (measured-readings)
              grown (observation 2 1 1
                                 {:shadow 3 :slaanesh 2 :castellan 2} 3)
              removed (observation 1 0 1
                                   {:shadow 2 :slaanesh 1 :castellan 2} 2)]
          (table.insert observations grown)
          (table.insert observations removed)
          (let [s (fixture true nil observations nil)]
            (s.start)
            (s.drain)
            (assert.same {:shadow 1 :slaanesh 1 :castellan 1}
                         s.saved.normalizers)
            (assert.same {:used 1 :limit 1}
                         (s.snapshot [:shadow :slaanesh]))
            (s.refresh (observation 2 1 1
                         {:shadow 3 :slaanesh 2 :castellan 2} 2))
            (assert.same {:used 1 :limit 2}
                         (s.snapshot [:shadow :slaanesh]))
            (s.refresh (observation 1 0 1
                         {:shadow 2 :slaanesh 1 :castellan 2} 3))
            (assert.same {:used 1 :limit 1}
                         (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 1}
                         (s.snapshot [:castellan]))
            (assert.same {:shadow-cap 1 :slaanesh-cap 0 :castellan-cap 1
                          :engineer-cap 2} s.saved.applied)
            (assert.equals 1 (length s.logs))))))
    (it "restores its previous overrides on reload without another opening grant"
      (fn []
        (let [reading (observation 1 0 1
                        {:shadow 2 :slaanesh 1 :castellan 2} 2)
              saved {:normalizers {:shadow 1 :slaanesh 1 :castellan 1}
                     :applied {:shadow-cap 1 :slaanesh-cap 0 :castellan-cap 1
                               :engineer-cap 2}
                     :uplifts {:engineer 2}}
              s (fixture false saved [reading] reading)]
          (s.start)
          (s.drain)
          (assert.equals 0 s.opening)
          (assert.equals 1 (length s.applied))
          (assert.same saved s.saved)
          (assert.same {:used 1 :limit 1}
                       (s.snapshot [:shadow :slaanesh]))
          (assert.same [] s.logs))))
    (it "retains permanent native rewards without counting its own class uplift"
      (fn []
        (let [test-config (collect [key value (pairs config)]
                           (values key value))
              saved {:normalizers {:shadow 1 :slaanesh 1 :castellan 1}
                     :applied {} :uplifts {}}
              initial (observation 0 0 0
                        {:shadow 1 :slaanesh 1 :castellan 1} 0 0)
              uplifted (observation 1 0 1
                         {:shadow 2 :slaanesh 1 :castellan 2} 2 2)
              rewarded (observation 2 1 2
                         {:shadow 3 :slaanesh 2 :castellan 3} 4 3)]
          (set test-config.native_families
               {:engineer [:alluress :castellan]})
          (let [s (fixture false saved
                    [uplifted uplifted rewarded rewarded]
                    initial test-config)]
            (s.start)
            (s.drain)
            (s.refresh uplifted)
            (assert.same {:used 1 :limit 1}
                         (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 1}
                         (s.snapshot [:castellan]))
            (s.refresh (observation 1 0 1
                         {:shadow 2 :slaanesh 1 :castellan 2} 3 2))
            (assert.same {:used 1 :limit 2}
                         (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 2}
                         (s.snapshot [:castellan]))
            (s.refresh rewarded)
            (assert.same {:used 1 :limit 2}
                         (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 2}
                         (s.snapshot [:castellan]))
            (assert.same {:engineer 3} s.saved.uplifts)
            (assert.same [] s.logs)))))
    (it "cleans a failed probe and retries only on the next relevant event"
      (fn []
        (let [retry (measured-readings)
              nonlinear (observation 1 1 1
                          {:shadow 3 :slaanesh 3 :castellan 3} 0)
              s (fixture true nil
                  [(. retry 1) nonlinear
                   (. retry 1) (. retry 2) (. retry 3)] nil)]
          (s.start)
          (s.drain)
          (assert.is_false s.present?)
          (assert.is_nil s.saved)
          (assert.is_nil (s.provider))
          (assert.equals 2 (length s.applied))
          (assert.same [] s.queue)
          (each [_ removed (ipairs s.removed)]
            (assert.equals bundle-key removed))
          (let [registered s.registrations]
            (s.refresh (observation 0 0 0
                         {:shadow 1 :slaanesh 1 :castellan 1} 0))
            (assert.is_true s.present?)
            (assert.same {:used 1 :limit 1}
                         (s.snapshot [:shadow :slaanesh]))
            (assert.same {:used 0 :limit 1}
                         (s.snapshot [:castellan]))
            (assert.equals 1 s.opening)
            (assert.equals registered s.registrations)
            (assert.equals 1 s.controllers)
            (assert.equals 5 (length s.applied))
            (assert.equals 2 (length s.logs))))))
    (it "shares one controller when main and test packs both start it"
      (fn []
        (let [s (fixture true nil (measured-readings) nil)]
          (s.other-start)
          (let [registered s.registrations]
            (s.start)
            (s.drain)
            (assert.is_true (> registered 0))
            (assert.equals registered s.registrations)
            (assert.equals 1 s.controllers)
            (assert.equals 1 s.opening)
            (assert.equals 3 (length s.applied))
            (assert.same {:used 0 :limit 1}
                         (s.snapshot [:castellan]))
            (assert.equals 1 (length s.logs))))))))
