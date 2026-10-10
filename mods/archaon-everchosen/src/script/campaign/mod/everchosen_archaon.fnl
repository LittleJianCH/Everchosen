(local campaign (include :everchosen_inheritance.campaign))
(local subjugation (include :everchosen_subjugation.campaign))
(local daemon (include :everchosen_daemon.campaign))

(cm:add_pre_first_tick_callback campaign.prepare)
(cm:add_first_tick_callback daemon.start)
(cm:add_first_tick_callback subjugation.start)
(cm:add_first_tick_callback campaign.start)
