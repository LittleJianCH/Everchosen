(fn catalog [members metadata]
  "Group observed native subtypes; different capacity classes stay separate."
  (let [indexed
        (accumulate [groups {} index member (ipairs members)]
          (let [meta (or (. metadata member.subtype) {})
                key (.. member.agent ":" (or meta.family member.subtype))
                group (or (. groups key)
                          {: key :agent member.agent :order index
                           :name-key meta.name_key
                           :name member.name :icon (or meta.icon member.icon)
                           :subtypes [] :members {}})]
            (when (not (. group.members member.subtype))
              (tset group.members member.subtype true)
              (table.insert group.subtypes member.subtype))
            (tset groups key group)
            groups))
        result (icollect [_ group (pairs indexed)] group)]
    (table.sort result #(< $1.order $2.order))
    result))

(fn selectable? [state]
  (not (or (= state :inactive) (= state :selected_inactive))))

(fn page [entries number size]
  "Return the visible entries and a page number clamped to this catalog."
  (let [pages (math.max 1 (math.ceil (/ (length entries) size)))
        current (math.max 1 (math.min pages number))
        first (+ 1 (* (- current 1) size))]
    (values (fcollect [index first
                      (math.min (length entries) (+ first size -1))]
              (. entries index))
            current pages)))

{: catalog : selectable? : page}
