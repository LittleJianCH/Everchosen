;;; Pure progression rules: no game interfaces are touched here.

(local data (include :everchosen_chieftains.data))

(local by-subtype (collect [_ hero (ipairs data.heroes)] hero.subtype hero))

;; Option keys shared by the MCT registration and the settings reader.
(fn level-key [slot] (.. "level_" slot))
(fn priority-key [slot] (.. "priority_" slot))

(fn clamp-rank [value fallback]
  (let [number (tonumber value)
        ;; NaN is the only number that differs from itself.
        rank (if (and number (= number number)) number fallback)]
    (math.max 1 (math.min data.max-rank (math.floor rank)))))

(fn thresholds [setting]
  "Sorted ranks at which each chieftain slot unlocks; the first is free."
  (let [levels (fcollect [slot 2 (length data.heroes) &into [0]]
                 (let [fallback (. data.levels slot)]
                   (clamp-rank (setting (level-key slot) fallback) fallback)))]
    (table.sort levels)
    levels))

(fn priority-order [setting]
  "Every hero subtype once: configured choices first, then the defaults."
  (let [order []
        seen {}]
    (fn add [subtype]
      (when (and (. by-subtype subtype) (not (. seen subtype)))
        (table.insert order subtype)
        (tset seen subtype true)))
    (each [slot hero (ipairs data.heroes)]
      (add (setting (priority-key slot) hero.subtype)))
    (each [_ hero (ipairs data.heroes)]
      (add hero.subtype))
    order))

(fn configure [setting]
  "Build a config from SETTING, a function of an option key and its fallback."
  {:levels (thresholds setting) :priority (priority-order setting)})

(fn target-count [rank levels]
  (accumulate [count 0 _ threshold (ipairs levels)]
    (if (>= rank threshold) (+ count 1) count)))

(fn owned-count [owned]
  (accumulate [count 0 _ hero (ipairs data.heroes)]
    (if (. owned hero.subtype) (+ count 1) count)))

(fn next-missing [rank config owned]
  "The subtype to add next, or nil once the target count is met.
OWNED maps subtype keys to characters."
  (if (< (owned-count owned) (target-count rank config.levels))
      (accumulate [missing nil _ subtype (ipairs config.priority)
                   &until missing]
        (if (. owned subtype) nil subtype))))

{: by-subtype : level-key : priority-key : configure : target-count
 : next-missing}
