;; API cap readings are supplied observations. This fixture does not model
;; the engine's unverified arithmetic or prove that recruitment is blocked.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local bundle-key :everchosen_hero_capacity_test_families)
(local saved-key :everchosen_hero_capacity_test_family_measurement)
(local config
  {:bundle bundle-key
   :families {:alluress {:limit 1 :subtypes [:shadow :slaanesh]}
              :castellan {:limit 1 :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :effect :shadow-cap :base -1}
              :slaanesh {:family :alluress :effect :slaanesh-cap :base -1}
              :castellan {:family :castellan :effect :castellan-cap :base -1}}})

(fn fixture [new? readings saved wounded? fail-at]
  (let [s {:queue [] :listeners {} :logs [] :applied [] :removed []
           :opening 0 :characters [] :saved saved :present? false}
        host {:is_null_interface (fn [] false)
              :name (fn [] :wh_main_chs_chaos) :is_human (fn [] true)
              :has_effect_bundle (fn [] s.present?)}
        objects {:everchosen_hero_capacity_test_families config}
        cm {:get_campaign_name (fn [] :main_warhammer)
            :is_multiplayer (fn [] false) :is_new_game (fn [] new?)
            :get_faction (fn [] host)
            :get_saved_value (fn [] s.saved)
            :set_saved_value (fn [_ key value]
                               (assert.equals saved-key key)
                               (set s.saved value))
            :add_first_tick_callback (fn [_ callback] (set s.start callback))
            :callback (fn [_ callback] (table.insert s.queue callback))
            :apply_effect_bundle #(set s.opening (+ s.opening 1))
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
              (set s.present? true))}
        env (setmetatable
              {:package {:preload {} :loaded {}} : cm
               :out #(table.insert s.logs $1)
               :core {:get_static_object (fn [_ key] (. objects key))
                      :add_static_object (fn [_ key value]
                                           (tset objects key value))
                      :add_listener (fn [_ _ event predicate callback]
                                       (tset s.listeners event
                                             {: predicate : callback}))}}
              {:__index _G})]
    (set host.character_list
      (fn [] {:num_items (fn [] (length s.characters))
              :item_at (fn [_ index] (. s.characters (+ index 1)))}))
    (set host.agent_subtype_cap
      (fn [_ subtype]
        (when (or s.fail? (= (length s.applied) fail-at))
          (error "Supplied cap read failure"))
        (let [observed (. readings (length s.applied))]
          (if s.override (. s.override subtype)
              observed (. observed subtype) 4294967295))))
    (when wounded?
      (set s.characters
        [{:character_subtype_key (fn [] :shadow) :faction (fn [] host)
          :is_null_interface (fn [] false)
          :is_wounded (fn [] true) :has_region (fn [] false)}]))
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile (.. root
      "/build/hero-capacity-test/script/campaign/mod/everchosen_hero_capacity_test.lua")))
      env))
    (set s.provider (fn [] objects.everchosen_hero_family_capacity))
    (s.start)
    (set s.drain (fn []
                  (while (. s.queue 1) ((table.remove s.queue 1)))))
    (s.drain)
    s))

(describe "hero-family capacity adapter"
  (fn []
    (it "counts wounded heroes and releases a transferred hero after re-query"
      (fn []
        (let [s (fixture true
                   [{:shadow 0 :slaanesh 0 :castellan 0}
                    {:shadow 1 :slaanesh 1 :castellan 1}
                    {:shadow 1 :slaanesh 0 :castellan 1}
                    {:shadow 1 :slaanesh 1 :castellan 1}] nil true)
              provider (s.provider)
              transferred (. s.characters 1)]
          (assert.equals :ready s.saved.status)
          (assert.same {:used 1 :limit 1}
                       (provider.snapshot [:shadow :slaanesh]))
          (assert.same {:shadow-cap 2 :slaanesh-cap 1 :castellan-cap 2}
                       (. s.applied 3 :effects))
          (set s.characters [])
          (set transferred.faction (fn [] {:name (fn [] :other)}))
          (let [event (. s.listeners :CharacterFactionChangeEvent)
                context {:character (fn [] transferred)}]
            (assert.is_truthy (event.predicate context))
            (event.callback context))
          (s.drain)
          (assert.same {:used 0 :limit 1}
                       (provider.snapshot [:shadow :slaanesh]))
          (assert.same {:shadow-cap 2 :slaanesh-cap 2 :castellan-cap 2}
                       (. s.applied 4 :effects)))))
    (it "does not enable an unresponsive cap effect or remove another bundle"
      (fn []
        (let [unlimited {:shadow 4294967295 :slaanesh 4294967295
                         :castellan 4294967295}
              s (fixture true [unlimited unlimited] nil false)]
          (assert.is_nil (s.provider))
          (assert.equals :unsupported s.saved.status)
          (assert.is_false s.present?)
          (each [_ key (ipairs s.removed)] (assert.equals bundle-key key)))))
    (it "restores current-campaign measurement without giving opening cap again"
      (fn []
        (let [s (fixture false [{:shadow 1 :slaanesh 1 :castellan 1}]
                   {:status :ready
                    :offsets {:shadow 1 :slaanesh 1 :castellan 1}} false)]
          (assert.equals 0 s.opening)
          (assert.equals 1 (length s.applied))
          (let [provider (s.provider)]
            (assert.same {:used 0 :limit 1}
                         (provider.snapshot [:shadow :slaanesh]))))))
    (it "removes measurement effects when the first delayed read throws"
      (fn []
        (let [s (fixture true [] nil false 1)]
          (assert.is_nil (s.provider))
          (assert.is_false s.present?)
          (assert.equals :unsupported s.saved.status))))
    (it "disables the published provider when a later verification throws"
      (fn []
        (let [s (fixture false [{:shadow 1 :slaanesh 1 :castellan 1}]
                   {:status :ready
                    :offsets {:shadow 1 :slaanesh 1 :castellan 1}} false)
              provider (s.provider)]
          (set s.fail? true)
          ((. s.listeners :FactionTurnStart :callback))
          (s.drain)
          (assert.is_nil (provider.snapshot [:shadow :slaanesh]))
          (assert.is_false s.present?)
          (assert.equals :unsupported s.saved.status))))
    (it "disables the published provider when later cap values stop matching"
      (fn []
        (let [s (fixture false [{:shadow 1 :slaanesh 1 :castellan 1}]
                   {:status :ready
                    :offsets {:shadow 1 :slaanesh 1 :castellan 1}} false)
              provider (s.provider)]
          (set s.override {:shadow 2 :slaanesh 2 :castellan 2})
          ((. s.listeners :FactionTurnStart :callback))
          (s.drain)
          (assert.is_nil (provider.snapshot [:shadow :slaanesh]))
          (assert.is_false s.present?)
          (assert.equals :unsupported s.saved.status))))
    (it "ignores destroyed characters whose native details are already null"
      (fn []
        (let [s (fixture false [{:shadow 1 :slaanesh 1 :castellan 1}]
                   {:status :ready
                    :offsets {:shadow 1 :slaanesh 1 :castellan 1}} false)
              event (. s.listeners :CharacterDestroyed)
              details {:is_null_interface (fn [] true)}
              member {:is_null_interface (fn [] false)
                      :character_details (fn [] details)}]
          (assert.is_falsy (event.predicate
                            {:family_member (fn [] member)})))))))
