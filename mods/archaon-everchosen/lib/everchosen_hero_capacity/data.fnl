;;; Registry and event contract shared by capacity and recruitment UI.
{:config :everchosen_hero_capacity_data
 :controller :everchosen_hero_capacity_controller
 :provider :everchosen_hero_family_capacity
 :ui-controller :everchosen_hero_recruitment_controller
 :updating :ScriptEventEverchosenHeroCapacityUpdating
 :ready :ScriptEventEverchosenHeroCapacityReady
 :failed :ScriptEventEverchosenHeroCapacityFailed}
