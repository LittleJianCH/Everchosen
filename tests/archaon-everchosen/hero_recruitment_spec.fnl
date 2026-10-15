(local rules (include :everchosen_hero_recruitment.rules))

(describe "hero-family navigation rules"
  (fn []
    (it "merges lores and repeated observations without merging capacity pools"
      (fn []
        (let [metadata {:fire {:family :shaman :name_key :shaman-name}
                        :death {:family :shaman :name_key :shaman-name}}
              groups (rules.catalog
                       [{:agent :wizard :subtype :fire}
                        {:agent :wizard :subtype :death}
                        {:agent :wizard :subtype :fire}
                        {:agent :dignitary :subtype :fire}]
                       metadata)]
          (assert.equals 2 (length groups))
          (assert.same [:fire :death] (. groups 1 :subtypes))
          (assert.equals :shaman-name (. groups 1 :name-key))
          (assert.equals :dignitary (. groups 2 :agent)))))
    (it "retains unknown external heroes as separate native-named families"
      (fn []
        (let [groups (rules.catalog
                       [{:agent :engineer :subtype :custom-a :name "A"}
                        {:agent :engineer :subtype :custom-b :name "B"}]
                       {})]
          (assert.equals 2 (length groups))
          (assert.equals "A" (. groups 1 :name))
          (assert.same {:custom-b true} (. groups 2 :members)))))
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
