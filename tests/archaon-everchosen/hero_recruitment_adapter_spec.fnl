;; Controller-boundary fixture: native IDs and states are inputs, not a UI
;; layout or candidate engine. Stop before candidate selection is simulated.
(local root (assert (os.getenv :EVERCHOSEN_ROOT)))
(local fire :wh_dlc08_nor_shaman_sorcerer_fire)
(local death :wh_dlc08_nor_shaman_sorcerer_death)

(fn scenario []
  (let [s {:queue [] :listeners {} :logs [] :clicks 0}
        label {:GetStateText (fn [] "巫术萨满")}
        class {:Id (fn [] :wizard) :GetProperty (fn [] nil)
               :CurrentState (fn [] :selected_hover) :label label
               :SimulateLClick #(set s.clicks (+ s.clicks 1))}
        types (icollect [_ subtype (ipairs [fire death])]
                {:Id (fn [] subtype) :GetProperty (fn [] nil)
                 :CurrentState (fn [] :active) :Visible (fn [] true)})
        page {:SetStateText (fn [])}
        controls {:agents {:wizard class :SetVisible (fn [])}
                  :types types
                  :private {:SetVisible (fn []) :everchosen_hero_page page}}
        metadata (collect [_ subtype (ipairs [fire death])]
                   (values subtype {:family :wh_dlc08_nor_shaman_sorcerer
                                    :name_key :shaman_name :icon "wizard.png"}))
        world {:host (fn [] true)
               :static-data (fn [] {:hero_recruitment
                 {:page_size 8 :icons {:wizard "wizard.png"}
                  :subtypes metadata}})}
        view {:controls (fn [] controls) :create (fn []) :restore (fn [])
              :reserve (fn []) :block (fn []) :unblock (fn [])
              :restore-types (fn [])
              :children (fn [parent]
                          (if (= parent controls.agents) [class]
                              (= parent types) types []))
              :show-page (fn [_ entries]
                           (when (> (length entries) 0)
                             (set s.groups entries)))}
        env (setmetatable
          {:package {:preload {} :loaded {}}
           :out (fn [message] (table.insert s.logs message))
           :find_uicomponent (fn [parent id] (. parent id))
           :common {:get_localised_string (fn [key] key)}
           :core {:add_listener (fn [_ _ event predicate callback]
                                 (tset s.listeners event
                                       {: predicate : callback}))}
           :cm {:add_first_tick_callback (fn [])
                :add_pre_first_tick_callback (fn [])
                :callback (fn [_ callback]
                            (table.insert s.queue callback))}}
          {:__index _G})]
    (set env.require
      (fn [key]
        (when (not (. env.package.loaded key))
          (tset env.package.loaded key ((assert (. env.package.preload key)))))
        (. env.package.loaded key)))
    ((setfenv (assert (loadfile (.. root
      "/build/archaon-everchosen/script/campaign/mod/everchosen_archaon.lua")))
      env))
    ;; Re-load the real controller with only its world/view boundaries changed.
    (tset env.package.preload :everchosen_core.world (fn [] world))
    (tset env.package.preload :everchosen_hero_recruitment.view (fn [] view))
    (each [_ key (ipairs [:everchosen_core.world
                          :everchosen_hero_recruitment.view
                          :everchosen_hero_recruitment.campaign])]
      (tset env.package.loaded key nil))
    (let [controller (env.require :everchosen_hero_recruitment.campaign)]
      (controller.start))
    (let [listener (. s.listeners :PanelOpenedCampaign)
          context {:string :character_panel}]
      (assert.is_true (listener.predicate context))
      (listener.callback context))
    ;; Catalog completion queues further native navigation. Leave that work
    ;; pending: this regression establishes discovery, not engine recruitment.
    (while (and (. s.queue 1) (not s.groups))
      ((table.remove s.queue 1)))
    s))

(describe "native hero-family discovery"
  (fn []
    (it "uses native class IDs and accepts a selected-hover class"
      (fn []
        (let [s (scenario)]
          (assert.is_not_nil s.groups (table.concat s.logs "\n"))
          (assert.is_true (> s.clicks 0))
          (assert.equals 1 (length s.groups))
          (assert.equals :wizard (. s.groups 1 :agent))
          (assert.same [fire death] (. s.groups 1 :subtypes)))))))
