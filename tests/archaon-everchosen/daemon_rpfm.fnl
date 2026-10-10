;; Run the daemon adapter with CA libraries and Assembly Kit typed fixtures.
;; Command completion is supplied independently; this is not the game engine.
(local fire rpfm.fire)
(set rpfm.fire
  (fn [event context]
    (fire (if (= event :TimeTrigger) :CampaignTimeTrigger event) context)))
(set os.clock #(do rpfm.world.time))
(local host-key :wh_main_chs_chaos)
(local prince-key :wh3_main_dae_daemon_prince)
(local souls :wh3_dlc20_chs_souls)
(local glory :wh3_main_dae_khorne_points)
(local spent :wh3_dlc20_chs_souls_spent_kho)
(local balances {souls 1000})
(local resources {})
(fn resource [key]
  (when (not (. resources key))
    (tset resources key
      (rpfm.object :POOLED_RESOURCE_SCRIPT_INTERFACE
        {:value #(or (. balances key) 0) :maximum_value 3080})))
  (. resources key))
(local manager (rpfm.object :POOLED_RESOURCE_MANAGER_SCRIPT_INTERFACE
                            {: resource}))
(local characters [])
;; Suppress unrelated feature startup, then start this adapter explicitly.
(local host (rpfm.faction {:key host-key :is_human false
                           :command_queue_index 100
                           :character_list characters
                           :pooled_resource_manager manager}))
(local inventory [])
(local armory (rpfm.object :ARMORY_SCRIPT_INTERFACE
                {:get_currently_registered_armory_items inventory}))
(local family (rpfm.object :FAMILY_MEMBER_SCRIPT_INTERFACE {: armory}))
(local prince (rpfm.character {:faction host :family_member family
                              :character_subtype_key prince-key
                              :command_queue_index 101 :cqi 101
                              :is_wounded true}))

(fn start []
  (rpfm.mock host :is_human true)
  (table.insert characters prince)
  (rpfm.mock (: (: (GAME) :model) :world) :is_factions_turn_by_key
             #(= $1 host-key))
  (set cm.local_faction_name host-key)
  (let [daemon (require :everchosen_daemon.campaign)]
    (daemon.start)
    daemon))

(rpfm.test "typed payload debits souls and credits glory plus native sacrifice total"
  (fn []
    (start)
    (rpfm.assert_called :unlock_ritual host
                       :everchosen_daemon_dedicate_khorne 0)
    (rpfm.fire :UITrigger {:faction_cqi 999
      :trigger (.. "everchosen_daemon_sacrifice:" glory)})
    (rpfm.assert_not_called :apply_payload)
    (rpfm.fire :UITrigger {:faction_cqi 100
      :trigger (.. "everchosen_daemon_sacrifice:" glory)})
    (rpfm.assert_called :faction_pooled_resource_transaction
                       souls :gifts_of_chaos -100 false)
    (rpfm.assert_called :faction_pooled_resource_transaction
                       glory :events 100 false)
    (rpfm.assert_called :faction_pooled_resource_transaction
                       spent :gifts_of_chaos 100 false)
    (rpfm.assert_equal (length (rpfm.calls_to :apply_payload)) 1)))

(rpfm.test "native armory interface acquires the threshold part without equipping"
  (fn []
    (let [daemon (start)]
      (tset balances glory 110)
      (daemon.reconcile)
      (rpfm.assert_called :add_armory_item_to_character prince
        :wh3_main_dae_cha_daemon_prince_torso_brasscollar_1 false false)
      (rpfm.assert_not_called :equip_armory_item_variant_on_character)
      (rpfm.assert_not_called :unequip_all_armory_items_from_character))))
