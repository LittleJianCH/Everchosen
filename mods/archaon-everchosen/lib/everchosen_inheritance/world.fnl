(local data (include :everchosen_inheritance.data))

(fn valid? [object]
  (and object (not (object:is_null_interface))))

(fn items [list]
  "Iterate a zero-indexed campaign list interface."
  ;; Cursor belongs to this iterator, not to persistent campaign state.
  (var index -1)
  (fn []
    (set index (+ index 1))
    (if (< index (list:num_items)) (list:item_at index))))

(fn game-world []
  (let [model (cm:model)]
    (model:world)))

(fn factions []
  "Iterate every faction in the campaign, living or dead."
  (let [model-world (game-world)]
    (items (model-world:faction_list))))

(fn host? [faction]
  (and (valid? faction) (= (faction:name) data.host)
       (faction:is_human) (= (cm:get_campaign_name) data.campaign)
       (not (cm:is_multiplayer))))

(fn host []
  (let [faction (cm:get_faction data.host)]
    (if (host? faction) faction)))

(fn owned [faction]
  "Include wounded lords; verify current ownership of every interface."
  (collect [character (items (faction:character_list))]
    (when (and (valid? character)
               (= (: (character:faction) :name) data.host))
      (values (character:character_subtype_key) true))))

(fn resource [faction key]
  (let [manager (faction:pooled_resource_manager)
        value (manager:resource key)]
    (assert (valid? value) (.. "Missing inherited resource: " key))
    value))

{: valid? : items : game-world : factions : host? : host : owned
 : resource}
