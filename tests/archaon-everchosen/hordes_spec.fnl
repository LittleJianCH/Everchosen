;; Native DLC29 source-capacity calls are modelled separately from stock.
;; These checks cover orchestration, not engine recruitment or camp persistence.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local host :wh_main_chs_chaos)
(local source :everchosen_horde_camp_stock)
(local settle :MILITARY_FORCE_ACTIVE_STANCE_TYPE_SETTLE)
(local state-key :everchosen_horde_state)

(fn clone [value]
  (if (= (type value) :table)
      (collect [key item (pairs value)] (values key (clone item)))
      value))

(fn game-list [entries]
  {:num_items #(length entries)
   :item_at (fn [_ index] (. entries (+ index 1)))})

(fn total-capacity [pool]
  (accumulate [total pool.base _ amount (pairs pool.sources)] (+ total amount)))

(fn make-pool [key restriction]
  {:key key :stock 0 :base 0 :sources {} :restriction restriction
   :unit_record (fn [self] {:key #(do self.key)})
   :unit_count (fn [self] self.stock)
   :current_max_units total-capacity
   :faction_restriction_key (fn [self] self.restriction)
   :scripted_capacity_bonus_for_source
   (fn [self key] (or (. self.sources key) 0))})

(fn faction [s key]
  {:is_null_interface (fn [] false) :name (fn [] key)
   :is_human #(= s.player key)
   :character_list #(game-list s.characters)
   :has_effect_bundle (fn [_ key] (or (. s.bundles key) false))})

(fn actor [s subtype force-type cqi]
  (let [character
        {:owner host :subtype subtype :has-force? true :in-region? true
         :is_null_interface (fn [] false)
         :character_type (fn [_ kind] (= kind :general))
         :character_subtype_key (fn [self] self.subtype)
         :command_queue_index (fn [] cqi)
         :faction (fn [self] (faction s self.owner))
         :has_military_force (fn [self] self.has-force?)
         :has_region (fn [self] self.in-region?)
         :region #(do s.region)}
        force
        {:kind force-type :stance settle :buildings [:gors] :bundles {}
         :is_null_interface (fn [] false)
         :command_queue_index (fn [] cqi)
         :faction #(character:faction)
         :has_general (fn [] true) :general_character (fn [] character)
         :force_type (fn [self] {:key #(do self.kind)})
         :active_stance (fn [self] self.stance)
         :has_effect_bundle (fn [self key] (or (. self.bundles key) false))
         :horde_details
         (fn [self]
           {:is_null_interface (fn [] false)
            :military_force_slot_list
            #(game-list (icollect [_ key (ipairs self.buildings)]
               {:has_building (fn [] true) :building (fn [] key)}))})}]
    (set character.military_force (fn [] force))
    (tset s.forces cqi force)
    (table.insert s.characters character)
    (values character force)))

(fn flush [s]
  (let [callbacks s.callbacks]
    (set s.callbacks [])
    (each [_ callback (ipairs callbacks)] (callback))))

(fn emit [s event context]
  (each [_ listener (ipairs s.listeners)]
    (when (and (= event listener.event)
               (or (= listener.condition true) (listener.condition context)))
      (listener.callback context)))
  (flush s))

(fn reload [s]
  (set s.listeners [])
  (set s.callbacks [])
  (let [config
        {:subtypes {:wh_dlc03_bst_khazrak :HORDE_KHAZRAK
                    :wh_dlc03_bst_malagor :HORDE_MALAGOR
                    :wh_dlc05_bst_morghur :HORDE_MORGHUR
                    :wh2_dlc17_bst_taurox :HORDE_TAUROX}
         :start_bundle :everchosen_horde_new_horde
         :settle_bundle :everchosen_horde_settle :pool_source source
         :buildings {:gors [:ungor] :gors_upgrade [:ungor]}
         :horn_bonus {:horn 30} :units {:ungor {:chance 40 :cap 4}}}
        env (setmetatable
          {:out #(table.insert s.logs $1)
           :package {:preload {} :loaded {}}
           :core
           {:get_static_object (fn [] {:hordes config})
            :add_listener
            (fn [_ name event condition callback]
              (table.insert s.listeners
                            {: name : event : condition : callback}))}
           :cm
           {:add_first_tick_callback (fn [])
            :add_pre_first_tick_callback (fn [])
            :get_campaign_name #(do s.campaign)
            :is_multiplayer #(do s.multiplayer?)
            :get_faction (fn [_ key] (faction s key))
            :get_saved_value (fn [_ key] (clone (. s.saved key)))
            :set_saved_value (fn [_ key value] (tset s.saved key (clone value)))
            :turn_number #(do s.turn)
            :get_military_force_by_cqi (fn [_ cqi] (. s.forces cqi))
            :get_region (fn [_ key] (when (= key :region) s.region))
            :apply_effect_bundle
            (fn [_ key faction-key]
              (assert.equals host faction-key)
              (tset s.bundles key true))
            :apply_effect_bundle_to_force
            (fn [_ key cqi] (tset (. s.forces cqi :bundles) key true))
            :remove_effect_bundle_from_force
            (fn [_ key cqi] (tset (. s.forces cqi :bundles) key nil))
            :add_unit_to_province_mercenary_pool
            (fn [_ region unit count chance maximum per-turn
                 restriction subculture technology]
              (assert.equals s.region region)
              (assert.same [:ungor 0 0 0 0 host "" ""]
                           [unit count chance maximum per-turn
                            restriction subculture technology])
              (set s.registrations (+ s.registrations 1))
              (table.insert s.commands :register)
              (when (not s.block-registration?)
                (set s.pool (make-pool unit restriction))
                (table.insert s.entries s.pool)))
            :set_mercenary_pool_unit_scripted_capacity_bonus
            (fn [_ pool amount key]
              (assert.equals source key)
              (table.insert s.commands :capacity)
              (when (not s.block-capacity?)
                (tset pool.sources key amount)
                ;; Native Glottkin documents stock clamping when max falls.
                (set pool.stock (math.min pool.stock (total-capacity pool)))))
            :random_number
            (fn [_ maximum]
              (assert.equals 100 maximum)
              (set s.rolls (+ s.rolls 1))
              s.roll)
            :add_units_to_province_mercenary_pool_by_region
            (fn [_ region unit amount]
              (assert.equals :region region)
              (assert.equals :ungor unit)
              (assert.equals 1 amount)
              (table.insert s.commands :stock)
              (set s.additions (+ s.additions 1))
              (when (not s.block-stock?)
                (set s.pool.stock
                     (math.min (+ s.pool.stock amount)
                               (total-capacity s.pool)))))
            :callback (fn [_ callback] (table.insert s.callbacks callback))}}
          {:__index _G})]
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile (.. root
       "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua")))
       env))
    ((. (env.require :everchosen_hordes.campaign) :start))))

