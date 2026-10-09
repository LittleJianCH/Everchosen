(local data (include :everchosen_inheritance.data))

(fn classify [faction subculture]
  "Return an inherited mechanic, or nil for an unaligned source."
  (if (= faction data.belakor) :gg
      (or (. data.allegiance faction) (. data.subcultures subculture))))

(fn state-key [god]
  (.. data.prefix "unlocked_" god))

(fn manifestation-key [index]
  (.. "wh3_main_ritual_belakor_gg_" index))

{: classify : state-key : manifestation-key}
