(local data (include :everchosen_inheritance.data))
(local world (include :everchosen_inheritance.world))

(local opened-key (.. data.prefix "starting_portal"))

(fn network [config]
  (let [game-world (world.game-world)
        system (game-world:teleportation_network_system)]
    (system:lookup_network config.network)))

(fn opened? [config key]
  (let [net (network config)]
    (when (world.valid? net)
      (let [node (net:lookup_open_node key)]
        (and (world.valid? node) (= (node:record_key) key)
             (= (node:template_key) config.template))))))

(fn confirm [config key]
  (if (opened? config key)
      (cm:set_saved_value opened-key key)
      (out (.. "[Everchosen portals] Starting node did not open: " key))))

(fn start []
  ;; Only campaign creation opens a node. Loading never reopens a closed rift.
  (let [host (world.host)]
    (when (and host (cm:is_new_game) (not (cm:get_saved_value opened-key)))
      (let [leader (host:faction_leader)
            generated (core:get_static_object :everchosen_inheritance_data)
            config generated.portals]
        (when (and (world.valid? leader) (leader:has_region))
          (let [region (leader:region)
                province (and (world.valid? region) (region:province))
                key (and (world.valid? province) (province:key))]
            (if (and key (. config.nodes key))
                (do
                  (when (not (opened? config key))
                    (cm:teleportation_network_open_node key))
                  (cm:callback #(confirm config key) 0.2))
                (out
                  "[Everchosen portals] No native node in starting province"))))))))

{: start}
