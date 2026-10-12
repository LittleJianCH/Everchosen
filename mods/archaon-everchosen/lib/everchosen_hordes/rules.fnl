(fn sorted-keys [entries]
  (let [keys (icollect [key _ (pairs entries)] key)]
    (table.sort keys)
    keys))

(fn camp-units [config buildings]
  "Completed building keys become unit -> capped refresh chance."
  (let [bonus (accumulate [highest 0 _ key (ipairs buildings)]
                (math.max highest (or (. config.horn_bonus key) 0)))]
    (accumulate [units {} _ building (ipairs buildings)]
      (do
        (each [_ unit (ipairs (or (. config.buildings building) []))]
          (tset units unit
            (math.min 100 (+ (. config.units unit :chance) bonus))))
        units))))

(fn provinces [camps]
  "Merge camps by province; overlapping unit chances take their maximum."
  (accumulate [result {} _ camp (ipairs camps)]
    (let [entry (or (. result camp.province)
                    {:region camp.region :units {}})]
      (each [unit chance (pairs camp.units)]
        (tset entry.units unit
          (math.max chance (or (. entry.units unit) 0))))
      (tset result camp.province entry)
      result)))

(fn capacity [active-cap our-cap total-cap stock]
  "Withdraw unused capacity while retaining stock above other sources' cap."
  (let [other-cap (- total-cap our-cap)
        retained (math.min our-cap (math.max 0 (- stock other-cap)))]
    (math.max active-cap retained)))

{: sorted-keys : camp-units : provinces : capacity}
