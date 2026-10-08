(local data (include :everchosen_chieftains.data))
(local by-subtype {})
(each [_ hero (ipairs data.heroes)] (tset by-subtype hero.subtype hero))

(fn configure [setting]
  (local levels [0])
  (for [i 2 (# data.heroes)]
    (local fallback (. data.levels i))
    (var rank (tonumber (setting (.. :level_ i) fallback)))
    (when (or (not rank) (not= rank rank)) (set rank fallback))
    (tset levels i (math.max 1 (math.min 25 (math.floor rank)))))
  (table.sort levels)
  (local priority [])
  (local seen {})
  (fn append [subtype]
    (when (and (. by-subtype subtype) (not (. seen subtype)))
      (table.insert priority subtype)
      (tset seen subtype true)))
  (each [i hero (ipairs data.heroes)]
    (append (setting (.. :priority_ i) hero.subtype)))
  (each [_ hero (ipairs data.heroes)] (append hero.subtype))
  {: levels : priority})

(fn target-count [rank levels]
  (var count 0)
  (each [_ threshold (ipairs levels)]
    (when (>= rank threshold) (set count (+ count 1))))
  count)

(fn next-missing [rank config owned]
  (var count 0)
  (each [_ hero (ipairs data.heroes)]
    (when (. owned hero.subtype) (set count (+ count 1))))
  (if (< count (target-count rank config.levels))
      (do
        (var missing nil)
        (each [_ subtype (ipairs config.priority)]
          (when (and (not missing) (not (. owned subtype)))
            (set missing subtype)))
        missing)
      nil))

{: configure : target-count : next-missing : by-subtype}
