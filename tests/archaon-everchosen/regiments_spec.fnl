;; The command queue is a boundary fixture, not proof of engine registration.
;; Interface names and command parameters follow current AK scripting docs.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local host :wh_main_chs_chaos)
(local unit :wh3_dlc24_tze_inf_pink_horrors_ror)
(local record
  {: unit :group unit :source :wh3_main_regiments_of_renown_pool
   :count 1 :chance 100 :maximum 1 :rate 0.1 :partial true
   :faction host :subculture "" :technology ""})

(fn scenario []
  (let [s {:new-game? true :human? true :registry {} :calls [] :logs []
           :first [] :callbacks [] :objects {} :pending [] :reads 0}
        faction
        {:is_null_interface (fn [] false) :name (fn [] host)
         :is_human #(do s.human?)
         :mercenary_pool
         (fn []
           (set s.reads (+ s.reads 1))
           {:is_null_interface (fn [] false)
            :mercenary_pool_units
            (fn []
              (let [entries
                    (icollect [key value (pairs s.registry)]
                      {:faction_restriction_key (fn [] host)
                       :unit_record #(do {:key (fn [] key)})
                       :base_max_units #(do value.maximum)
                       :unit_count #(do value.count)})]
                {:num_items #(length entries)
                 :item_at (fn [_ index] (. entries (+ index 1)))}))})}
        env
        (setmetatable
          {:package {:preload {} :loaded {}}
           :out #(table.insert s.logs $1)
           :core {:get_static_object #(. s.objects $2)
                  :add_static_object #(tset s.objects $2 $3)}
           :cm {:get_faction (fn [] faction)
                :get_campaign_name (fn [] :main_warhammer)
                :is_multiplayer (fn [] false)
                :is_new_game #(do s.new-game?)
                :add_pre_first_tick_callback (fn [])
                :add_first_tick_callback #(table.insert s.first $2)
                :callback #(table.insert s.callbacks $2)
                :add_unit_to_faction_mercenary_pool
                (fn [_ owner ...]
                  (assert.equals faction owner)
                  (table.insert s.calls [...])
                  (table.insert s.pending [...]))}}
          {:__index _G})]
    (tset s.objects :everchosen_core_data {:regiments_of_renown [record]})
    (set env.require
      (fn [name]
        (when (not (. env.package.loaded name))
          (tset env.package.loaded name ((assert (. env.package.preload name)))))
        (. env.package.loaded name)))
    ((setfenv (assert (loadfile
       (or (os.getenv :EVERCHOSEN_REGIMENTS_ENTRY)
           (.. root "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua"))))
      env))
    (set s.start (. (env.require :everchosen_regiments.campaign) :start))
    (assert.is_truthy
      (accumulate [found false _ callback (ipairs s.first) &until found]
        (= callback s.start)))
    (set s.flush
      (fn []
        (when (not s.reject?)
          (each [_ command (ipairs s.pending)]
            (tset s.registry (. command 1)
              {:count (. command 3) :maximum (. command 5)})))
        (set s.pending [])
        (each [_ callback (ipairs s.callbacks)] (callback))
        (set s.callbacks [])))
    s))

(describe "new-campaign RoR pool registration"
  (fn []
    (it "registers through the native source and verifies the resulting pool"
      (fn []
        (let [s (scenario)]
          (s.start)
          (s.start)
          (assert.same
            [[unit :wh3_main_regiments_of_renown_pool 1 100 1 0.1
              host "" "" true unit]] s.calls)
          (assert.same [] s.logs)
          (assert.is_nil (. s.registry unit))
          (s.flush)
          (assert.same {:count 1 :maximum 1} (. s.registry unit))
          (assert.same
            ["[Everchosen regiments] Confirmed 1 additional RoR pool entries"]
            s.logs))))
    (it "keeps depleted entries and does not refill on normal loading"
      (fn []
        (let [s (scenario)]
          (tset s.registry unit {:count 0 :maximum 1})
          (s.start)
          (s.flush)
          (assert.same [] s.calls)
          (assert.equals 0 (. s.registry unit :count))
          (let [loaded (scenario)]
            (set loaded.new-game? false)
            (loaded.start)
            (assert.equals 0 loaded.reads)
            (assert.same [] loaded.calls)))))
    (it "reports a missing result instead of treating submission as success"
      (fn []
        (let [s (scenario)]
          (set s.reject? true)
          (s.start)
          (s.flush)
          (assert.equals 1 (length s.logs))
          (assert.is_truthy
            (string.find (. s.logs 1)
                         (.. "RoR pool registration missing: " unit) 1 true)))))
    (it "leaves a campaign without player-controlled Archaon alone"
      (fn []
        (let [s (scenario)]
          (set s.human? false)
          (s.start)
          (assert.equals 0 s.reads)
          (assert.same [] s.calls))))))
