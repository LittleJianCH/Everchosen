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
        (advance)
        (rpfm.assert_called :force_add_ancillary hero
                           :wh3_dlc25_anc_talisman_icon_of_decay true true)
        (rpfm.assert_called :force_add_ancillary hero
                           :wh3_dlc25_anc_weapon_sword_of_filth true true)
        (rpfm.assert_called :force_add_trait (lookup hero)
                           :wh3_dlc25_trait_chieftain_kazyk_antitrait true)
        (rpfm.assert_called :level_up_agent_rank (lookup hero) 1)
        (spawn-count 1)))))

(rpfm.test "rank 25 fills six missing chieftains sequentially and caps initial rank at 7"
  (fn []
    (let [tam (add-tam 25)]
      (advance)
      (each [_ subtype (ipairs heroes)]
        (request-for subtype tam)
        (let [hero (spawned subtype)]
          (advance)
          (rpfm.assert_called :level_up_agent_rank (lookup hero) 7)))
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
      (spawned (. heroes 3))
      (advance)
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
      (spawn-event (spawned (. heroes 1)))
      (advance)
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
    (rpfm.fire :FactionTurnStart {:faction host})
    (advance)
    (spawn-count 2)
    (rpfm.assert_not_called :force_add_ancillary)))

(rpfm.test "late confirmed spawn is initialized once after timeout"
  (fn []
    (add-tam 1)
    (advance)
    (rpfm.advance_time 5.1)
    (spawned (. heroes 1))
    (advance)
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
