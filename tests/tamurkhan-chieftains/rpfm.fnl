;;; RPFM runs the real WH3 libraries with typed engine fixtures.
;;; Spawn requests do not auto-succeed; tests supply observed completions.

;; RPFM 5.1.1 emits TimeTrigger; the native single-player timer listens for
;; CampaignTimeTrigger and also checks os.clock.
(local fire rpfm.fire)
(set rpfm.fire
     (fn [event context]
       (fire (if (= event :TimeTrigger) :CampaignTimeTrigger event) context)))
(set os.clock #(do rpfm.world.time))

;; Native cm:add_agent_experience(..., true) calls this undocumented command.
;; Record requests only; do not pretend to simulate rank changes.
(rpfm.mock (GAME) :level_up_agent_rank (fn []))

(local host-key :wh_main_chs_chaos)
(local tamurkhan-key :wh3_dlc25_nur_tamurkhan)
(local heroes
       [:wh3_dlc25_nur_kayzk_the_befouled
        :wh3_dlc25_nur_skin_wolf_werekin_chieftain
        :wh3_dlc25_nur_exalted_hero_chieftain
        :wh3_dlc25_nur_bray_shaman_wild_chieftain
        :wh3_dlc25_nur_fimir_balefiend_shadow_chieftain
        :wh3_dlc25_nur_castellan_chieftain])
(local characters [])
(local agents [])
(local regions [])
;; The official docs describe a list but label the return as a single
;; UNIQUE_AGENT_DETAILS_SCRIPT_INTERFACE. Supply the list explicitly.
(local host
       (rpfm.faction
         {:key host-key :is_human true :command_queue_index 100
          :character_list characters :region_list regions
          :unique_agents
          (rpfm.list :UNIQUE_AGENT_DETAILS_LIST_SCRIPT_INTERFACE agents)}))
(local other
       (rpfm.faction
         {:key tamurkhan-key :character_list []
          :unique_agents
          (rpfm.list :UNIQUE_AGENT_DETAILS_LIST_SCRIPT_INTERFACE [])}))

;; Distinct character IDs keep event correlation observable within each test.
(var next-id 1000)
(fn character [subtype rank owner wounded?]
  (set next-id (+ next-id 1))
  (rpfm.character
    {:faction (or owner host) :character_subtype_key subtype
     :rank (or rank 1) :cqi next-id :command_queue_index next-id
     :is_wounded (or wounded? false) :has_region (not wounded?)}))

(fn add-tam [rank wounded?]
  (let [tam (character tamurkhan-key rank host wounded?)]
    (table.insert characters tam)
    tam))

(fn advance [] (rpfm.advance_time 0.3))

(fn unique-agent [hero]
  (rpfm.object :UNIQUE_AGENT_DETAILS_SCRIPT_INTERFACE {:character hero}))

(fn spawn-event [hero]
  (rpfm.fire :UniqueAgentSpawned {:unique_agent_details (unique-agent hero)}))

(fn spawned [subtype]
  (let [hero (character subtype)]
    (table.insert characters hero)
    (spawn-event hero)
    hero))

(fn lookup [hero] (.. "character_cqi:" (hero:cqi)))

(fn no-spawn []
  (rpfm.assert_not_called :spawn_unique_agent_at_character)
  (rpfm.assert_not_called :spawn_unique_agent_at_region))

(fn spawn-count [expected]
  (rpfm.assert_equal
    (+ (length (rpfm.calls_to :spawn_unique_agent_at_character))
       (length (rpfm.calls_to :spawn_unique_agent_at_region)))
    expected))

(fn request-for [subtype anchor]
  (rpfm.assert_called :spawn_unique_agent_at_character
                     100 subtype (anchor:command_queue_index) true))

;; Expected observations are supplied independently of the command mocks.
;; This checks the adapter protocol, not the engine's equipment/rank changes.
(local equipment
       [[:wh3_dlc25_anc_talisman_icon_of_decay
         :wh3_dlc25_anc_weapon_sword_of_filth]
        [:wh3_dlc25_anc_talisman_unkind_taint]
        [:wh3_dlc25_anc_talisman_virulent_boon]
        [:wh3_dlc25_anc_talisman_reeking_talisman]
        [:wh3_dlc25_anc_talisman_sigil_of_madness]
        [:wh3_dlc25_anc_talisman_cursed_yhetee_jawbone]])
(local traits
       [:wh3_dlc25_trait_chieftain_kazyk_antitrait
        :wh3_dlc25_trait_chieftain_werekin_antitrait
        :wh3_dlc25_trait_chieftain_exalted_hero_antitrait
        :wh3_dlc25_trait_chieftain_bray_shaman_antitrait
        :wh3_dlc25_trait_chieftain_fimir_balefiend_antitrait
        :wh3_dlc25_trait_chieftain_castellan_antitrait])

(fn observe-initialization [hero index rank]
  (let [observed {}]
    (rpfm.mock hero :has_ancillary #(or (. observed $1) false))
    (advance)
    (each [_ key (ipairs (. equipment index))]
      (rpfm.assert_called :force_add_ancillary hero key true true)
      (tset observed key true)
      (rpfm.advance_time 1.3))
    (rpfm.assert_called :force_add_trait (lookup hero) (. traits index) true)
    (rpfm.mock hero :trait_points #(if (= $1 (. traits index)) 1 0))
    (rpfm.advance_time 1.3)
    (when (> rank 1)
      (rpfm.assert_called :level_up_agent_rank (lookup hero) (- rank 1)))
    (rpfm.mock hero :rank rank)
    (rpfm.advance_time 1.5)))

(rpfm.test "without owned Tamurkhan no chieftain is requested"
  (fn []
    (advance)
    (no-spawn)))

(rpfm.test "rank 1 requests Kayzk and rewards only a confirmed owned spawn"
  (fn []
    (let [tam (add-tam 1)]
      (advance)
      (request-for (. heroes 1) tam)
      (rpfm.assert_not_called :force_add_ancillary)
      (rpfm.assert_not_called :force_add_trait)
      (let [hero (spawned (. heroes 1))]
        (observe-initialization hero 1 1)
        (rpfm.assert_called :force_add_ancillary hero
                           :wh3_dlc25_anc_talisman_icon_of_decay true true)
        (rpfm.assert_called :force_add_ancillary hero
                           :wh3_dlc25_anc_weapon_sword_of_filth true true)
        (rpfm.assert_called :force_add_trait (lookup hero)
                           :wh3_dlc25_trait_chieftain_kazyk_antitrait true)
        (rpfm.assert_not_called :level_up_agent_rank)
        (spawn-count 1)))))

(rpfm.test "rank 25 fills six missing chieftains sequentially and caps initial rank at 7"
  (fn []
    (let [tam (add-tam 25)]
      (advance)
      (each [index subtype (ipairs heroes)]
        (request-for subtype tam)
        (let [hero (spawned subtype)]
          (observe-initialization hero index 7)
          (rpfm.assert_called :level_up_agent_rank (lookup hero) 6)))
      (spawn-count 6)
      (rpfm.assert_equal (length (rpfm.calls_to :force_add_trait)) 6)
      (rpfm.assert_equal (length (rpfm.calls_to :force_add_ancillary)) 7)
      (rpfm.fire :FactionTurnStart {:faction host})
      (advance)
      (spawn-count 6))))

(rpfm.test "rank threshold crosses from one owned hero at 4 to two at 5"
  (fn []
    (let [tam (add-tam 4)]
      (table.insert characters (character (. heroes 1)))
      (advance)
      (no-spawn)
      (rpfm.mock tam :rank 5)
      (rpfm.fire :CharacterRankUp {:character tam})
      (advance)
      (request-for (. heroes 2) tam)
      (spawn-count 1))))

(rpfm.test "wounded owned unique hero counts and is not duplicated"
  (fn []
    (let [tam (add-tam 5)]
      (tset agents 1 (unique-agent (character (. heroes 1) 1 host true)))
      (advance)
      (request-for (. heroes 2) tam)
      (spawn-count 1))))

(rpfm.test "unlocked registry entry without a character does not count as ownership"
  (fn []
    (let [tam (add-tam 1)]
      (tset agents 1 (unique-agent (rpfm.null :CHARACTER_SCRIPT_INTERFACE)))
      (advance)
      (request-for (. heroes 1) tam))))

(rpfm.test "subjugation reconciliation counts transferred heroes before filling the shortfall"
  (fn []
    (advance)
    (no-spawn)
    (let [tam (add-tam 10)
          kayzk (character (. heroes 1) 1 other true)
          mournhowl (character (. heroes 2) 1 other)]
      (rpfm.mock other :character_list [kayzk mournhowl])
      (rpfm.fire :ScriptEventArchaonSubjugatesChaosFaction)
      (no-spawn)
      ;; Ownership settles before the queued reconciliation runs.
      (rpfm.mock kayzk :faction host)
      (rpfm.mock mournhowl :faction host)
      (rpfm.mock other :character_list [])
      (tset agents 1 (unique-agent kayzk))
      (table.insert characters mournhowl)
      (advance)
      (request-for (. heroes 3) tam)
      (spawn-count 1)
      (observe-initialization (spawned (. heroes 3)) 3 7)
      (spawn-count 1)
      (rpfm.fire :FactionTurnStart {:faction host})
      (advance)
      (spawn-count 1))))

(rpfm.test "wounded Tamurkhan falls back to an available Archaon"
  (fn []
    (add-tam 1 true)
    (let [archaon (character :chs_archaon)]
      (table.insert characters archaon)
      (advance)
      (request-for (. heroes 1) archaon))))

(rpfm.test "both lords unavailable falls back to an owned home region"
  (fn []
    (add-tam 1 true)
    (let [home (rpfm.region {:key :wh3_main_combi_region_the_writhing_fortress
                             :cqi 200 :owning_faction host})]
      (tset regions 1 home)
      (rpfm.mock host :home_region home)
      (advance)
      (rpfm.assert_called :spawn_unique_agent_at_region
                         100 (. heroes 1) 200 true)
      (rpfm.assert_not_called :spawn_unique_agent_at_character))))

(rpfm.test "no usable character or owned region defers spawning"
  (fn []
    (add-tam 25 true)
    (advance)
    (no-spawn)))

(rpfm.test "duplicate rank and spawn events do not duplicate requests or rewards"
  (fn []
    (let [tam (add-tam 1)]
      (advance)
      (for [_ 1 3] (rpfm.fire :CharacterRankUp {:character tam}))
      (advance)
      (spawn-count 1)
      (let [hero (spawned (. heroes 1))]
        (spawn-event hero)
        (observe-initialization hero 1 1))
      (spawn-count 1)
      (rpfm.assert_equal (length (rpfm.calls_to :force_add_ancillary)) 2))))

(rpfm.test "unrelated spawn cannot initialize the pending hero"
  (fn []
    (add-tam 1)
    (advance)
    (spawn-event (character (. heroes 1) 1 other))
    (rpfm.assert_not_called :force_add_ancillary)
    (spawn-count 1)))

(rpfm.test "unconfirmed command waits and retries on the following host turn"
  (fn []
    (add-tam 1)
    (advance)
    (rpfm.advance_time 5.1)
    (spawn-count 1)
    (rpfm.fire :FactionTurnStart {:faction other})
    (advance)
    (spawn-count 1)
    (set rpfm.world.turn (+ rpfm.world.turn 1))
    (rpfm.fire :FactionTurnStart {:faction host})
    (advance)
    (spawn-count 2)
    (rpfm.assert_not_called :force_add_ancillary)))

(rpfm.test "late confirmed spawn is initialized once after timeout"
  (fn []
    (add-tam 1)
    (advance)
    (rpfm.advance_time 5.1)
    (observe-initialization (spawned (. heroes 1)) 1 1)
    (spawn-count 1)
    (rpfm.assert_equal (length (rpfm.calls_to :force_add_ancillary)) 2)))

(fn mct-with-second-hero-first []
  {:get_mod_by_key
   (fn []
     {:get_option_by_key
      (fn [_ key]
        {:get_finalized_setting
         #(if (= key :priority_1) (. heroes 2))})})})

(rpfm.test "MCT finalized settings change priority without requiring MCT at startup"
  (fn []
    (let [tam (add-tam 1)]
      (set _G.get_mct mct-with-second-hero-first)
      (rpfm.fire :MctFinalized)
      (advance)
      (request-for (. heroes 2) tam))))

(local ticket-key :everchosen_tamurkhan_chieftains_active_ticket)

(fn next-host-turn []
  (set rpfm.world.turn (+ rpfm.world.turn 1))
  (rpfm.fire :FactionTurnStart {:faction host})
  (advance))

(rpfm.test "failed trait initialization resumes without reissuing observed equipment"
  (fn []
    (add-tam 1)
    (advance)
    (rpfm.mock (GAME) :force_add_trait #(error "injected trait failure"))
    (let [hero (spawned (. heroes 1))]
      (advance)
      ;; Supply an observed equipment result independently of the commands.
      (rpfm.mock hero :has_ancillary true)
      (rpfm.advance_time 5.1)
      (rpfm.assert_equal (length (rpfm.calls_to :force_add_trait)) 1)
      (let [equipment-count (length (rpfm.calls_to :force_add_ancillary))]
        (rpfm.mock (GAME) :force_add_trait (fn []))
        (next-host-turn)
        (rpfm.assert_equal (length (rpfm.calls_to :force_add_trait)) 2)
        (rpfm.assert_equal (length (rpfm.calls_to :force_add_ancillary))
                           equipment-count)
        (spawn-count 1)
        ;; A successful command alone must not mark initialization complete.
        (rpfm.assert_equal (type (cm:get_saved_value ticket-key)) :table)
        (rpfm.mock hero :trait_points 1)
        (rpfm.advance_time 1.3)
        (rpfm.assert_equal (cm:get_saved_value ticket-key) false)
        (spawn-count 1)))))

(fn reload-mod []
  ;; Exercise native saved-value serialization and fresh module locals.
  ;; This is not a simulation of the engine's save/load lifecycle.
  (let [saved (cm:saved_values_to_string)
        first-tick cm.add_first_tick_callback]
    (each [_ suffix (ipairs [:spawn :rank :turn :MctInitialized :MctFinalized
                             :subjugation])]
      (core:remove_listener (.. "everchosen_tamurkhan_chieftains_" suffix)))
    (set cm.saved_values {})
    (cm:load_values_from_string saved)
    (set cm.add_first_tick_callback (fn [_ callback] (callback)))
    (dofile "script/campaign/mod/everchosen_tamurkhan_chieftains.lua")
    (set cm.add_first_tick_callback first-tick)))

(each [_ scope (ipairs [{:name "AI Archaon" :human? false}
                        {:name "multiplayer" :multiplayer? true}
                        {:name "another campaign" :campaign :wh3_main_chaos}])]
  (rpfm.test (.. scope.name " cannot spawn or reward chieftains")
    (fn []
      (let [tam (add-tam 25)]
        (when (= scope.human? false) (rpfm.mock host :is_human false))
        ;; Native 9.0.3 cm accessors read these campaign setup fields.
        (when scope.multiplayer?
          (set cm.is_multiplayer_campaign true))
        (when scope.campaign (set cm.name scope.campaign))
        (reload-mod)
        (advance)
        (rpfm.fire :CharacterRankUp {:character tam})
        (rpfm.fire :FactionTurnStart {:faction host})
        (rpfm.fire :ScriptEventArchaonSubjugatesChaosFaction)
        (spawned (. heroes 1))
        (rpfm.advance_time 6)
        (no-spawn)
        (rpfm.assert_not_called :force_add_ancillary)
        (rpfm.assert_not_called :force_add_trait)
        (rpfm.assert_not_called :level_up_agent_rank)))))

(rpfm.test "reload restores spawn and initialization without repeating uncertain commands"
  (fn []
    (let [tam (add-tam 4)]
      (advance)
      (rpfm.advance_time 5.1)
      (reload-mod)
      (advance)
      (spawn-count 1)
      (rpfm.mock tam :faction other)
      (next-host-turn)
      (spawn-count 1)
      (rpfm.mock tam :faction host))
    (let [hero (spawned (. heroes 1))]
      (advance)
      (rpfm.mock hero :has_ancillary true)
      (rpfm.mock hero :trait_points 1)
      (rpfm.advance_time 5.1)
      (rpfm.assert_called :level_up_agent_rank (lookup hero) 3)
      (rpfm.assert_equal (type (cm:get_saved_value ticket-key)) :table)
      (reload-mod)
      (advance)
      (next-host-turn)
      (rpfm.advance_time 5.1)
      (rpfm.assert_equal (length (rpfm.calls_to :level_up_agent_rank)) 1)
      (rpfm.assert_equal (type (cm:get_saved_value ticket-key)) :table)
      (spawn-count 1)
      (rpfm.mock hero :rank 4)
      (next-host-turn)
      (rpfm.assert_equal (cm:get_saved_value ticket-key) false)
      (spawn-count 1))))
