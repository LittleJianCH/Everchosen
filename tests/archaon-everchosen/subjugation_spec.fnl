;; Command/confirmation boundaries, not an emulation of confederation or armies.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local native (assert (os.getenv :EVERCHOSEN_VANILLA_DB)))
(local host :wh_main_chs_chaos)
(local source-key :wh_dlc03_bst_beastmen)
(local client-key :wh_dlc03_bst_beastmen_chaos)
(local prefix "everchosen_subjugation_")
(local mod-path (.. root "/build/archaon-everchosen/script/campaign/mod/"))

(fn game-list [entries]
  {:num_items #(length entries)
   :item_at (fn [_ index] (. entries (+ index 1)))
   :is_empty #(= 0 (length entries))})

(fn record [s name value]
  (tset s.calls name (or (. s.calls name) []))
  (table.insert (. s.calls name) (or value true)))

(fn count-calls [s name] (length (or (. s.calls name) [])))

(fn faction [s key]
  (let [f {:key key :chars [] :regions [] :dead? false
           :is_null_interface (fn [] false)
           :name (fn [self] self.key)
           :is_human (fn [self] (= self.key (or s.player host)))
           :culture (fn [] :wh_dlc03_bst_beastmen)
           :command_queue_index (fn [self] self.key)
           :is_dead (fn [self] self.dead?)
           :has_faction_leader (fn [self] (not= self.leader nil))
           :faction_leader (fn [self] self.leader)
           :master (fn [self] self.overlord)
           :is_vassal_of (fn [self other] (= self.overlord other))
           :character_list (fn [self] (game-list self.chars))
           :military_force_list
           (fn [self] (game-list (or self.forces [])))
           :was_confederated (fn [self] (not= self.absorbed-by nil))
           :num_regions (fn [self] (length self.regions))
           :region_list (fn [self] (game-list self.regions))
           :was_confederated_by_faction
           (fn [self other]
             ;; API takes an interface, not its key.
             (assert.is_table other)
             (= self.absorbed-by other))}]
    (tset s.factions key f)
    f))

(fn character [s id owner subtype wounded?]
  (let [c {:id id :owner owner :subtype subtype :alive? (not wounded?)
           :is_null_interface (fn [] false)
           :cqi (fn [self] self.id)
           :faction (fn [self] self.owner)
           :character_type (fn [_ kind] (= kind :general))
           :character_subtype_key (fn [self] self.subtype)
           :character_subtype (fn [self kind] (= kind self.subtype))
           :is_alive (fn [self] self.alive?)
           :has_region (fn [] true)
           :region (fn [] {:name (fn [] :native_region)})
           :family_member
           (fn []
             {:is_null_interface (fn [] false)
              :command_queue_index (fn [] id)
              :character #(. s.characters id)})}]
    (set c.command_queue_index c.cqi)
    (tset s.characters id c)
    (table.insert owner.chars c)
    c))

(fn campaign-manager [s]
  {:get_campaign_name (fn [] :main_warhammer)
   :is_multiplayer (fn [] false)
   :get_human_factions #(do [(or s.player host)])
   :get_faction (fn [_ key] (. s.factions key))
   :get_saved_value (fn [_ key] (. s.saved key))
   :set_saved_value (fn [_ key value] (tset s.saved key value))
   :add_saving_game_callback (fn [])
   :add_loading_game_callback (fn [])
   :add_first_tick_callback (fn [])
   :add_pre_first_tick_callback (fn [])
   :callback (fn [_ callback] (table.insert s.queue callback))
   :turn_number #(do s.turn)
   :get_family_member_by_cqi
   (fn [_ id]
     (let [c (. s.characters id)] (and c (c:family_member))))
   :get_character_by_cqi (fn [_ id] (. s.characters id))
   :char_lookup_str (fn [_ id] (.. "character_cqi:" id))
   :kill_character
   (fn [_ lookup wound?]
     (assert.is_true wound?)
     (record s :wound lookup)
     (let [c (. s.characters (tonumber (lookup:match "%d+")))]
       (set c.alive? false)))
   :reassign_character
   (fn [_ id receiver]
     (assert.equals host receiver)
     ;; Ownership is deliberately not confirmed here.
     (record s :reassign id))
   :stop_character_convalescing (fn [_ id] (record s :recover id))
   :randomise_character_name (fn [])
   :change_localised_faction_name
   (fn [_ key name]
     (assert.equals client-key key)
     (record s :rename name))
   :find_valid_spawn_location_for_character_from_settlement
   (fn [] (values (if s.no-spawn? -1 1) 2))
   :awaken_faction_from_death (fn [_ f] (record s :awaken (f:name)))
   :awaken_faction_from_death_with_region
   (fn [_ f]
     (record s :resurrect (f:name))
     (set f.dead? false))
   :create_force_with_general
   (fn [_ key units region x y kind subtype a b c d leader? callback]
     (assert.equals (or s.expected-client client-key) key)
     ;; No reconstruction of the legendary lord's army.
     (assert.is_nil units)
     (assert.is_true leader?)
     (record s :create key)
     (set s.created callback))
   :force_make_vassal
   (fn [_ owner key]
     (assert.equals host owner)
     (record s :vassal key))
   :create_payload
   (fn []
     {:form_confederation
      (fn [_ receiver source dead? keep?]
        (assert.equals s.client receiver)
        (assert.equals s.source source)
        (assert.is_false dead?)
        (assert.is_true keep?))})
   :apply_payload #(record s :merge)
   :kill_faction (fn [_ key] (record s :kill_faction key))
   :trigger_dilemma_with_targets
   (fn [_ winner key a b c d e f callback]
     (record s :dilemma key)
     (callback))
   :model (fn [] {:manual_saves_disabled (fn [] false)})})

(fn require-module [env name]
  (when (not (. env.package.loaded name))
    (tset env.package.loaded name ((assert (. env.package.preload name)))))
  (. env.package.loaded name))

(fn campaign-environment [s]
  (let [env (setmetatable
              {:cm (campaign-manager s) :dpairs pairs
               :out (fn [message] (table.insert s.logs message))
               :core
               {:get_static_object (fn [_ key] (. s.objects key))
                :add_static_object
                (fn [_ key value] (tset s.objects key value))
                :trigger_event (fn [_ event key] (record s :completed key))
                :add_listener
                (fn [_ key event condition callback]
                  (tset s.listeners key [condition callback]))}}
              {:__index _G})]
    ;; Match CA's separate campaign environment and global registry.
    (set env._G (setmetatable {:campaign_env env} {:__index _G}))
    (set env.core.get_env (fn [] env))
    (set env.package {:preload {} :loaded {}})
    (set env.require #(require-module env $1))
    env))

(fn load-script [s path] ((setfenv (assert (loadfile path)) s.env)))

(fn flush [s]
  (let [queue s.queue]
    (set s.queue [])
    (each [_ callback (ipairs queue)] (callback))))

(fn start [s]
  (let [env s.env]
    (load-script s (.. native
                       "/script/campaign/wh3_dlc29_archaon_subjugation.lua"))
    (set s.original-accept env.archaon_subjugation.subjugate_chaos_faction)
    (load-script s (.. mod-path "everchosen_inheritance_data.lua"))
    (load-script s (.. mod-path "everchosen_archaon.lua"))
    (let [module (env.require :everchosen_subjugation.campaign)]
      (module.start))
    (set s.manager env.archaon_subjugation)
    (s:flush)))

(fn accept [s]
  (s.manager:subjugate_chaos_faction s.source)
  (s:flush))

(fn confirm-client [s]
  (set s.client.dead? false)
  (set s.client.leader (s:character 3 s.client :wh_dlc03_bst_beastlord))
  (set s.client.overlord s.host)
  (when s.created (s.created 3)))

(fn campaign [saved]
  (let [s {:saved (or saved {}) :factions {} :characters {} :queue []
           :calls {} :objects {} :listeners {} :logs [] :turn 1
           :count count-calls : faction : character : flush : start : accept
           : confirm-client}]
    (set s.host (s:faction host))
    (set s.source (s:faction source-key))
    (set s.client (s:faction client-key))
    (set s.host.leader (s:character 1 s.host :wh_main_chs_archaon))
    (set s.lord (s:character 2 s.source :wh_dlc03_bst_khazrak))
    (set s.source.leader s.lord)
    (set s.client.dead? true)
    (set s.env (campaign-environment s))
    s))

(describe "Extended subjugation"
  (fn []
    (it "keeps Daniel's faction and confirms its successor before transferring"
      (fn []
        (let [s (campaign) key :wh3_main_dae_daemon_prince]
          (set s.source (s:faction key))
          (set s.source.culture (fn [] :wh3_main_dae_daemons))
          (set s.lord (s:character 2 s.source key))
          (set s.source.leader s.lord)
          (set s.expected-client key)
          (s:start) (s:accept) (s:accept)
          (assert.equals 1 (s:count :create))
          (assert.equals 0 (s:count :reassign))
          ;; Completion without a valid faction leader cannot release Daniel.
          (s.created nil) (s:accept)
          (assert.equals 0 (s:count :reassign))
          (let [successor (s:character 3 s.source
                            :wh3_dlc20_chs_daemon_prince_undivided)]
            (set s.source.leader successor)
            (s:accept)
            (assert.equals 1 (s:count :vassal))
            (assert.equals 0 (s:count :reassign))
            (set s.source.overlord s.host)
            ((. s.listeners (.. prefix "turn") 2)) (s:flush)
            (assert.same [2] s.calls.reassign)
            (set s.lord.owner s.host)
            (set s.host.chars [s.host.leader s.lord])
            ((. s.listeners (.. prefix "turn") 2)) (s:flush)
            (assert.is_true (. s.saved (.. prefix "completed") key))
            (assert.equals s.source successor.owner)
            (assert.equals 0 (s:count :merge))
            (assert.equals 0 (s:count :kill_faction))))))

    (it "leaves a borrowed faction alone when another mod has activated it"
      (fn []
        (let [s (campaign)]
          (set s.client.dead? false)
          (set s.client.forces [{}])
          (s:start)
          (s:accept)
          (s.manager:trigger_archaon_confederation_dilemma s.host s.source)
          (assert.equals 0 (s:count :dilemma))
          (assert.equals 0 (s:count :rename))
          (assert.equals 0 (s:count :create))
          (assert.equals 0 (s:count :vassal))
          (assert.equals 0 (s:count :merge)))))

    (it (.. "waits for a valid client and merger, "
            "then transfers only accepted lords")
      (fn []
        (let [s (campaign)]
          (s:start)
          (let [wounded (s:character 4 s.source :wh_dlc03_bst_malagor true)
                ordinary (s:character 5 s.source :wh_dlc03_bst_beastlord)]
            (s:accept)
            (s:accept)
            (assert.equals 1 (s:count :create))
            (assert.equals 0 (s:count :merge))
            (assert.equals 0 (s:count :reassign))
            (s:confirm-client)
            (s:accept)
            (assert.equals 1 (s:count :merge))
            (assert.equals 0 (s:count :reassign))
            (set s.source.absorbed-by s.client)
            (set s.source.dead? true)
            (set s.lord.owner s.client)
            (set wounded.owner s.client)
            (set ordinary.owner s.client)
            (s:accept)
            (assert.same ["character_cqi:2"] s.calls.wound)
            (assert.equals 2 (s:count :reassign))
            (assert.is_nil (. s.saved (.. prefix "completed")))
            (assert.equals s.client ordinary.owner)
            (set s.lord.owner s.host)
            (set wounded.owner s.host)
            (set s.host.chars [s.host.leader s.lord wounded])
            ;; Accepted work resumes from saved IDs after eligibility ends.
            ((. s.listeners (.. prefix "turn") 2))
            (s:flush)
            (assert.is_true (. s.saved (.. prefix "completed") source-key))
            (assert.equals 1 (s:count :completed))
            (s:accept)
            (assert.equals 1 (s:count :completed))
            (assert.equals 0 (s:count :kill_faction))))))

    (it "does not merge after an invalid spawn and resumes a saved merger"
      (fn []
        (let [s (campaign)]
          (set s.no-spawn? true)
          (s:start)
          (s:accept)
          (assert.equals 0 (s:count :create))
          (assert.equals 0 (s:count :merge))
          (assert.equals 0 (s:count :rename))
          (assert.is_nil (. s.saved (.. prefix "claimed_clients")))
          (set s.no-spawn? false)
          (s:accept)
          (s:confirm-client)
          (s:accept)
          (let [loaded (campaign s.saved)]
            (loaded:confirm-client)
            (set loaded.source.absorbed-by loaded.client)
            (set loaded.source.dead? true)
            (set loaded.lord.owner loaded.client)
            (loaded:start)
            (assert.equals 0 (loaded:count :create))
            (assert.equals 0 (loaded:count :merge))
            (assert.is_true (> (loaded:count :reassign) 0))))))

    (it "recovers a destroyed faction's lord without creating a client"
      (fn []
        (let [s (campaign)]
          (set s.source.dead? true)
          (set s.lord.alive? false)
          (s:start)
          (s:accept)
          ;; Actual CA resurrection helper.
          (assert.equals 1 (s:count :resurrect))
          (assert.equals 0 (s:count :create))
          (assert.equals 0 (s:count :merge))
          (set s.lord.owner s.host)
          (set s.host.chars [s.host.leader s.lord])
          ((. s.listeners (.. prefix "turn") 2))
          (s:flush)
          (assert.equals 1 (s:count :kill_faction))
          (assert.equals 1 (s:count :completed)))))

    (it (.. "keeps the native reject choice and excludes human vassals "
            "and other players")
      (fn []
        (let [s (campaign)]
          (s:start)
          (s.manager:trigger_archaon_confederation_dilemma s.host s.source)
          (assert.equals 1 (s:count :dilemma))
          (let [listener s.listeners.ArchaonConfederationDilemmaChoiceMadeEvent
                choice {:dilemma #(.. prefix "accept")
                        :choice (fn [] 1)}]
            (assert.is_true ((. listener 1) choice))
            ((. listener 2) choice)
            (s:flush)
            (assert.equals 0 (s:count :create))
            (assert.is_nil (. s.saved (.. prefix "pending")))
            (set s.source.overlord s.host)
            (s:accept)
            (assert.equals 0 (s:count :create))))
        (let [s (campaign)]
          (set s.player source-key)
          (s:start)
          (assert.equals s.original-accept
                         s.manager.subjugate_chaos_faction))))))
