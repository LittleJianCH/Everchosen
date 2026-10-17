(local unlimited 4294967295)

(fn family-key [config subtypes]
  "Return one family key only when every subtype belongs to that family."
  (let [first (. config.subtypes (. subtypes 1))]
    (when (and first
               (accumulate [same? true _ subtype (ipairs subtypes)]
                 (let [member (. config.subtypes subtype)]
                   (and same? member (= member.family first.family)))))
      first.family)))

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

(fn class-targets [config counts]
  (collect [agent _ (pairs config.classes)]
    (let [used (accumulate [total 0 subtype class
                            (pairs config.counted_subtypes)]
                 (+ total (if (= class agent) (or (. counts subtype) 0) 0)))]
      ;; The unified page enforces every family quota. Keep one native slot
      ;; available through panel closure until the hiring command completes.
      (values agent (+ used 1)))))

(fn plan [config source-bonus extras counts native-caps]
  "Plan family quotas and one native hiring slot per class.
  native-caps must be read without this controller's effect bundle."
  (let [families (family-state config source-bonus extras counts)
        targets (class-targets config counts)
        effects (collect [agent effect (pairs config.classes)]
                  (let [native (. native-caps agent)]
                    (assert (< native unlimited)
                            (.. "Cannot constrain unlimited hero class: " agent))
                    (values effect
                      (- (. targets agent) native))))]
    {: families : effects :class-targets targets}))

(fn snapshot [config families subtypes]
  "Return used/limit for one known family, or nil for mixed/unknown subtypes."
  (. families (family-key config subtypes)))

{: plan : snapshot : family-key}
