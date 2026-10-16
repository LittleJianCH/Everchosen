(local rules (include :everchosen_hero_capacity.rules))
(local config
  {:families {:alluress {:agent :engineer :subtypes [:shadow :slaanesh]}
              :castellan {:agent :engineer :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress :agent :engineer
                       :effect :shadow-cap :base -1}
              :slaanesh {:family :alluress :agent :engineer
                         :effect :slaanesh-cap :base -1}
              :castellan {:family :castellan :agent :engineer
                          :effect :castellan-cap :base -1}}
   :classes {:engineer :engineer-cap}
   :counted_subtypes {:shadow :engineer :slaanesh :engineer
                      :castellan :engineer :unique :engineer}})
(local normalizers {:shadow 1 :slaanesh 1 :castellan 1})

(describe "independent hero family capacities"
  (fn []
    (it "shares lores while leaving another hero's allowance available"
      (fn []
        (let [sources {:shadow 1 :slaanesh 1 :castellan 1}
              result (rules.plan config sources {} {:shadow 1} normalizers
                                 {:engineer 1} {})]
          (assert.same {:shadow 1 :slaanesh 0 :castellan 1} result.targets)
          (assert.same {:used 1 :limit 1}
                       (rules.snapshot config result.families
                                       [:shadow :slaanesh]))
          (assert.same {:used 0 :limit 1}
                       (rules.snapshot config result.families [:castellan]))
          (assert.equals 1 result.effects.engineer-cap)
          (assert.is_nil
            (rules.snapshot config result.families [:shadow :castellan]))
          (assert.is_nil
            (rules.snapshot config result.families [:unknown])))))
    (it "counts one building once across lores and follows removed sources"
      (fn []
        (let [before (rules.plan config
                       {:shadow 2.5 :slaanesh 2.5 :castellan 0}
                       {:alluress 1} {:shadow 1 :slaanesh 1} normalizers
                       {:engineer 0} {})
              after (rules.plan config {} {} {:shadow 1 :slaanesh 1}
                               normalizers {:engineer 3}
                               before.class-uplifts)]
          (assert.same {:used 2 :limit 3} before.families.alluress)
          (assert.same {:shadow 2 :slaanesh 2 :castellan 0} before.targets)
          (assert.same {:used 2 :limit 0} after.families.alluress)
          (assert.same {:shadow 1 :slaanesh 1 :castellan 0} after.targets)
          (assert.equals 2 after.effects.engineer-cap))))
    (it "allows the other hero after an over-limit transfer or unique grant"
      (fn []
        (let [result (rules.plan config
                       {:shadow 1 :slaanesh 1 :castellan 1} {}
                       {:shadow 3 :unique 1} normalizers
                       {:engineer 2} {})]
          (assert.same {:used 3 :limit 1} result.families.alluress)
          (assert.same {:shadow 3 :slaanesh 0 :castellan 1} result.targets)
          (assert.equals 3 result.effects.engineer-cap))))
    (it "replaces only its prior class contribution when sources change"
      (fn []
        (let [result (rules.plan config
                       {:shadow 2 :slaanesh 2 :castellan 1} {}
                       {:shadow 1} normalizers {:engineer 7}
                       {:engineer 6})]
          (assert.equals 2 result.effects.engineer-cap)
          (assert.equals 2 result.class-uplifts.engineer))))
    (it "normalizes subtype totals without changing their native base"
      (fn []
        (let [sources {:shadow 2 :slaanesh 2 :castellan 1}
              offsets {:shadow 1 :slaanesh 0 :castellan 1}
              result (rules.plan config sources {} {:shadow 1} offsets
                                 {:engineer 4294967295}
                                 {:engineer 8})]
          (assert.same {:shadow 2 :slaanesh 1 :castellan 1} result.targets)
          (assert.same {:shadow-cap 1 :slaanesh-cap -1 :castellan-cap 1
                        :engineer-cap 0} result.effects)
          (assert.equals -1 config.subtypes.shadow.base)
          (assert.same {:shadow 2 :slaanesh 2 :castellan 1} sources))))))
