(local data (include :everchosen_daemon.data))
(local legion (include :everchosen_daemon.legion))
(local progress (include :everchosen_daemon.progress))
(local host (include :everchosen_core.data))
(local world (include :everchosen_core.world))

;; Listener registration belongs to this Lua session.
(var started? false)

(fn can-donate? [faction key]
  (let [amount (progress.donation-amount faction key)]
    (and (progress.saved :initialized) (progress.prince faction)
         (not (progress.saved :pending)) (cm:is_local_players_turn)
         amount (> amount 0)
         (>= (progress.resource-value faction data.souls) amount))))

(fn can-dedicate? [faction key]
  (let [god (. (progress.config) :gods key)]
    (and god (progress.saved :initialized) (progress.prince faction)
         (cm:is_local_players_turn) (not (progress.saved :pending))
         (not (progress.dedication faction))
         (>= (progress.resource-value faction key) god.dedication_minimum))))

(fn refresh-ui []
  (let [faction (world.host)
        enabled? (and faction (progress.prince faction)
                      (progress.saved :initialized))]
    (common.set_context_value (.. data.prefix "enabled")
                              (if enabled? 1 0))
    (when faction
      (common.set_context_value (.. data.prefix "dedication")
                                (or (progress.dedication faction) ""))
      (each [key _ (pairs (. (progress.config) :gods))]
        (common.set_context_value (.. data.prefix "can_" key)
                                  (if (can-donate? faction key) 1 0))
        (common.set_context_value (.. data.prefix "can_dedicate_" key)
                                  (if (can-dedicate? faction key) 1 0)))
      (when enabled?
        (let [registered (progress.inventory (progress.prince faction))
              choices (progress.saved :choices {})]
          (each [key reward (pairs (. (progress.config) :rewards))]
            (common.set_context_value (.. data.prefix "threshold_" key)
                                      (if (. choices key) 1 0))
            (each [operation items (pairs reward.options)]
              (common.set_context_value
                (.. data.prefix "operation_" operation)
                (if (progress.all-owned? items registered) 1 0)))))))))

(fn confirm-donation []
  (let [pending (progress.saved :pending)]
    (when (and pending pending.receipts.souls pending.receipts.glory
               pending.receipts.spent)
      (progress.save :pending false))))

(fn reconcile []
  (let [faction (world.host)
        character (and faction (progress.prince faction))]
    (when character
      (progress.import-progress)
      (confirm-donation)
      (progress.unlock-parts faction character)
      (legion.reconcile faction character (. (progress.config) :legions)))
    (refresh-ui)))

(fn safely-reconcile []
  (let [(ok? message) (pcall reconcile)]
    (when (not ok?)
      (out (.. "[Everchosen Daemon Prince] " (tostring message))))))

(fn request []
  (cm:callback safely-reconcile 0.2)
  (cm:callback safely-reconcile 1))

(fn resource-changed [context]
  (let [pending (progress.saved :pending)
        key (: (context:resource) :key)
        factor (context:factor)
        amount (context:amount)]
    (when (and pending (world.valid? factor))
      (let [god (. (progress.config) :gods pending.resource)
            receipt (if (and (= key data.souls) (< amount 0)
                             (= (factor:key)
                                (. (progress.config) :souls_factor)))
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
          (progress.save :pending pending)
          (out (.. "[Everchosen Daemon Prince] Receipt " receipt
                   "=" amount))
          ;; Model events settle the donation even while a modal panel pauses
          ;; campaign callbacks. UI timers must not perform model mutations.
          (confirm-donation)
          (when (not (progress.saved :pending))
            (safely-reconcile)))))
    (when (or pending (= key data.souls) (. (progress.config) :gods key))
      (refresh-ui)
      (request))))

(fn sacrifice [key]
  (let [faction (world.host)]
    (when (and faction (not (can-donate? faction key)))
      (out (.. "[Everchosen Daemon Prince] Sacrifice blocked: " key
               "; souls=" (progress.resource-value faction data.souls)
               "; pending=" (tostring (progress.saved :pending)))))
    (when (and faction (can-donate? faction key))
      (let [god (. (progress.config) :gods key)
            amount (progress.donation-amount faction key)
            payload (cm:create_payload)]
        ;; Pending receipts block another donation until this one settles.
        (progress.save :pending
          {:resource key :spent god.spent :amount amount
           :glory (progress.resource-value faction key)
           :souls (progress.resource-value faction data.souls)
           :total (progress.resource-value faction god.spent) :receipts {}})
        (payload:faction_pooled_resource_transaction
          data.souls :gifts_of_chaos (- amount) false)
        (payload:faction_pooled_resource_transaction key :events amount false)
        (payload:faction_pooled_resource_transaction
          god.spent :gifts_of_chaos amount false)
        (cm:apply_payload payload faction)
        (safely-reconcile)
        (request)))))

(fn dedicate [key]
  (let [faction (world.host)]
    (when (and faction (can-dedicate? faction key))
      (let [god (. (progress.config) :gods key)]
        ;; Native ascension requires glory but does not expend it.
        (cm:apply_effect_bundle god.ritual host.host 0)
        (out (.. "[Everchosen Daemon Prince] Dedication " key
                 "; confirmed="
                 (tostring (faction:has_effect_bundle god.ritual))))
        (safely-reconcile)
        (request)))))

(fn choose [key operation]
  (let [faction (world.host)
        character (and faction (progress.prince faction))
        reward (. (progress.config) :rewards key)
        choices (progress.saved :choices {})]
    (when (and character reward (. reward.options operation)
               (progress.saved :initialized) (cm:is_local_players_turn)
               (not (. choices key)) (progress.available? faction key reward))
      (tset choices key operation)
      (progress.save :choices choices)
      (progress.grant character (. reward.options operation))
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
        (when (and key (. (progress.config) :gods key)
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
      progress.snapshot)
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

{: start :snapshot progress.snapshot : sacrifice : dedicate : choose
 : reconcile :prince progress.prince}
