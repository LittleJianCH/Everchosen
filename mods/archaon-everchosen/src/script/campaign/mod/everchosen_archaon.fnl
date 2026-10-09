(local campaign (include :everchosen_inheritance.campaign))

(cm:add_pre_first_tick_callback campaign.prepare)
(cm:add_first_tick_callback campaign.start)
