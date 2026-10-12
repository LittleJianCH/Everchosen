(local prefix "everchosen_horde_")

(fn config []
  (. (core:get_static_object :everchosen_inheritance_data) :hordes))

{: prefix :state-key (.. prefix "state")
 :settle :MILITARY_FORCE_ACTIVE_STANCE_TYPE_SETTLE : config}
