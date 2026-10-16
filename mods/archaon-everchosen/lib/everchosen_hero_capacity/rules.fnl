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

(fn class-targets [config families counts private?]
  (collect [agent _ (pairs config.classes)]
    (let [retained (. families (. config.native_page agent))
          used (accumulate [total 0 subtype class
                            (pairs config.counted_subtypes)]
                 (+ total (if (= class agent) (or (. counts subtype) 0) 0)))
          ;; Imported heroes consume their own quota, not the native family's.
          imported (- used retained.used)
          native (+ retained.limit imported)]
      ;; One extra native slot keeps private-page candidates accessible even
      ;; when the retained hero is full. The private page gates its own quota.
      (values agent (if private? (+ (math.max native used) 1) native)))))

(fn plan [config source-bonus extras counts native-caps private?]
  "Plan family quotas and the six native recruitment capacities.
  native-caps must be read without this controller's effect bundle.
  private? opens one shared navigation slot, never a per-family cap switch."
  (let [families (family-state config source-bonus extras counts)
        targets (class-targets config families counts private?)
        effects (collect [agent effect (pairs config.classes)]
                  (let [native (. native-caps agent)]
                    (assert (< native unlimited)
                            (.. "Cannot constrain unlimited hero class: " agent))
                    (values effect
                      (- (. targets agent) native))))]
    {: families : effects :class-targets targets : private?}))

(fn snapshot [config families subtypes]
  "Return used/limit for one known family, or nil for mixed/unknown subtypes."
  (. families (family-key config subtypes)))

{: plan : snapshot : family-key}
