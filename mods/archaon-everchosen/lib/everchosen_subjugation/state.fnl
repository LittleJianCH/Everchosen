;;; Saved operation keys and queries shared by subjugation adapters.

(local world (include :everchosen_core.world))

(local prefix "everchosen_subjugation_")
(local pending-key (.. prefix "pending"))
(local done-key (.. prefix "completed"))
(local challenge-key (.. prefix "challenges"))
(local clients-key (.. prefix "claimed_clients"))

(fn config []
  (. (world.static-data) :subjugation))

(fn targets [] (. (config) :targets))
(fn cultures [] (. (config) :cultures))

(fn saved [key]
  (or (cm:get_saved_value key) {}))

(fn native [] (. (core:get_env) :archaon_subjugation))

(fn character [family-id]
  (let [family (cm:get_family_member_by_cqi family-id)]
    (when (world.valid? family) (family:character))))

(fn owned? [family-id faction-key]
  (let [lord (character family-id)]
    (and (world.valid? lord) (world.valid? (lord:faction))
         (= (: (lord:faction) :name) faction-key))))

{: prefix : pending-key : done-key : challenge-key : clients-key
 : config : targets : cultures : saved : native : character : owned?}
