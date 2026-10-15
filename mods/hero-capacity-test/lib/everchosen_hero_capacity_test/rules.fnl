(fn usage [config counts]
  (collect [family record (pairs config.families)]
    (values family
      (accumulate [used 0 _ subtype (ipairs record.subtypes)]
        (+ used (or (. counts subtype) 0))))))

(fn targets [config counts]
  "Each lore keeps its owned heroes plus the family's remaining allowance."
  (let [used (usage config counts)]
    (collect [subtype record (pairs config.subtypes)]
      (values subtype
        (+ (or (. counts subtype) 0)
           (math.max 0 (- (. config.families record.family :limit)
                          (. used record.family))))))))

(fn snapshot [config counts subtypes]
  "Return one supported family's usage, or nil for an unrelated/mixed list."
  (let [first (. config.subtypes (. subtypes 1))]
    (when (and first
               (accumulate [same? true _ subtype (ipairs subtypes)]
                 (let [member (. config.subtypes subtype)]
                   (and same? member (= member.family first.family)))))
      {:used (. (usage config counts) first.family)
       :limit (. config.families first.family :limit)})))

(fn measured-offsets [first second]
  "Cap readings after effects of 1 and 2 must differ by exactly one."
  (when (accumulate [linear? true subtype value (pairs first)]
          (and linear? (< (. second subtype) 4294967295)
               (= (. second subtype) (+ value 1))))
    (collect [subtype value (pairs first)]
      (values subtype (- 1 value)))))

{: targets : snapshot : measured-offsets}
