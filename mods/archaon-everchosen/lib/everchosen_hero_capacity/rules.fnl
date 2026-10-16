(local unlimited 4294967295)

(fn family-state [config source-bonus extras counts]
  (collect [family record (pairs config.families)]
    (let [source (accumulate [highest (- math.huge)
                             _ subtype (ipairs record.subtypes)]
                    (math.max highest (or (. source-bonus subtype) 0)))
          used (+ (accumulate [total 0 _ subtype (ipairs record.subtypes)]
                    (+ total (or (. counts subtype) 0)))
                  (accumulate [total 0 _ subtype
                               (ipairs (or record.promoted_subtypes []))]
                    (+ total (or (. counts subtype) 0))))
          limit (math.max 0 (math.floor (+ source (or (. extras family) 0))))]
      (values family {: used : limit}))))

(fn subtype-targets [config families counts]
  (collect [subtype record (pairs config.subtypes)]
    (let [family (. families record.family)
          remaining (math.max 0 (- family.limit family.used))]
      (values subtype (+ (or (. counts subtype) 0) remaining)))))

(fn class-uplifts [config families counts class-caps last-uplifts]
  (collect [agent _ (pairs config.classes)]
    (let [observed (. class-caps agent)
          used (accumulate [total 0 subtype class
                            (pairs config.counted_subtypes)]
                 (+ total (if (= class agent) (or (. counts subtype) 0) 0)))
          remaining (accumulate [total 0 family record
                                 (pairs config.families)]
                      (let [state (. families family)]
                        (+ total (if (= record.agent agent)
                                     (math.max 0 (- state.limit state.used))
                                     0))))
          ;; Native soul promotion creates the new hero before deleting the old.
          promotion-slot
          (accumulate [reserved 0 _ record (pairs config.families)]
            (if (and (= record.agent agent)
                     (next (or record.promoted_subtypes []))
                     (accumulate [owned? false _ subtype
                                  (ipairs record.subtypes) &until owned?]
                       (> (or (. counts subtype) 0) 0)))
                1 reserved))]
      (values agent
        (if (= observed unlimited) 0
            (math.max 0 (- (+ used remaining promotion-slot)
                           (- observed (or (. last-uplifts agent) 0)))))))))

(fn plan [config source-bonus extras counts normalizers class-caps
          last-uplifts]
  "Plan independent family limits and host-only native cap effects.
  source-bonus excludes our previous subtype overrides; extras is per family.
  counts includes wounded heroes and every cap-contributing unique subtype.
  Promotion forms count toward their original family but keep native caps.
  normalizers turn native subtype bonuses into total caps; class-caps are
  observed totals including last-uplifts. Return families, targets, effects,
  and the class-uplifts to subtract from the next observed class totals."
  (let [families (family-state config source-bonus extras counts)
        targets (subtype-targets config families counts)
        uplifts (class-uplifts config families counts class-caps last-uplifts)
        subtype-effects (collect [subtype record (pairs config.subtypes)]
                          (values record.effect
                            (- (+ (. normalizers subtype) (. targets subtype))
                               (or (. source-bonus subtype) 0))))
        effects (accumulate [result subtype-effects agent effect
                             (pairs config.classes)]
                  (do (tset result effect (. uplifts agent)) result))]
    {: families : targets : effects :class-uplifts uplifts}))

(fn snapshot [config families subtypes]
  "Return used/limit for one known family, or nil for mixed/unknown subtypes."
  (let [first (. config.subtypes (. subtypes 1))]
    (when (and first
               (accumulate [same? true _ subtype (ipairs subtypes)]
                 (let [member (. config.subtypes subtype)]
                   (and same? member (= member.family first.family)))))
      (. families first.family))))

{: plan : snapshot}
