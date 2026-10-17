(local rules (include :everchosen_hero_capacity.rules))
(local config
  {:families {:alluress {:agent :engineer :subtypes [:shadow :slaanesh]}
              :castellan {:agent :engineer :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :agent :engineer}
              :slaanesh {:family :alluress :agent :engineer}
              :castellan {:family :castellan :agent :engineer}}
   :classes {:engineer :engineer-cap}
   :counted_subtypes {:shadow :engineer :slaanesh :engineer
                      :castellan :engineer :unique :engineer}})

(describe "independent hero quotas and native recruitment headroom"
  (fn []
    (it "shares lores while every hero family keeps its own allowance"
      (fn []
        (let [sources {:shadow 1 :slaanesh 1 :castellan 1}
              counts {:shadow 1}
              full (rules.plan config sources {} counts {:engineer 6})]
          (assert.same {:used 1 :limit 1}
                       (rules.snapshot config full.families
                                       [:shadow :slaanesh]))
          (assert.same {:used 0 :limit 1}
                       (rules.snapshot config full.families [:castellan]))
          (assert.equals 2 full.class-targets.engineer)
          (assert.equals -4 full.effects.engineer-cap)
          (assert.is_nil
            (rules.snapshot config full.families [:shadow :castellan]))
          (assert.is_nil
            (rules.snapshot config full.families [:unknown])))))
    (it "counts every actual hero while keeping family source allowances separate"
      (fn []
        (let [before (rules.plan config
                       {:shadow 2.5 :slaanesh 2.5 :castellan 0}
                       {:alluress 1} {:shadow 1 :slaanesh 1}
                       {:engineer 0})
              after (rules.plan config {} {} {:shadow 1 :slaanesh 1}
                               {:engineer 5})
              transferred (rules.plan config
                            {:shadow 1 :slaanesh 1 :castellan 1} {}
                            {:shadow 3 :castellan 2 :unique 1}
                            {:engineer 2})]
          (assert.same {:used 2 :limit 3} before.families.alluress)
          (assert.equals 3 before.class-targets.engineer)
          (assert.same {:used 2 :limit 0} after.families.alluress)
          (assert.equals 3 after.class-targets.engineer)
          (assert.equals -2 after.effects.engineer-cap)
          (assert.same {:used 3 :limit 1} transferred.families.alluress)
          (assert.same {:used 2 :limit 1} transferred.families.castellan)
          (assert.equals 7 transferred.class-targets.engineer)
          (assert.equals 5 transferred.effects.engineer-cap))))
    (it "keeps promotion in the native family's single quota"
      (fn []
        (let [promotion-config
              {:families {:exalted {:agent :champion :subtypes [:undivided]
                                   :promoted_subtypes [:khorne]}
                          :gorebull {:agent :champion :subtypes [:gorebull]}}
               :subtypes {:undivided {:family :exalted}
                          :gorebull {:family :gorebull}}
               :classes {:champion :parent-cap}
               :counted_subtypes {:undivided :champion :khorne :champion
                                  :gorebull :champion}}
              sources {:undivided 1 :gorebull 1}
              before (rules.plan promotion-config sources {} {:undivided 1}
                                 {:champion 0})
              after (rules.plan promotion-config sources {} {:khorne 1}
                                {:champion 0})
              imported (rules.plan promotion-config sources {}
                                   {:khorne 1 :gorebull 1}
                                   {:champion 3})]
          (assert.same {:used 1 :limit 1} before.families.exalted)
          (assert.same before.families.exalted after.families.exalted)
          (assert.equals 2 before.class-targets.champion)
          (assert.equals 2 after.class-targets.champion)
          (assert.equals 3 imported.class-targets.champion)
          (assert.equals 0 imported.effects.parent-cap)
          (assert.same {:used 0 :limit 1} after.families.gorebull))))
    (it "keeps one native slot when families exceed or lose their allowance"
      (fn []
        (let [sources {:shadow 1 :slaanesh 1 :castellan 1}
              counts {:shadow 3 :castellan 1}
              before (rules.plan config sources {} counts {:engineer 0})
              lost (rules.plan config {} {} counts {:engineer 7})]
          (assert.equals 5 before.class-targets.engineer)
          (assert.equals 5 before.effects.engineer-cap)
          (assert.same {:used 3 :limit 0} lost.families.alluress)
          (assert.equals 5 lost.class-targets.engineer)
          (assert.equals -2 lost.effects.engineer-cap))))))
