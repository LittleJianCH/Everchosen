(local world (include :everchosen_core.world))

(local prefix "everchosen_horde_")

(fn config []
  (. (world.static-data) :hordes))

{: prefix :state-key (.. prefix "state")
 :settle :MILITARY_FORCE_ACTIVE_STANCE_TYPE_SETTLE : config}
