;; Execute CA's river implementation: the fixture only stores region bundles.
;; This checks script integration, not combat or effect execution in the engine.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local native (assert (os.getenv :EVERCHOSEN_VANILLA_DB)))
(local host :wh_main_chs_chaos)
(local taurox :wh2_dlc17_bst_taurox)

(fn scenario []
  (let [s {:owner host :subtype taurox :human? true :multiplayer? false
           :won? true :skills {} :bundles {} :applications [] :objects {}
           :attacker-result :victory :forwarded 0}
        faction {:is_null_interface (fn [] false) :name #(do s.owner)
                 :is_human #(do s.human?)}
        region {:is_null_interface #(not (not s.sea?))
                :name (fn [] :battle_region)
                :has_effect_bundle (fn [_ key] (. s.bundles key))}
        character {:is_null_interface (fn [] false)
                   :faction (fn [] faction)
                   :character_subtype_key #(do s.subtype)
                   :won_battle #(do s.won?) :region (fn [] region)
                   :military_force (fn [] {})
                   :has_skill (fn [_ key] (. s.skills key))}
        env (setmetatable
          {:package {:preload {} :loaded {}} :out (fn [])
           :core {:get_static_object (fn [_ key] (. s.objects key))
                  :add_static_object (fn [_ key value]
                                       (tset s.objects key value))}
           :cm {:get_faction (fn [] faction)
                :get_campaign_name (fn [] :main_warhammer)
                :is_multiplayer #(do s.multiplayer?)
                :add_first_tick_callback (fn [])
                :add_pre_first_tick_callback (fn [])
                :add_saving_game_callback (fn [])
                :add_loading_game_callback (fn [])
                :model #(do {:pending_battle
                  (fn [] {:attacker_battle_result #(do s.attacker-result)})})
                :remove_effect_bundle_from_region
                (fn [_ key target]
                  (assert.equals :battle_region target)
                  (tset s.bundles key nil))
                :apply_effect_bundle_to_region
                (fn [_ key target duration]
                  (assert.equals :battle_region target)
                  (tset s.bundles key duration)
                  (table.insert s.applications key))}}
          {:__index _G})]
    ;; CA loads campaign scripts in core's environment, separate from _G.
    (set env.core.get_env (fn [] env))
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile (.. native
       "/script/campaign/wh2_dlc17_taurox_rampage.lua"))) env))
    (let [original env.TauroxRampage_BattleCompleted]
      (set env.TauroxRampage_BattleCompleted
        (fn [context]
          (set s.forwarded (+ s.forwarded 1))
          (original context))))
    (each [_ file (ipairs [:everchosen_core_data.lua
                           :everchosen_archaon.lua])]
      ((setfenv (assert (loadfile (.. root
        "/build/archaon-everchosen/script/campaign/mod/" file))) env)))
    (let [adapter (env.require :everchosen_subjugation.river_of_blood)]
      (adapter.start)
      (adapter.start))
    (set s.battle #(env.TauroxRampage_BattleCompleted
                    {:character (fn [] character)}))
    (set s.config (. s.objects :everchosen_core_data :subjugation :river_of_blood))
    (set s.native env.RiverOfBlood)
    s))

(describe "Transferred Taurox's native River of Blood"
  (fn []
    (it "keeps native stacking, cap and duration with the replacement skill"
      (fn []
        (let [s (scenario) bundles s.native.bundle_keys]
          (s.battle)
          (assert.equals 5 (. s.bundles (. bundles 1)))
          (set s.bundles {})
          (tset s.skills s.config.skill true)
          (s.battle)
          (assert.equals 5 (. s.bundles (. bundles 2)))
          (s.battle)
          (assert.equals 5 (. s.bundles (. bundles 3)))
          (assert.is_nil (. s.bundles (. bundles 2)))
          (s.battle)
          (assert.equals 5 (. s.bundles (. bundles 3)))
          (let [before (length s.applications)]
            (set s.won? false) (s.battle)
            (set s.won? true) (set s.sea? true) (s.battle)
            (assert.equals before (length s.applications)))
          (assert.equals 0 s.forwarded))))
    (it "leaves the original faction and unrelated actors on the native handler"
      (fn []
        (let [s (scenario)]
          ;; A defensive native victory avoids unrelated momentum fixtures.
          (set s.attacker-result :defeat)
          (set s.owner taurox)
          (tset s.skills s.native.skill_key true)
          (s.battle)
          (assert.equals 1 s.forwarded)
          (assert.equals 5 (. s.bundles (. s.native.bundle_keys 2)))
          (set s.owner host) (set s.subtype :other_lord) (s.battle)
          (assert.equals 2 s.forwarded)
          (set s.subtype taurox) (set s.multiplayer? true) (s.battle)
          (assert.equals 3 s.forwarded))))))
