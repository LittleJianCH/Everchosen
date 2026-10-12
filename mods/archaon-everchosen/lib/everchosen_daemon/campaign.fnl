(local data (include :everchosen_daemon.data))
(local legion (include :everchosen_daemon.legion))
(local host (include :everchosen_core.data))
(local world (include :everchosen_core.world))

;; An in-flight payload blocks duplicate clicks until its resource events are observed.
(var busy? false)
(var started? false)

(fn config []
  (. (world.static-data) :daemon_prince))

(fn saved [key fallback]
  (or (cm:get_saved_value (.. data.prefix key)) fallback))

(fn save [key value]
  (cm:set_saved_value (.. data.prefix key) value))

(fn prince [faction]
  (when (world.valid? faction)
    (accumulate [found nil character (world.items (faction:character_list))
                 &until found]
      (when (and (world.valid? character)
                 (= (character:character_subtype_key) data.prince)
                 (= (: (character:faction) :name) (faction:name)))
        character))))

(fn resource-value [faction key]
  (: (world.resource faction key) :value))

(fn inventory [character]
  (let [armory (: (character:family_member) :armory)]
    (collect [_ key (ipairs (armory:get_currently_registered_armory_items))]
      (values key true))))

(fn all-owned? [items registered]
  (accumulate [owned? true _ item (ipairs items) &until (not owned?)]
    (. registered item)))

(fn dedication [faction]
  (accumulate [chosen nil _ god (pairs (. (config) :gods)) &until chosen]
    (when (faction:has_effect_bundle god.ritual) god.ritual)))

(fn snapshot []
  "Capture progression before changing ownership, including a wounded prince."
  (when (not (saved :snapshot))
    (let [source (cm:get_faction data.prince)]
      (when (world.valid? source)
        (save :snapshot
          {:values (collect [key _ (pairs (. (config) :gods))]
                     (values key (resource-value source key)))
           :dedication
           (accumulate [chosen nil _ god (pairs (. (config) :gods))
                        &until chosen]
             (when (source:has_effect_bundle god.native_ritual)
               god.ritual))})))))

(fn import-progress []
  (let [faction (world.host)
        previous (saved :snapshot {:values {}})]
    (when (and faction (prince faction) (not (saved :initialized)))
      (when previous.dedication
        (cm:apply_effect_bundle previous.dedication host.host 0))
      (each [key _ (pairs (. (config) :gods))]
        (let [resource (world.resource faction key)
              amount (math.min (or (. previous.values key) 0)
                               (resource:maximum_value))]
          (when (> amount (resource:value))
            (cm:faction_add_pooled_resource host.host key :events
                                            (- amount (resource:value))))))
      (each [_ god (pairs (. (config) :gods))]
        (cm:unlock_ritual faction god.ritual 0))
      (save :initialized true))))

(fn available? [faction key reward]
  (let [amount (resource-value faction reward.resource)]
    (and (>= amount reward.minimum) (<= amount reward.maximum)
         (or (not reward.achievement)
             (= false (: (cco :CcoPooledResourceThresholdOperationSetRecord key)
                         :Call :IsLockedByAchievement))))))

(fn grant [character items]
  (let [registered (inventory character)]
    (each [_ item (ipairs items)]
      (when (not (. registered item))
        ;; Acquiring a part must not change the player's equipped loadout.
        (cm:add_armory_item_to_character character item false false)))))

(fn unlock-parts [faction character]
  (let [choices (saved :choices {})
        registered (inventory character)]
    (each [key reward (pairs (. (config) :rewards))]
      (let [operations (icollect [operation _ (pairs reward.options)] operation)]
        (table.sort operations)
        (when (not (. choices key))
          (let [owned (accumulate [found nil _ operation (ipairs operations)
                                  &until found]
                        (when (all-owned? (. reward.options operation) registered)
                          operation))]
            (when owned (tset choices key owned))))
        (when (and (not (. choices key)) (= (length operations) 1)
                   (available? faction key reward))
          (tset choices key (. operations 1)))
        (when (. choices key)
          (grant character (. reward.options (. choices key))))))
    (save :choices choices)))

(fn donation-amount [faction key]
  (let [god (. (config) :gods key)
        chosen (dedication faction)]
    (when (and god (or (not chosen) (= chosen god.ritual)
                       (= chosen (.. data.prefix "dedicate_undivided"))))
      (let [resource (world.resource faction key)]
        (math.max 0 (math.min data.step
                              (- (resource:maximum_value) (resource:value))))))))

(fn can-donate? [faction key]
  (let [amount (donation-amount faction key)]
    (and (saved :initialized) (prince faction) (not busy?)
         (not (saved :pending)) (cm:is_local_players_turn)
         amount (> amount 0) (>= (resource-value faction data.souls) amount))))