(fn scenario []
  (let [s {:player host :campaign :main_warhammer :multiplayer? false
           :turn 1 :saved {} :characters [] :forces {} :bundles {} :logs []
           :callbacks [] :listeners [] :rolls 0 :roll 1 :additions 0
           :registrations 0 :commands []
           :pool (make-pool :ungor host)}
        province {:is_null_interface #(or s.null-province? false)
                  :key (fn [] (assert (not s.null-province?)) :province)
                  :mercenary_pool
                  (fn []
                    (assert (not s.null-province?))
                    {:is_null_interface #(or s.null-pool? false)
                     :mercenary_pool_units
                     (fn []
                       (assert (not s.null-pool?))
                       (game-list s.entries))})}]
    (set s.entries [s.pool])
    (set s.region {:is_null_interface (fn [] false) :name (fn [] :region)
                   :province (fn [] province)})
    s))

(fn turn [s]
  (emit s :FactionTurnStart {:faction #(faction s host)}))

(fn select [s character]
  (emit s :CharacterSelected {:character (fn [] character)}))

(describe "Bound Beastmen camp supply"
  (fn []
    (it "registers absent camp stock before capacity and turn replenishment"
      (fn []
        (let [s (scenario)
              (lord force) (actor s :wh2_dlc17_bst_taurox :HORDE_TAUROX 1)]
          (set s.entries [])
          (set force.stance :MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT)
          (reload s)
          (assert.equals 0 s.registrations)
          (set force.stance settle)
          (select s lord)
          (assert.same [:register :capacity] s.commands)
          (assert.equals 4 (. s.pool.sources source))
          (assert.equals 0 s.pool.stock)
          (turn s)
          (assert.same [:register :capacity :stock] s.commands)
          (assert.equals 1 s.pool.stock)
          (select s lord) (reload s) (turn s)
          (assert.equals 1 s.registrations)
          (assert.equals 1 s.pool.stock))))
    (it "preserves shared and foreign stock instead of replacing its entry"
      (fn []
        (each [_ restriction (ipairs ["" :foreign])]
          (let [s (scenario)]
            (actor s :wh2_dlc17_bst_taurox :HORDE_TAUROX 1)
            (set s.pool.restriction restriction)
            (set s.pool.stock 2)
            (set s.pool.base 3)
            (tset s.pool.sources :other 4)
            (reload s) (turn s)
            (assert.equals 0 s.registrations)
            (assert.equals 0 s.additions)
            (assert.equals 2 s.pool.stock)
            (assert.equals 3 s.pool.base)
            (assert.same {:other 4} s.pool.sources)
            (assert.is_truthy
              (: (. s.logs (length s.logs)) :find
                 (.. "conflicting restrictions: "
                     (string.format "%q" restriction)) 1 true))))))
    (it "requires host ownership, matching horde and an active force"
      (fn []
        (let [s (scenario)
              (foreign foreign-force)
              (actor s :wh_dlc03_bst_khazrak :HORDE_KHAZRAK 1)
              (wounded _wounded-force)
              (actor s :wh_dlc03_bst_malagor :HORDE_MALAGOR 2)
              (_wrong wrong-force) (actor s :wh_dlc05_bst_morghur :ARMY 3)
              (_ordinary ordinary-force) (actor s :archaon :HORDE_TAUROX 4)]
          (set foreign.owner :wh_dlc03_bst_beastmen)
          (set wounded.has-force? false)
          (reload s) (turn s)
          (assert.equals 0 s.rolls)
          (assert.equals 0 s.pool.stock)
          (each [_ force (ipairs [foreign-force wrong-force ordinary-force])]
            (assert.is_nil (. force.bundles :everchosen_horde_settle)))
          (set foreign.owner host)
          (select s foreign)
          (assert.is_true (. foreign-force.bundles :everchosen_horde_settle))
          (assert.equals 0 s.rolls)
          (set foreign.owner :wh_dlc03_bst_beastmen)
          (select s foreign)
          (assert.is_nil (. foreign-force.bundles :everchosen_horde_settle)))))
    (it "uses one highest chance per province and cannot reroll after reload"
      (fn []
        (let [s (scenario)
              (first _first-force)
              (actor s :wh_dlc03_bst_khazrak :HORDE_KHAZRAK 1)
              (_second second-force)
              (actor s :wh2_dlc17_bst_taurox :HORDE_TAUROX 2)]
          (set second-force.buildings [:gors :gors_upgrade :horn])
          (set s.roll 65)
          (reload s)
          (assert.equals 0 s.rolls)
          (turn s)
          (assert.equals 1 s.rolls)
          (assert.equals 1 s.pool.stock)
          (select s first) (turn s) (reload s) (turn s)
          (assert.equals 1 s.rolls)
          (assert.equals 1 s.pool.stock)
          (set s.turn 2)
          (turn s)
          (assert.equals 2 s.rolls)
          (assert.equals 2 s.pool.stock))))
    (it "retires only our unused capacity and retains local stock after leaving"
      (fn []
        (let [s (scenario)
              (lord force) (actor s :wh2_dlc17_bst_taurox :HORDE_TAUROX 1)]
          (tset s.pool.sources :other 2)
          (reload s)
          (assert.equals 0 s.registrations)
          (set s.pool.stock 5)
          (set force.stance :MILITARY_FORCE_ACTIVE_STANCE_TYPE_DEFAULT)
          (emit s :ForceAdoptsStance {:military_force (fn [] force)})
          (assert.equals 5 s.pool.stock)
          (assert.equals 3 (. s.pool.sources source))
          (assert.equals 2 s.pool.sources.other)
          (reload s) (turn s)
          (assert.equals 0 s.rolls)
          (assert.equals 5 s.pool.stock)
          (set s.pool.stock 2)
          (emit s :UnitTrained {:unit #(do {:faction #(faction s host)})})
          (assert.equals 0 (. s.pool.sources source))
          (assert.equals 2 s.pool.sources.other)
          (assert.equals 2 s.pool.stock)
          (assert.is_nil (. s.saved state-key :provinces :province)))))
    (it "does not claim failed engine commands or fall back to foreign pools"
      (fn []
        (let [s (scenario)
              (lord _force) (actor s :wh2_dlc17_bst_taurox :HORDE_TAUROX 1)]
          (set s.entries [])
          (set s.block-registration? true)
          (reload s) (turn s)
          (assert.equals 0 s.rolls)
          (assert.equals 0 s.additions)
          (assert.same {} s.pool.sources)
          (assert.is_truthy
            (: (. s.logs (length s.logs)) :find "registration not confirmed"))
          (set s.entries [s.pool])
          (set s.pool.restriction :foreign)
          (reload s) (turn s)
          (assert.equals 0 s.additions)
          (each [_ flag (ipairs [:null-province? :null-pool?])]
            (tset s flag true)
            (select s lord)
            (assert.is_truthy
              (: (. s.logs (length s.logs)) :find "Missing host pool"))
            (tset s flag false))
          (set s.pool.restriction host)
          (set s.block-capacity? true)
          (set s.turn 2)
          (turn s)
          (assert.equals 0 s.rolls)
          (set s.block-capacity? false)
          (select s lord) (turn s)
          (assert.equals 0 s.rolls)
          (set s.block-stock? true)
          (set s.turn 3)
          (turn s)
          (assert.equals 1 s.additions)
          (assert.equals 0 s.pool.stock)
          (assert.is_truthy
            (: (. s.logs (length s.logs)) :find "Stock addition not confirmed"))
          (turn s)
          (assert.equals 1 s.additions))))))
