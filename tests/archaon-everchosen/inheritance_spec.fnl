;; Adapter regressions under Lua 5.1. Native plague and Great Game functions
;; are loaded from the current game extraction; the engine is not simulated.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local native (assert (os.getenv :EVERCHOSEN_VANILLA_DB)))
(local host :wh_main_chs_chaos)
(local prefix "everchosen_inheritance_")
(local mod-path (.. root "/build/archaon-everchosen/script/campaign/mod/"))

(fn game-list [entries]
  {:num_items #(length entries)
   :item_at (fn [_ index] (. entries (+ index 1)))})

(fn record [s kind value] (table.insert s.calls [kind value]))

(fn count-calls [s kind]
  (accumulate [count 0 _ call (ipairs s.calls)]
    (+ count (if (= (. call 1) kind) 1 0))))

(fn building-restrictions [s]
  (icollect [_ call (ipairs s.calls)]
    (when (= (. call 1) :building_restriction) (. call 2))))

(fn hud-component [s id]
  {:visible? true :state :inactive
   :SetVisible
   (fn [self visible?]
     (set self.visible? visible?)
     (record s :visibility id))})

(fn create-hud [s]
  (each [_ id (ipairs [:button_nurgle_plagues :button_changing_of_the_ways
                      :button_great_game_rituals :nurgle_infections_holder
                      :dae_ascendant_race_holder])]
    (tset s.ui id (hud-component s id))))

