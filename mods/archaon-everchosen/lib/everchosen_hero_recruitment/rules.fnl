(fn catalog [families]
  "Use explicit family records; opening the panel never scans native classes."
  (let [result
        (icollect [key family (pairs families)]
          {: key :agent family.agent :private? family.private
           :name-key family.name_key :description-key family.description_key
           :icon family.icon :subtypes family.subtypes
           :members (collect [_ subtype (ipairs family.subtypes)]
                      (values subtype true))})]
    (table.sort result #(< $1.key $2.key))
    result))

(fn selectable? [state]
  (not (or (= state :inactive) (= state :selected_inactive))))

(fn selected? [state]
  (or (= state :selected) (= state :selected_hover)
      (= state :selected_down) (= state :selected_down_off)
      (= state :selected_inactive)))

(fn page [entries number size]
  "Return the visible entries and a page number clamped to this catalog."
  (let [pages (math.max 1 (math.ceil (/ (length entries) size)))
        current (math.max 1 (math.min pages number))
        first (+ 1 (* (- current 1) size))]
    (values (fcollect [index first
                      (math.min (length entries) (+ first size -1))]
              (. entries index))
            current pages)))

{: catalog : selectable? : selected? : page}
