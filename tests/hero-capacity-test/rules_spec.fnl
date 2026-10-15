(local rules (include :everchosen_hero_capacity_test.rules))
(local config
  {:families {:alluress {:limit 1 :subtypes [:shadow :slaanesh]}
              :castellan {:limit 1 :subtypes [:castellan]}}
   :subtypes {:shadow {:family :alluress}
              :slaanesh {:family :alluress}
              :castellan {:family :castellan}}})

(describe "independent hero-family capacity experiment"
  (fn []
    (it "shares one allowance across lores and leaves the other hero available"
      (fn []
        (assert.same {:shadow 1 :slaanesh 1 :castellan 1}
                     (rules.targets config {}))
        (assert.same {:shadow 1 :slaanesh 0 :castellan 1}
                     (rules.targets config {:shadow 1}))
        (assert.same {:shadow 1 :slaanesh 0 :castellan 1}
                     (rules.targets config {:shadow 1 :castellan 1}))
        (assert.same {:used 1 :limit 1}
                     (rules.snapshot config {:shadow 1} [:shadow :slaanesh]))))
    (it "retains existing heroes above the limit while allowing no new lore"
      (fn []
        (assert.same {:shadow 2 :slaanesh 0 :castellan 1}
                     (rules.targets config {:shadow 2}))
        (assert.same {:used 2 :limit 1}
                     (rules.snapshot config {:shadow 2} [:shadow :slaanesh]))
        (assert.is_nil (rules.snapshot config {} [:shadow :castellan]))
        (assert.is_nil (rules.snapshot config {} [:other]))))
    (it "measures signed base offsets without treating unlimited as a number"
      (fn []
        (assert.same {:shadow 1 :castellan 0}
          (rules.measured-offsets {:shadow 0 :castellan 1}
                                 {:shadow 1 :castellan 2}))
        (assert.is_nil (rules.measured-offsets {:shadow 4294967295}
                                             {:shadow 4294967295}))
        (assert.is_nil (rules.measured-offsets {:shadow 1} {:shadow 1}))))))