(fn can-dedicate? [faction key]
  (let [god (. (config) :gods key)]
    (and god (saved :initialized) (prince faction)
         (cm:is_local_players_turn) (not busy?) (not (saved :pending))
         (not (dedication faction))
         (>= (resource-value faction key) god.dedication_minimum))))

(fn refresh-ui []
  (let [faction (world.host)
        enabled? (and faction (prince faction) (saved :initialized))]
    (common.set_context_value (.. data.prefix "enabled")
                              (if enabled? 1 0))
    (when faction
      (common.set_context_value (.. data.prefix "dedication")
                                (or (dedication faction) ""))
      (each [key _ (pairs (. (config) :gods))]
        (common.set_context_value (.. data.prefix "can_" key)
                                  (if (can-donate? faction key) 1 0))
        (common.set_context_value (.. data.prefix "can_dedicate_" key)
                                  (if (can-dedicate? faction key) 1 0)))
      (when enabled?
        (let [registered (inventory (prince faction))
              choices (saved :choices {})]
          (each [key reward (pairs (. (config) :rewards))]
            (common.set_context_value (.. data.prefix "threshold_" key)
                                      (if (. choices key) 1 0))
            (each [operation items (pairs reward.options)]
              (common.set_context_value (.. data.prefix "operation_" operation)
                                        (if (all-owned? items registered) 1 0)))))))))

(fn confirm-donation []
  (let [pending (saved :pending)]
    (when (and pending pending.receipts.souls pending.receipts.glory
               pending.receipts.spent)
      (save :pending false))))

(fn reconcile []
  (let [faction (world.host)
        character (and faction (prince faction))]
    (when character
      (import-progress)
      (confirm-donation)
      (unlock-parts faction character)
      (legion.reconcile faction character (. (config) :legions)))
    (refresh-ui)))

(fn safely-reconcile []
  (let [(ok? message) (pcall reconcile)]
    (when (not ok?)
      (out (.. "[Everchosen Daemon Prince] " (tostring message))))))

(fn request []
  (cm:callback safely-reconcile 0.2)
  (cm:callback safely-reconcile 1))

(fn resource-changed [context]
  (let [pending (saved :pending)
        key (: (context:resource) :key)
        factor (context:factor)
        amount (context:amount)]
    (when (and pending (world.valid? factor))
      (let [god (. (config) :gods pending.resource)
            receipt (if (and (= key data.souls) (< amount 0)
                             (= (factor:key) (. (config) :souls_factor)))
                        :souls
                        (and (= key pending.resource) (> amount 0)
                             (= (factor:key) god.glory_factor))
                        :glory
                        (and (= key pending.spent) (> amount 0)
                             (= (factor:key) god.spent_factor))
                        :spent)]
        (when receipt
          ;; Observe the engine transaction, including income modifiers and
          ;; caps. Later income must not invalidate an already observed debit.
          (tset pending.receipts receipt amount)
          (save :pending pending)
          (out (.. "[Everchosen Daemon Prince] Receipt " receipt
                   "=" amount))
          ;; Model events settle the donation even while a modal panel pauses
          ;; campaign callbacks. UI timers must not perform model mutations.
          (confirm-donation)
          (when (not (saved :pending))
            (safely-reconcile)))))
    (when (or pending (= key data.souls) (. (config) :gods key))
      (refresh-ui)
      (request))))

(fn sacrifice [key]
  (let [faction (world.host)]
    (when (and faction (not (can-donate? faction key)))
      (out (.. "[Everchosen Daemon Prince] Sacrifice blocked: " key
               "; souls=" (resource-value faction data.souls)
               "; pending=" (tostring (saved :pending)))))
    (when (and faction (can-donate? faction key))
      (let [god (. (config) :gods key)
            amount (donation-amount faction key)
            payload (cm:create_payload)]
        (save :pending {:resource key :spent god.spent :amount amount
                        :glory (resource-value faction key)
                        :souls (resource-value faction data.souls)
                        :total (resource-value faction god.spent) :receipts {}})
        (set busy? true)
        (payload:faction_pooled_resource_transaction
          data.souls :gifts_of_chaos (- amount) false)
        (payload:faction_pooled_resource_transaction key :events amount false)
        (payload:faction_pooled_resource_transaction
          god.spent :gifts_of_chaos amount false)
        (cm:apply_payload payload faction)
        (set busy? false)
        (safely-reconcile)
        (request)))))

(fn dedicate [key]
  (let [faction (world.host)]
    (when (and faction (can-dedicate? faction key))
      (let [god (. (config) :gods key)]
        ;; Native ascension requires glory but does not expend it.
        (cm:apply_effect_bundle god.ritual host.host 0)
        (out (.. "[Everchosen Daemon Prince] Dedication " key
                 "; confirmed="
                 (tostring (faction:has_effect_bundle god.ritual))))
        (safely-reconcile)
        (request)))))

