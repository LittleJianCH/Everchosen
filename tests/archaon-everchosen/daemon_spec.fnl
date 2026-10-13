;; Model events are supplied independently; queued timers stay paused.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local host :wh_main_chs_chaos)
(local subtype :wh3_main_dae_daemon_prince)
(local souls :wh3_dlc20_chs_souls)
(local glory :wh3_main_dae_khorne_points)
(local spent :wh3_dlc20_chs_souls_spent_kho)

(fn valid [object]
  (set object.is_null_interface (fn [] false))
  object)

(fn resource [s key]
  (when (not (. s.resources key))
    (tset s.resources key
      (valid {:amount (if (= key souls) 1000 0) :cap 3080
              :key (fn [] key) :value (fn [self] self.amount)
              :maximum_value (fn [self] self.cap)})))
  (. s.resources key))

(fn load-module [s env]
  (set env.package {:preload {} :loaded {}})
  (set env.require
    (fn [name]
      (when (not (. env.package.loaded name))
        (tset env.package.loaded name ((assert (. env.package.preload name)))))
      (. env.package.loaded name)))
  (each [_ file (ipairs [:everchosen_core_data.lua
                         :everchosen_archaon.lua])]
    ((setfenv (assert (loadfile (.. root
      "/build/archaon-everchosen/script/campaign/mod/" file))) env)))
  (set s.module (env.require :everchosen_daemon.campaign)))

