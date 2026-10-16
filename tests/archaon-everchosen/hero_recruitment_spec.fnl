(local rules (include :everchosen_hero_recruitment.rules))

(describe "unified hero-family catalog rules"
  (fn []
    (it "uses explicit hero families without scanning native classes"
      (fn []
        (let [groups (rules.catalog
                       {:shaman {:agent :wizard
                                 :name_key :shaman-name
                                 :description_key :shaman-description
                                 :icon "shaman.png" :subtypes [:fire :death]}
                        :sorcerer {:agent :wizard
                                   :name_key :sorcerer-name
                                   :subtypes [:chaos-fire :chaos-death]}})]
          (assert.equals 2 (length groups))
          (assert.equals :shaman (. groups 1 :key))
          (assert.same [:fire :death] (. groups 1 :subtypes))
          (assert.equals :shaman-name (. groups 1 :name-key))
          (assert.equals :shaman-description (. groups 1 :description-key))
          (assert.same {:fire true :death true} (. groups 1 :members))
          (assert.equals :wizard (. groups 2 :agent)))))
    (it "recognises native selected-hover and selected-inactive states"
      (fn []
        (assert.is_true (rules.selected? :selected_hover))
        (assert.is_true (rules.selectable? :selected_hover))
        (assert.is_true (rules.selected? :selected_inactive))
        (assert.is_false (rules.selectable? :selected_inactive))
        (assert.is_false (rules.selected? :inactive))))
    (it "keeps every entry accessible when the catalog shrinks between regions"
      (fn []
        (let [(entries page pages) (rules.page [1 2 3 4 5] 9 3)]
          (assert.same [4 5] entries)
          (assert.equals 2 page)
          (assert.equals 2 pages))
        (let [(entries page pages) (rules.page [] 2 8)]
          (assert.same [] entries)
          (assert.equals 1 page)
          (assert.equals 1 pages))))))