(fn choose [key operation]
  (let [faction (world.host)
        character (and faction (prince faction))
        reward (. (config) :rewards key)
        choices (saved :choices {})]
    (when (and character reward (. reward.options operation)
               (saved :initialized) (cm:is_local_players_turn)
               (not (. choices key)) (available? faction key reward))
      (tset choices key operation)
      (save :choices choices)
      (grant character (. reward.options operation))
      (request))))

(fn resource-click [context levels action]
  (let [faction (world.host)]
    (when (and faction (= (cm:get_local_faction_name true) host.host))
      ;; Walk only the verified template depth, never search the UI tree.
      (var entry (UIComponent context.component))
      (for [_ 1 levels]
        (set entry (UIComponent (entry:Parent))))
      (let [(key cqi) (string.match (entry:Id)
              "^CcoCampaignPooledResource(wh3_main_dae_.+_points)_FACTION_(%d+)$")]
        (when (and key (. (config) :gods key)
                   (= (tonumber cqi) (faction:command_queue_index)))
          (out (.. "[Everchosen Daemon Prince] " action " click: " key))
          (CampaignUI.TriggerCampaignScriptEvent
            (faction:command_queue_index)
            (.. data.prefix action ":" key)))))))

(fn command [context]
  (out (.. "[Everchosen Daemon Prince] UI command: " (context:trigger)))
  (let [faction (world.host)]
    (when (and faction (= (context:faction_cqi)
                          (faction:command_queue_index)))
      (let [message (context:trigger)
            resource (string.match message "^everchosen_daemon_sacrifice:(.+)$")
            dedication-key
            (string.match message "^everchosen_daemon_dedicate:(.+)$")
            (threshold operation)
            (string.match message "^everchosen_daemon_choose:([^:]+):([^:]+)$")]
        (if resource (sacrifice resource)
            dedication-key (dedicate dedication-key)
            threshold (choose threshold operation))))))

(fn tint [context]
  (let [character (context:character)
        armory (: (character:family_member) :armory)
        dominant
        (accumulate [chosen {:count 0} _ key
                     (ipairs [:khorne :nurgle :slaanesh :tzeentch])]
          (let [number (armory:number_of_equipped_items_of_ui_type key)]
            (if (> number chosen.count) {:god key :count number} chosen)))
        {:god god :count count} dominant]
    (if god
        (let [slots (tonumber (or (common.tweaker_value
                                   :daemon_prince_max_equipment_can_equip) "9"))
              amount (math.floor (+ 0.5 (* (/ 255 slots) count)))]
          (cm:set_tint_colour_for_character character
            (.. "wh3_main_daemon_prince_" god "_primary") amount
            (.. "wh3_main_daemon_prince_" god "_secondary") amount)
          (cm:set_tint_activity_state_for_character character true))
        (cm:set_tint_activity_state_for_character character false))))

(fn listen [suffix event condition callback]
  (core:add_listener (.. data.prefix suffix) event condition
    (world.guarded "Everchosen Daemon Prince" callback) true))

(fn start []
  (when (and (world.host) (not started?))
    (set started? true)
    (listen :accepted
      :ScriptEventEverchosenTransferAccepted #(= $1.string data.prince)
      snapshot)
    (listen :acquired
      :ScriptEventArchaonSubjugatesChaosFaction #(= $1.string data.prince)
      request)
    (listen :resource :PooledResourceChanged
      #(and ($1:has_faction) (world.host? ($1:faction)))
      resource-changed)
    (listen :sacrifice_click :ComponentLClickUp
      #(= $1.string :everchosen_daemon_sacrifice)
      #(resource-click $1 3 :sacrifice))
    (listen :dedication_click :ComponentLClickUp
      #(= $1.string :button_ascend)
      #(resource-click $1 4 :dedicate))
    (listen :command :UITrigger
      #(= (string.sub ($1:trigger) 1 (length data.prefix)) data.prefix)
      command)
    (listen :panel :PanelOpenedCampaign
      #(or (= $1.string :daemonic_progression)
           (= $1.string :character_details_panel)) request)
    (listen :turn :FactionTurnStart
      #(world.host? ($1:faction)) request)
    (listen :ritual :RitualCompletedEvent
      #(world.host? ($1:performing_faction)) request)
    (listen :tint :CharacterArmoryItemEquipped
      #(and (world.host? (: ($1:character) :faction))
            (= (: ($1:character) :character_subtype_key) data.prince)) tint)
    (safely-reconcile)))

{: start : snapshot : sacrifice : dedicate : choose : reconcile : prince}
