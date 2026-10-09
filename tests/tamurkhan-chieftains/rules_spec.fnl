(local data (include :everchosen_chieftains.data))
(local rules (include :everchosen_chieftains.rules))
(local config (rules.configure (fn [_ fallback] fallback)))

(describe "Chieftain progression"
  (fn []
    (it "fills only the shortfall when a rank threshold is crossed"
      (fn []
        (let [owned (collect [i hero (ipairs data.heroes) &until (> i 3)]
                      hero.subtype true)]
          (assert.is_nil (rules.next-missing 14 config owned))
          (assert.equals (. data.heroes 4 :subtype)
                         (rules.next-missing 15 config owned))
          (tset owned (. data.heroes 4 :subtype) true)
          (assert.is_nil (rules.next-missing 15 config owned)))))))
