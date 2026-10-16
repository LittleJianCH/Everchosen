(local rules (include :everchosen_hero_capacity.rules))
(local config
  {:families {:alluress {:agent :engineer :subtypes [:shadow :slaanesh]}
              :castellan {:agent :engineer :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :agent :engineer}
              :slaanesh {:family :alluress :agent :engineer}
              :castellan {:family :castellan :agent :engineer}}
   :classes {:engineer :engineer-cap}
   :native_page {:engineer :alluress}
   :counted_subtypes {:shadow :engineer :slaanesh :engineer
                      :castellan :engineer :unique :engineer}})

(describe "independent hero quotas and native/private recruitment pages"
  (fn []
    (it "shares lores while private heroes keep their own allowance"
      (fn []
        (let [sources {:shadow 1 :slaanesh 1 :castellan 1}
              counts {:shadow 1}
              full (rules.plan config sources {} counts
                               {:engineer 6} false)
              available (rules.plan config sources {} counts
                                    {:engineer 6} true)]
          (assert.same {:used 1 :limit 1}
                       (rules.snapshot config full.families
                                       [:shadow :slaanesh]))
          (assert.same {:used 0 :limit 1}
                       (rules.snapshot config full.families [:castellan]))
          (assert.equals 1 full.class-targets.engineer)
          (assert.equals -5 full.effects.engineer-cap)
          (assert.equals 2 available.class-targets.engineer)
          (assert.equals -4 available.effects.engineer-cap)
          (assert.is_nil
            (rules.snapshot config full.families [:shadow :castellan]))
          (assert.is_nil
            (rules.snapshot config full.families [:unknown])))))
    (it "compensates actual imported heroes without granting native slots"
      (fn []
        (let [before (rules.plan config
                       {:shadow 2.5 :slaanesh 2.5 :castellan 0}
                       {:alluress 1} {:shadow 1 :slaanesh 1}
                       {:engineer 0} false)
              after (rules.plan config {} {} {:shadow 1 :slaanesh 1}
                               {:engineer 5} false)
              transferred (rules.plan config
                            {:shadow 1 :slaanesh 1 :castellan 1} {}
                            {:shadow 3 :castellan 2 :unique 1}
                            {:engineer 2} false)]
          (assert.same {:used 2 :limit 3} before.families.alluress)
          (assert.equals 3 before.class-targets.engineer)
          (assert.same {:used 2 :limit 0} after.families.alluress)
          (assert.equals 0 after.class-targets.engineer)
          (assert.equals -5 after.effects.engineer-cap)
          (assert.same {:used 3 :limit 1} transferred.families.alluress)
          (assert.same {:used 2 :limit 1} transferred.families.castellan)
          (assert.equals 4 transferred.class-targets.engineer)
          (assert.equals 2 transferred.effects.engineer-cap))))
    (it "keeps promotion in the native family's single quota"
      (fn []
        (let [promotion-config
              {:families {:exalted {:agent :champion :subtypes [:undivided]
                                   :promoted_subtypes [:khorne]}
                          :gorebull {:agent :champion :subtypes [:gorebull]}}
               :subtypes {:undivided {:family :exalted}
                          :gorebull {:family :gorebull}}
               :classes {:champion :parent-cap}
               :native_page {:champion :exalted}
               :counted_subtypes {:undivided :champion :khorne :champion
                                  :gorebull :champion}}
              sources {:undivided 1 :gorebull 1}
              before (rules.plan promotion-config sources {} {:undivided 1}
                                 {:champion 0} false)
              after (rules.plan promotion-config sources {} {:khorne 1}
                                {:champion 0} false)
              imported (rules.plan promotion-config sources {}
                                   {:khorne 1 :gorebull 1}
                                   {:champion 3} false)]
          (assert.same {:used 1 :limit 1} before.families.exalted)
          (assert.same before.families.exalted after.families.exalted)
          (assert.equals 1 before.class-targets.champion)
          (assert.equals 1 after.class-targets.champion)
          (assert.equals 2 imported.class-targets.champion)
          (assert.equals -1 imported.effects.parent-cap)
          (assert.same {:used 0 :limit 1} after.families.gorebull))))
    (it "opens one private slot even when native heroes exceed their quota"
      (fn []
        (let [sources {:shadow 1 :slaanesh 1 :castellan 1}
              counts {:shadow 3 :castellan 1}
              private (rules.plan config sources {} counts
                                  {:engineer 0} true)
              outside (rules.plan config sources {} counts
                                  {:engineer 7} false)]
          (assert.equals 5 private.class-targets.engineer)
          (assert.equals 5 private.effects.engineer-cap)
          (assert.equals 2 outside.class-targets.engineer)
          (assert.equals -5 outside.effects.engineer-cap))))))
