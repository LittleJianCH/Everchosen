(local world (include :everchosen_inheritance.world))

(fn selected [rewards balances]
  "Return the highest reached bundle per glory resource; tiers replace."
  (let [best {}]
    (each [_ reward (pairs rewards)]
      (let [previous (. best reward.resource)]
        (when (and (>= (or (. balances reward.resource) 0) reward.minimum)
                   (or (not previous) (> reward.minimum previous.minimum)))
          (tset best reward.resource reward))))
    (collect [key reward (pairs best)] (values key reward.bundle))))

(fn reconcile [faction character rewards]
  ;; Character bundles follow a wounded or reassigned general. Their effects
  ;; use general_to_force_own, so a replacement commander cannot inherit them.
  (let [balances (collect [_ reward (pairs rewards)]
                   (values reward.resource
                           (: (world.resource faction reward.resource) :value)))
        wanted (selected rewards balances)]
    (each [_ reward (pairs rewards)]
      (let [has? (character:has_effect_bundle reward.bundle)]
        (if (= (. wanted reward.resource) reward.bundle)
            (when (not has?)
              (cm:apply_effect_bundle_to_character reward.bundle character 0))
            has? (cm:remove_effect_bundle_from_character
                   reward.bundle character))))))

{: selected : reconcile}