(fn scenario []
  (let [s {:saved {:everchosen_daemon_initialized true} :resources {}
           :payloads [] :bundles [] :character-bundles {} :grants []
           :resets 0 :queue [] :listeners {}
           :ui-events [] :ui {} :registry [:existing_part]}
        faction (valid {:name (fn [] host) :is_human (fn [] true)
                         :command_queue_index (fn [] 83)
                         :has_effect_bundle (fn [_ key] (= s.dedication key))})
        armory {:get_currently_registered_armory_items #(do s.registry)}
        prince (valid {:character_subtype_key (fn [] subtype)
                        :faction (fn [] faction)
                        :has_effect_bundle (fn [_ key] (. s.character-bundles key))
                        :family_member #(do {:armory (fn [] armory)})})
        objects {}
        env (setmetatable
              {:cm
               {:get_faction (fn [_ key] (when (= key host) faction))
                :get_local_faction_name (fn [] host)
                :get_campaign_name (fn [] :main_warhammer)
                :is_multiplayer (fn [] false)
                :is_local_players_turn #(not s.other-turn?)
                :get_saved_value (fn [_ key] (. s.saved key))
                :set_saved_value (fn [_ key value] (tset s.saved key value))
                :char_lookup_str (fn [_ character]
                                   (assert.equals prince character) :character_cqi:7)
                :force_reset_skills
                (fn [_ lookup]
                  (assert.equals :character_cqi:7 lookup)
                  (set s.resets (+ s.resets 1)))
                :unlock_ritual (fn [_ owner] (assert.equals faction owner))
                :callback (fn [_ f] (table.insert s.queue f))
                :add_first_tick_callback (fn [])
                :add_pre_first_tick_callback (fn [])
                :create_payload
                (fn []
                  {:changes {}
                   :faction_pooled_resource_transaction
                   (fn [self key factor amount percent?]
                     (assert.is_false percent?)
                     (tset self.changes key {: factor : amount}))})
                :apply_payload
                (fn [_ payload owner]
                  (assert.equals faction owner)
                  (table.insert s.payloads payload))
                :apply_effect_bundle
                (fn [_ key owner duration]
                  (assert.equals host owner) (assert.equals 0 duration)
                  (table.insert s.bundles key)
                  (set s.dedication key))
                :apply_effect_bundle_to_character
                (fn [_ key character duration]
                  (assert.equals prince character)
                  (tset s.character-bundles key true))
                :remove_effect_bundle_from_character
                (fn [_ key character]
                  (assert.equals prince character)
                  (tset s.character-bundles key nil))
                :add_armory_item_to_character
                (fn [_ character item equip? clear?]
                  (assert.equals prince character)
                  (assert.is_false equip?) (assert.is_false clear?)
                  (table.insert s.grants item)
                  (table.insert s.registry item)
                  false)}
               :UIComponent (fn [c] c)
               :CampaignUI
               {:TriggerCampaignScriptEvent
                (fn [cqi message] (table.insert s.ui-events [cqi message]))}
               :core
               {:add_listener (fn [_ key event condition callback]
                                (tset s.listeners key [condition callback]))
                :get_static_object (fn [_ key] (. objects key))
                :add_static_object (fn [_ key value] (tset objects key value))}
               :common {:set_context_value (fn [key value]
                                             (tset s.ui key value))}
               :out (fn []) :cco #(do {:Call (fn [] true)})}
              {:__index _G})]
    (set faction.character_list
      #(do {:num_items #(if s.no-prince? 0 1) :item_at (fn [] prince)}))
    (set faction.pooled_resource_manager
      #(do {:resource (fn [_ key] (resource s key))}))
    (set s.faction faction)
    (set s.reload #(load-module s env))
    (load-module s env)
    s))

(fn change [s key amount factor]
  (let [r (resource s key)
        context {:has_faction (fn [] true) :faction #(do s.faction)
                 :resource (fn [] r) :amount (fn [] amount)
                 :factor #(valid {:key (fn [] factor)})}
        listener s.listeners.everchosen_daemon_resource]
    (set r.amount (+ r.amount amount))
    (when ((. listener 1) context) ((. listener 2) context))))

(fn click [s action depth]
  (var entry {:Id #( .. "CcoCampaignPooledResource" glory "_FACTION_83")})
  (for [_ 1 depth]
    (let [parent entry] (set entry {:Parent (fn [] parent)})))
  (let [listener (. s.listeners (.. "everchosen_daemon_" action "_click"))]
    ((. listener 2) {:component entry})))

(fn command [s index]
  ((. s.listeners.everchosen_daemon_command 2)
    {:faction_cqi (fn [] 83) :trigger #(. s.ui-events index 2)}))

(describe "Daemon Prince campaign commands"
  (fn []
    (it "imports progression without resetting skills, including after reload"
      (fn []
        (let [s (scenario)]
          (set s.saved.everchosen_daemon_initialized nil)
          (set s.no-prince? true)
          (s.module.reconcile) (assert.equals 0 s.resets)
          (set s.no-prince? false)
          (s.module.reconcile) (assert.equals 0 s.resets)
          (let [r (resource s glory)] (set r.amount 1540))
          (s.module.reconcile)
          (s.reload) (s.module.reconcile)
          (assert.equals 0 s.resets)
          (assert.equals 1540 (: (resource s glory) :value))
          (assert.is_true s.character-bundles.everchosen_daemon_legion_khorne_2))))
    (it "routes UI clicks through the campaign command before charging"
      (fn []
        (let [s (scenario)]
          (s.module.start) (click s :sacrifice 3)
          (assert.equals 0 (length s.payloads))
          (command s 1)
          (assert.equals -100 (. s.payloads 1 :changes souls :amount)))))
    (it "accepts modified receipts without waiting for paused campaign timers"
      (fn []
        (let [s (scenario)]
          (s.module.start) (s.module.sacrifice glory)
          (s.module.sacrifice glory)
          (assert.equals 1 (length s.payloads))
          (change s souls -100 :gifts_of_chaos)
          (change s glory 107 :events)
          (change s souls 40000 :wh3_dlc20_souls_other)
          (change s spent 100 :path_to_glory)
          (s.module.sacrifice glory)
          (assert.equals 1 (length s.payloads))
          (change s spent 100 :gifts_of_chaos)
          (assert.is_false s.saved.everchosen_daemon_pending)
          (assert.equals 1 (. s.ui (.. "everchosen_daemon_can_" glory)))
          (s.module.sacrifice glory)
          (assert.equals 2 (length s.payloads)))))
    (it "dedicates once at the native threshold without spending glory"
      (fn []
        (let [s (scenario)]
          (s.module.start) (click s :dedication 4)
          (let [r (resource s glory)] (set r.amount 3079))
          (command s 1) (assert.equals 0 (length s.bundles))
          (let [r (resource s glory)] (set r.amount 3080))
          (set s.other-turn? true) (command s 1)
          (assert.equals 0 (length s.bundles))
          (set s.other-turn? false) (command s 1) (command s 1)
          (assert.same [:everchosen_daemon_dedicate_khorne] s.bundles)
          (assert.equals 3080 (: (resource s glory) :value))
          (assert.equals 0 (length s.payloads)))))
    (it "rejects missing princes, insufficient funds and full glory"
      (fn []
        (let [s (scenario)]
          (set s.no-prince? true) (s.module.sacrifice glory)
          (set s.no-prince? false)
          (let [r (resource s souls)] (set r.amount 99))
          (s.module.sacrifice glory)
          (let [r (resource s souls)] (set r.amount 1000))
          (let [r (resource s glory)] (set r.amount 3080))
          (s.module.sacrifice glory)
          (assert.equals 0 (length s.payloads)))))
    (it "replaces legion tiers on the prince without applying faction rewards"
      (fn []
        (let [s (scenario) r (resource s glory)]
          (set r.amount 770) (s.module.reconcile)
          (assert.is_true s.character-bundles.everchosen_daemon_legion_khorne_1)
          (set r.amount 1540) (s.module.reconcile)
          (assert.is_nil s.character-bundles.everchosen_daemon_legion_khorne_1)
          (assert.is_true s.character-bundles.everchosen_daemon_legion_khorne_2)
          (s.module.reconcile)
          (assert.equals 0 (length s.bundles)))))
    (it "acquires unlocked parts once without equipping them"
      (fn []
        (let [s (scenario) part :wh3_main_dae_cha_daemon_prince_torso_brasscollar_1]
          (let [r (resource s glory)] (set r.amount 110))
          (s.module.reconcile)
          (assert.is_truthy (string.find (table.concat s.grants ",") part 1 true))
          (set s.grants []) (s.module.reconcile)
          (assert.equals 0 (length s.grants)))))))