(fn faction-leader [s]
  (let [province {:is_null_interface (fn [] false) :key #(do s.province)}
        region {:is_null_interface (fn [] false) :province (fn [] province)}]
    {:is_null_interface (fn [] false)
     :has_region #(not s.no-region?) :region (fn [] region)}))

(fn resource-manager [s]
  {:resource
   (fn [_ key]
     {:is_null_interface #(= s.missing key)
      :value #(or (. s.balances key) 0)})})

(fn faction [s key subculture]
  (let [f {:key key :sc subculture
           :is_null_interface (fn [] false)
           :name (fn [self] self.key)
           :subculture (fn [self] self.sc)
           :culture (fn [] :wh_main_chs_chaos)
           :is_human (fn [self] (= self.key s.player))
           :is_dead (fn [self] (or self.dead? false))
           :is_vassal_of
           (fn [self overlord]
             (assert (= (type overlord) :table) "Native API takes a faction")
             (= self.master (overlord:name)))
           :faction_leader #(faction-leader s)
           :character_list
           (fn [self] (game-list (or (. s.characters self.key) [])))
           :was_confederated_by_faction
           (fn [self receiver]
             (assert (= (type receiver) :table) "Native API takes a faction")
             (= self.absorbed-by receiver))
           :has_effect_bundle
           (fn [self effect]
             (= (. (or (. s.effects self.key) {}) effect) true))
           :command_queue_index (fn [self] (if (= self.key host) 1 2))
           :has_rituals (fn [] true)
           :has_access_to_ritual_category (fn [] true)
           :is_contained_in_faction_set
           (fn [self]
             (or (= self.key host) (= self.key :wh3_dlc20_chs_festus)))
           :plagues (fn [] {:plague_component_list #(game-list [])})
           :pooled_resource_manager #(resource-manager s)}]
    (tset s.factions key f)
    f))

(fn own [s subtype]
  (let [c {:is_null_interface (fn [] false)
           :character_subtype_key (fn [] subtype)
           :faction #(. s.factions host)}]
    ;; No deployment/health methods: wounded ownership must not need them.
    (table.insert (. s.characters host) c)))

(fn campaign-model [s]
  (let [network
        {:is_null_interface (fn [] false)
         :lookup_open_node
         (fn [_ key]
           {:is_null_interface #(not (. s.nodes key))
            :record_key (fn [] key) :template_key #(. s.nodes key)})}
        system
        {:lookup_network
         (fn [_ key]
           (assert.equals :wh3_main_teleportation_network_belakor key)
           network)}]
    {:world
     (fn []
       {:teleportation_network_system (fn [] system)
        :faction_list #(game-list (icollect [_ f (pairs s.factions)] f))})}))

(fn open-node [s key]
  (record s :portal key)
  (when (not s.fail-portal?)
    (tset s.nodes key :wh3_main_teleportation_node_template_belakor)))

(fn apply-bundle [s key owner]
  (tset s.effects owner (or (. s.effects owner) {}))
  (tset s.effects owner key true)
  (record s :apply_bundle (.. owner ":" key)))

(fn remove-bundle [s key owner]
  (when (not s.fail-removal?) (tset s.effects owner key nil))
  (record s :remove_bundle (.. owner ":" key)))

(fn add-resource [s owner key factor amount]
  (assert (and (= owner host) (= factor :other)))
  (tset s.balances key (+ (or (. s.balances key) 0) amount))
  (record s :resource key))

(fn campaign-manager [s]
  {:get_campaign_name #(or s.campaign :main_warhammer)
   :is_multiplayer #(or s.multiplayer? false)
   :is_new_game #(do s.new-game?)
   :get_faction (fn [_ key] (. s.factions key))
   :get_faction_list #(game-list [(. s.factions host)])
   :get_local_faction #(. s.factions s.player)
   :get_saved_value (fn [_ key] (. s.saved key))
   :set_saved_value
   (fn [_ key value]
     (assert (not= value nil) "CA saved values cannot be nil")
     (tset s.saved key value))
   :save_named_value (fn [_ key value] (tset s.named key value))
   :load_named_value (fn [_ key default] (or (. s.named key) default))
   :add_first_tick_callback (fn [_ callback] (table.insert s.first callback))
   :add_pre_first_tick_callback
   (fn [_ callback] (table.insert s.pre-first callback))
   :add_saving_game_callback (fn [_ callback] (table.insert s.saving callback))
   :add_loading_game_callback
   (fn [_ callback] (table.insert s.loading callback))
   :callback (fn [_ callback] (table.insert s.callbacks callback))
   :model #(campaign-model s)
   :teleportation_network_open_node (fn [_ key] (open-node s key))
   :add_or_remove_faction_features
   (fn [_ owner features enable?]
     (assert (and (= owner (. s.factions host)) enable?))
     (record s :features features))
   :restrict_buildings_for_faction
   (fn [_ owner levels restricted?]
     (record s :building_restriction [owner levels restricted?]))
   :apply_effect_bundle (fn [_ key owner] (apply-bundle s key owner))
   :remove_effect_bundle (fn [_ key owner] (remove-bundle s key owner))
   :unlock_ritual
   (fn [_ owner key]
     (tset s.rituals key true)
     (record s :unlock key))
   :lock_ritual (fn [_ owner key] (tset s.rituals key false))
   :faction_add_pooled_resource
   (fn [_ owner key factor amount] (add-resource s owner key factor amount))
   :set_plague_component_state
   (fn [_ owner component state] (record s :component (.. component state)))
   :override_ui (fn [])
   :random_number (fn [_ maximum] maximum)
   :pending_battle_cache_faction_won_battle
   (fn [_ owner] (and (= owner host) s.won?))
   :pending_battle_cache_faction_won_battle_against_culture
   (fn [_ owner culture] (and (= owner host) (= s.enemy culture)))})

(fn require-module [env name]
  (when (not (. env.package.loaded name))
    (tset env.package.loaded name ((assert (. env.package.preload name)))))
  (. env.package.loaded name))

(fn campaign-environment [s]
  (let [env
        (setmetatable
          {:cm (campaign-manager s)
           :core
           {:get_ui_root #(do s.ui)
            :add_listener
            (fn [_ key event condition callback]
              (tset s.listeners key [event condition callback]))
            :add_static_object (fn [_ key value] (tset s.objects key value))
            :get_static_object (fn [_ key] (. s.objects key))}
           :common {:set_context_value
                    (fn [key value] (tset s.contexts key value))}
           :find_uicomponent (fn [ui id] (. ui id))
           :out (fn [value] (table.insert s.logs value))
           :archaon_subjugation_config
           {:faction_key_to_leader_subtype_list
            {:wh3_dlc20_chs_festus {:subtype_key :wh3_dlc20_nur_festus}
             :wh3_dlc20_chs_vilitch {:subtype_key :wh3_dlc20_tze_vilitch}
             :wh3_main_chs_shadow_legion {:subtype_key :wh3_main_dae_belakor}}}}
          {:__index _G})]
    ;; CA loads campaign/mod chunks into core:get_env(), not the Lua registry.
    ;; lib_campaign_manager exposes that environment as _G.campaign_env.
    (set env._G (setmetatable {:campaign_env env} {:__index _G}))
    (set env.core.get_env (fn [] env))
    ;; Each campaign session has a fresh cache for Fennel's bundled loaders.
    (set env.package {:preload {} :loaded {}})
    (set env.require #(require-module env $1))
    env))

(fn load-script [s path] ((setfenv (assert (loadfile path)) s.env)))

(fn flush [s]
  (let [queue s.callbacks]
    (set s.callbacks [])
    (each [_ callback (ipairs queue)] (callback))))

(fn start [s]
  (load-script s (.. native
                     "/script/campaign/wh3_dlc29_archaon_subjugation.lua"))
  (load-script s (.. native "/script/campaign/wh3_campaign_nurgle_plagues.lua"))
  (load-script s (.. native "/script/campaign/wh3_campaign_great_game.lua"))
  (each [_ callback (ipairs s.loading)] (callback {}))
  (load-script s (.. mod-path "everchosen_core_data.lua"))
  (load-script s (.. mod-path "everchosen_archaon.lua"))
  (each [_ callback (ipairs s.pre-first)] (callback))
  (s.env.nurgle_plagues:initialise)
  (each [_ callback (ipairs s.first)] (callback))
  (when s.late-hud? (s:create-hud))
  (s:flush))

(fn emit [s event context]
  ;; Limit delivery to this mod; native functions are called explicitly.
  (each [key listener (pairs s.listeners)]
    (let [[registered condition callback] listener]
      (when (and (= (key:sub 1 (length prefix)) prefix)
                 (= registered event)
                 (or (= condition true) (condition context)))
        (callback context))))
  (s:flush))

(fn turn [s]
  (s:emit :FactionTurnStart {:faction #(. s.factions host)}))

(fn sandbox [saved player]
  (let [s {:saved (or saved {}) :named {} :listeners {} :objects {}
           :first [] :pre-first [] :saving [] :loading [] :callbacks []
           :factions {} :balances {} :bundles {} :characters {} :rituals {}
           :calls [] :contexts {} :logs [] :new-game? (not saved)
           :player (or player host) :nodes {} :ui {}
           :province :wh3_main_combi_province_albion
           :count count-calls : create-hud : faction : own
           : start : emit : flush : turn}]
    (set s.effects {host s.bundles})
    (s:create-hud)
    (s:faction host :wh_main_sc_chs_chaos)
    (s:faction :wh3_dlc20_chs_festus :wh_main_sc_chs_chaos)
    (s:faction :wh3_dlc20_chs_vilitch :wh_main_sc_chs_chaos)
    (s:faction :wh3_main_chs_shadow_legion :wh_main_sc_chs_chaos)
    (s:faction :wh3_main_sla_seducers_of_slaanesh :wh3_main_sc_sla_slaanesh)
    (s:faction :wh3_main_kho_exiles_of_khorne :wh3_main_sc_kho_khorne)
    (tset s.characters host [])
    (set s.env (campaign-environment s))
    s))

(fn reload [s]
  (each [_ callback (ipairs s.saving)] (callback {}))
  (let [loaded (sandbox s.saved s.player)]
    (set loaded.named s.named)
    (set loaded.balances s.balances)
    (set loaded.bundles s.bundles)
    (set loaded.effects s.effects)
    (set loaded.nodes s.nodes)
    (each [key f (pairs s.factions)]
      (let [copy (or (. loaded.factions key) (loaded:faction key f.sc))]
        (set copy.master f.master)
        (set copy.dead? f.dead?)))
    (set loaded.rituals s.rituals)
    (loaded:start)
    loaded))

(describe "Archaon inheritance"
  (fn []
    (it "isolates a failed UI callback and keeps later listeners running"
      (fn []
        (let [s (sandbox)
              context {:string :character_details_panel}
              observed []
              component s.ui.button_nurgle_plagues
              set-visible component.SetVisible]
          (s:start)
          (set component.SetVisible #(error "HUD no longer available"))
          (let [callback (. s.listeners (.. prefix "ui_open") 3)
                listeners [callback #(table.insert observed $1)]]
            ;; lib_core's release path invokes listeners without pcall.
            (each [_ listener (ipairs listeners)] (listener context))
            (assert.same [context] observed)
            (assert.matches "Everchosen inheritance.*HUD no longer available"
                            (. s.logs (length s.logs)))
            (set component.SetVisible set-visible)
            (set component.visible? true)
            (each [_ listener (ipairs listeners)] (listener context))
            (s:flush)
            (assert.same [context context] observed)
            (assert.is_false component.visible?)))))

    (it (.. "hides unearned HUD controls after layout "
            "and opens each earned mechanic")
      (fn []
        (let [s (sandbox)]
          (set s.ui {})
          (set s.late-hud? true)
          (s:start)
          (each [_ component (pairs s.ui)]
            (assert.is_false component.visible?))
          (s:own :wh3_dlc20_nur_festus)
          (s:turn)
          (assert.is_true s.ui.button_nurgle_plagues.visible?)
          (assert.is_true s.ui.nurgle_infections_holder.visible?)
          (assert.is_false s.ui.button_changing_of_the_ways.visible?)
          (assert.is_false s.ui.button_great_game_rituals.visible?)
          (assert.is_false s.ui.dae_ascendant_race_holder.visible?)
          ;; A panel/layout refresh reapplied the native defaults.
          (s:create-hud)
          (s:emit :PanelClosedCampaign {})
          (assert.is_true s.ui.button_nurgle_plagues.visible?)
          (assert.is_false s.ui.button_great_game_rituals.visible?)
          (s:own :wh3_dlc20_tze_vilitch)
          (s:turn)
          (assert.is_true s.ui.button_changing_of_the_ways.visible?)
          (assert.is_false s.ui.button_great_game_rituals.visible?)
          (s:own :wh3_main_dae_belakor)
          (s:turn)
          (assert.is_true s.ui.button_great_game_rituals.visible?)
          (assert.is_true s.ui.dae_ascendant_race_holder.visible?)
          (let [loaded (reload s)]
            (each [_ component (pairs loaded.ui)]
              (assert.is_true component.visible?)
              ;; Keep native cooldown/turn locks.
              (assert.equals :inactive component.state))))))

    (it "requires verified ownership, counts wounded lords and unlocks once"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (assert.is_false
            (s.env.faction_has_great_game_rituals (. s.factions host)))
          (s:emit :ScriptEventArchaonSubjugatesChaosFaction
                  {:string :wh3_dlc20_chs_vilitch})
          (s:own :wh3_main_tze_lord_of_change)
          (s:turn)
          (assert.is_nil (. s.saved (.. prefix "unlocked_tze")))
          (s:own :wh3_dlc20_tze_vilitch)
          (s:emit :ScriptEventArchaonSubjugatesChaosFaction {})
          (assert.is_true (. s.saved (.. prefix "unlocked_tze")))
          (let [calls (s:count :unlock)
                ritual (. s.objects.everchosen_core_data.tze 1)]
            ;; An engine cooldown/temporary lock.
            (tset s.rituals ritual false)
            (s:turn)
            (s:emit :ScriptEventArchaonSubjugatesChaosFaction {})
            (assert.equals calls (s:count :unlock))
            (let [loaded (reload s)]
              (loaded:turn)
              (assert.equals 0 (loaded:count :unlock))
              (assert.is_false (. loaded.rituals ritual)))))))

    (it "waits for a real confederation, rejects other recipients"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (let [source s.factions.wh3_main_sla_seducers_of_slaanesh
                event {:faction (fn [] source)
                       :confederation #(. s.factions host)}]
            (s:emit :FactionJoinsConfederation event)
            (assert.is_nil (. s.saved (.. prefix "unlocked_sla")))
            (set source.absorbed-by s.factions.wh3_dlc20_chs_festus)
            (s:turn)
            (assert.is_nil (. s.saved (.. prefix "unlocked_sla")))
            (set source.absorbed-by (. s.factions host))
            (s:turn)
            (s:emit :FactionJoinsConfederation event)
            (assert.is_true (. s.saved (.. prefix "unlocked_sla")))
            (assert.equals 1 (s:count :features)))
          (let [source s.factions.wh3_main_kho_exiles_of_khorne
                event {:faction (fn [] source)
                       :confederation #(. s.factions host)}]
            (set source.absorbed-by (. s.factions host))
            (s:emit :FactionJoinsConfederation event)
            (s:emit :FactionJoinsConfederation event)
            (assert.is_true (. s.saved (.. prefix "unlocked_kho")))
            (assert.equals 2 (s:count :features)))
          (let [last-features
                (accumulate [last nil _ call (ipairs s.calls)]
                  (if (= (. call 1) :features) (. call 2) last))]
            (assert.same [:streaks] last-features)))))

    (it "keeps native plague recipes, resource balances and shuffle variants"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (set s.balances.wh3_main_nur_infections 47)
          (s:own :wh3_dlc20_nur_festus)
          (s:turn)
          (let [info (. s.env.nurgle_plagues.plague_faction_info host)]
            (assert.equals 18
              (length (. s.contexts (.. "random_plague_component_list_" host))))
            (assert.equals 3
              (. s.contexts (.. "random_plague_creation_count_" host)))
            (assert.equals 1 (. s.contexts (.. prefix "ui_nur")))
            (assert.equals 47 s.balances.wh3_main_nur_infections)
            (assert.is_nil (. s.bundles (.. prefix "infections_locked")))
            (assert.equals 2 (s:count :component))
            (set info.plague_creation_counter 1)
            (tset info.current_symptoms_list 1 :saved_recipe))
          (let [loaded (reload s)
                manager loaded.env.nurgle_plagues
                info (. manager.plague_faction_info host)]
            (assert.equals 1 info.plague_creation_counter)
            (assert.equals :saved_recipe (. info.current_symptoms_list 1))
            (assert.equals :saved_recipe
              (. loaded.contexts (.. "random_plague_component_list_" host) 1))
            (assert.equals 1
              (. loaded.contexts (.. "random_plague_creation_count_" host)))
            (assert.equals 0 (loaded:count :component))
            (assert.equals 47 loaded.balances.wh3_main_nur_infections)
            (manager:randomise_symptom_location (. loaded.factions host))
            (assert.is_true
              (accumulate [found? false _ key
                           (ipairs info.current_symptoms_list)
                           &until found?]
                (= key :wh3_dlc25_nur_force_5_festus)))))))

    (it "does not commit a failed initialization and retries from ownership"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (set s.missing :wh3_main_nur_infections)
          (s:own :wh3_dlc20_nur_festus)
          (s:turn)
          (assert.is_nil (. s.saved (.. prefix "unlocked_nur")))
          (assert.is_true (. s.bundles (.. prefix "infections_locked")))
          (set s.missing nil)
          (s:turn)
          (assert.is_true (. s.saved (.. prefix "unlocked_nur"))))))

    (it "persists battle deduplication and updates only on new ascendancy"
      (fn []
        (let [s (sandbox)
              resource :wh3_main_ritual_belakor_gg_1_uses]
          (s:start)
          (s:own :wh3_main_dae_belakor)
          (s:turn)
          ;; No free charges on acquisition.
          (assert.is_nil (. s.balances resource))
          (set s.won? true)
          (set s.enemy :wh3_main_kho_khorne)
          (s:emit :PendingBattle {})
          (s:emit :BattleCompleted {})
          (s:emit :BattleCompleted {})
          (assert.equals 1 (. s.balances resource))
          (let [loaded (reload s)]
            (set loaded.won? true)
            (set loaded.enemy :wh3_main_kho_khorne)
            (loaded:emit :BattleCompleted {})
            (assert.equals 1 (. loaded.balances resource))
            (loaded:emit :PendingBattle {})
            (loaded:emit :BattleCompleted {})
            (assert.equals 2 (. loaded.balances resource))
            (set loaded.saved.great_game_ascendant_god :wh3_main_kho_khorne)
            (loaded:emit :ScriptEventNewGodAscendant {})
            (assert.is_true
              loaded.rituals.wh3_main_ritual_belakor_gg_1_upgraded)
            (let [count (loaded:count :unlock)]
              (loaded:emit :ScriptEventNewGodAscendant {})
              (loaded:turn)
              (assert.equals count (loaded:count :unlock))
              ;; The wrapper delegates other factions to CA's actual function.
              (loaded.env.unlock_gg_rituals nil
                loaded.factions.wh3_main_chs_shadow_legion false)
              (assert.equals (+ count 4) (loaded:count :unlock)))))))

    (it "locks both military trees before independently unlocking each race"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (let [trees s.objects.everchosen_core_data.vassal_military_buildings
                refresh (. s.listeners
                           :everchosen_vassal_recruitment_turn 3)]
            (assert.equals 2 (s:count :building_restriction))
            (assert.same [[host trees.norsca.levels true]
                          [host trees.chaos_dwarfs.levels true]]
                         (building-restrictions s))
            (tset s.saved :everchosen_subjugation_completed
                  {:wh3_dlc23_chd_zhatan true})
            (refresh)
            (assert.equals 3 (s:count :building_restriction))
            (assert.same [host trees.chaos_dwarfs.levels false]
                         (. (building-restrictions s) 3))
            (tset s.saved.everchosen_subjugation_completed
                  :wh_dlc08_nor_norsca true)
            (refresh)
            (assert.equals 4 (s:count :building_restriction))
            (assert.same [host trees.norsca.levels false]
                         (. (building-restrictions s) 4))
            (refresh)
            (assert.equals 4 (s:count :building_restriction))))))

    (it "does not initialize inheritance for another player or multiplayer"
      (fn []
        (each [_ settings (ipairs [{:player :wh3_dlc20_chs_festus}
                                  {:multiplayer? true}])]
          (let [s (sandbox nil settings.player)]
            (set s.multiplayer? settings.multiplayer?)
            (s:start)
            (assert.is_nil s.objects.everchosen_inheritance)
            (assert.equals 2 (s:count :building_restriction))
            (each [_ call (ipairs s.calls)]
              (when (= (. call 1) :building_restriction)
                (let [[owner levels restricted?] (. call 2)]
                  (assert.equals host owner)
                  (assert.is_true (> (length levels) 0))
                  (assert.is_true restricted?))))
            (assert.equals 0 (s:count :features))
            (assert.is_nil (. s.bundles (.. prefix "infections_locked")))
            (assert.equals 0 (s:count :portal))
            (assert.equals 0 (s:count :visibility))))))

    (it "opens and confirms only the starting province, never reopens on load"
      (fn []
        (let [s (sandbox)]
          (s:start)
          (assert.equals s.province (. s.saved (.. prefix "starting_portal")))
          (assert.equals 1 (s:count :portal))
          (assert.is_nil (. s.saved (.. prefix "unlocked_gg")))
          ;; The node was closed during normal play.
          (tset s.nodes s.province nil)
          (let [loaded (reload s)]
            (loaded:turn)
            (assert.equals 0 (loaded:count :portal))
            (assert.is_nil (. loaded.nodes loaded.province))))
        (let [s (sandbox)]
          (set s.fail-portal? true)
          (s:start)
          (assert.equals 1 (s:count :portal))
          (assert.is_nil (. s.saved (.. prefix "starting_portal")))
          (assert.matches "did not open" (. s.logs (length s.logs)))
          (let [loaded (reload s)]
            (assert.equals 0 (loaded:count :portal))))
        (let [s (sandbox)]
          (set s.province :province_without_a_native_node)
          (s:start)
          (assert.equals 0 (s:count :portal))
          (assert.is_nil (. s.saved (.. prefix "starting_portal"))))))

    (it (.. "follows direct vassals, preserves unrelated effects "
            "and retries removal")
      (fn []
        (let [s (sandbox)
              vassal (s:faction :test_vassal :wh_main_sc_emp_empire)
              indirect (s:faction :test_indirect :wh_main_sc_emp_empire)
              other (s:faction :test_other :wh_main_sc_chs_chaos)]
          (set vassal.master host)
          (set indirect.master vassal.key)
          (tset s.effects vassal.key {:unrelated_native_bundle true})
          (s:start)
          (let [bundles s.objects.everchosen_core_data.blessings]
            (assert.is_false (vassal:has_effect_bundle bundles.nur))
            (s:own :wh3_dlc20_nur_festus)
            (s:turn)
            (assert.is_true (vassal:has_effect_bundle bundles.nur))
            (assert.is_false (vassal:has_effect_bundle bundles.tze))
            (assert.is_false (indirect:has_effect_bundle bundles.nur))
            (assert.is_false (other:has_effect_bundle bundles.nur))
            (assert.is_false
              (: (. s.factions host) :has_effect_bundle bundles.nur))
            (s:own :wh3_dlc20_tze_vilitch)
            (s:turn)
            (assert.is_true (vassal:has_effect_bundle bundles.tze))
            (let [applied (s:count :apply_bundle)]
              (s:turn)
              (assert.equals applied (s:count :apply_bundle)))
            (let [loaded (reload s)
                  vassal loaded.factions.test_vassal
                  other loaded.factions.test_other
                  event {:is_vassalage (fn [] true)
                         :was_vassalage (fn [] true)
                         :proposer #(. loaded.factions host)
                         :recipient (fn [] other)}]
              (assert.equals 0 (loaded:count :apply_bundle))
              (set other.master host)
              (loaded:emit :PositiveDiplomaticEvent event)
              (assert.is_true (other:has_effect_bundle bundles.nur))
              (assert.is_true (other:has_effect_bundle bundles.tze))
              (set vassal.master :wh3_main_chs_shadow_legion)
              (set loaded.fail-removal? true)
              (set event.recipient (fn [] vassal))
              (loaded:emit :NegativeDiplomaticEvent event)
              (assert.is_true
                (. loaded.saved (.. prefix "blessing_recipients") vassal.key))
              (set loaded.fail-removal? false)
              (loaded:emit :FactionTurnStart {:faction (fn [] vassal)})
              (assert.is_false (vassal:has_effect_bundle bundles.nur))
              (assert.is_false (vassal:has_effect_bundle bundles.tze))
              (assert.is_true
                (vassal:has_effect_bundle :unrelated_native_bundle))
              (assert.is_nil
                (. loaded.saved (.. prefix "blessing_recipients") vassal.key))
              (set other.dead? true)
              (loaded:turn)
              (assert.is_false (other:has_effect_bundle bundles.nur)))))))))
