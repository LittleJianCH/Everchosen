;;; Legendary-lord gates and the two race-specific recruitment bonuses.

(local races
  [{:name :norsca
    :subculture :wh_dlc08_sc_nor_norsca
    :targets [:wh_dlc08_nor_norsca
              :wh_dlc08_nor_wintertooth
              :wh3_dlc27_nor_sayl]
    :bundle :everchosen_vassal_recruitment_norsca
    :effect :everchosen_vassal_recruit_cost_norsca}
   {:name :chaos_dwarfs
    :subculture :wh3_dlc23_sc_chd_chaos_dwarfs
    :targets [:wh3_dlc23_chd_astragoth
              :wh3_dlc23_chd_legion_of_azgorh
              :wh3_dlc23_chd_zhatan]
    :bundle :everchosen_vassal_recruitment_chd
    :effect :everchosen_vassal_recruit_cost_chd}])

{: races
 :applied-key :everchosen_vassal_recruitment_applied
 :discount-per-city 1
 :discount-cap 50}
