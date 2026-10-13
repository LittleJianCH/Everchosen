(local dorghar (include :everchosen_dorghar.campaign))
(local campaign (include :everchosen_inheritance.campaign))
(local subjugation (include :everchosen_subjugation.campaign))
(local daemon (include :everchosen_daemon.campaign))
(local hordes (include :everchosen_hordes.campaign))
(local river (include :everchosen_subjugation.river_of_blood))

(cm:add_pre_first_tick_callback campaign.prepare)
;; The game separately loads generated static data before first tick;
;; modules must defer reading it until these callbacks run.
(cm:add_first_tick_callback hordes.start)
(cm:add_first_tick_callback river.start)
(cm:add_first_tick_callback daemon.start)
;; Extend the native subjugation config before inheritance checks its lords.
(cm:add_first_tick_callback subjugation.start)
(cm:add_first_tick_callback campaign.start)

(cm:add_first_tick_callback dorghar.start)
