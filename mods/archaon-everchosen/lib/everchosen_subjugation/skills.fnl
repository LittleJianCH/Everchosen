;; WH3 9.0.3 AK: SkillList/HiddenSkillList expose Key and Level;
;; SkillPointsAvailable is the unspent budget. Only named skills are queried.
;; CA's add_skill wrapper accepts ignore_requirements/ignore_skill_points.
(fn read-number [character expression]
  (let [value (tonumber (: (cco :CcoCampaignCharacter (character:cqi))
                          :Call expression))]
    (assert value (.. "Cannot read transferred character skill: " expression))
    value))

(fn unspent [character]
  (read-number character :SkillPointsAvailable))

(fn level [character key]
  (if (character:has_skill key)
      (read-number character
        (.. "Join(SkillList, HiddenSkillList).Filter(Key == \"" key
            "\").FirstContext.Level"))
      0))

(fn capture [character slots]
  "Snapshot changed positions before transfer; leave other lines intact."
  (let [limits (accumulate [limits {} _ slot (ipairs slots)]
                 (do
                   (tset limits slot.source
                     (math.max (or (. limits slot.source) 0) slot.source_max))
                   (tset limits slot.target
                     (math.max (or (. limits slot.target) 0) slot.target_max))
                   limits))
        held (collect [key maximum (pairs limits)]
               (let [points (level character key)]
                 (assert (and (>= points 0) (<= points maximum))
                         "Transferred skill exceeds the native level limit")
                 (values key points)))
        wanted (collect [_ slot (ipairs slots)]
                 (values slot.target (. held slot.source)))
        entries (icollect [key _ (pairs limits)]
                  {: key :held (. held key) :wanted (or (. wanted key) 0)})]
    (table.sort entries #(< $1.key $2.key))
    {: entries :unspent (unspent character) :stage :remove}))

(fn matches? [character plan]
  (and (= (unspent character) plan.unspent)
       (accumulate [same? true _ entry (ipairs plan.entries)
                    &until (not same?)]
         (if (= entry.wanted 0)
             (not (character:has_skill entry.key))
             (= (level character entry.key) entry.wanted)))))

(fn cleared? [character plan]
  (accumulate [clear? true _ entry (ipairs plan.entries) &until (not clear?)]
    (not (character:has_skill entry.key))))

(fn remove-points [character plan persist]
  ;; The old tree may no longer expose a Cco skill context after transfer.
  ;; Use levels captured while it was active; has_skill confirms removal.
  (set plan.stage :removed)
  (persist)
  (each [_ entry (ipairs plan.entries)]
    (for [_ 1 entry.held]
      (cm:remove_skill_point (cm:char_lookup_str character) entry.key))))

(fn add-points [character plan persist]
  (let [refunded (- (unspent character) plan.unspent)
        points (accumulate [total 0 _ entry (ipairs plan.entries)]
                 (+ total entry.wanted))]
    (assert (and (>= refunded 0) (<= refunded points))
            "Unexpected skill-point budget during character transfer")
    (set plan.stage :added)
    (persist)
    ;; Consume only points actually refunded by removal. Ignore prerequisites
    ;; because these are existing allocations, not new player choices.
    (accumulate [remaining refunded _ entry (ipairs plan.entries)]
      (let [spent (math.min remaining entry.wanted)]
        (for [point 1 entry.wanted]
          (cm:add_skill character entry.key true (> point spent)))
        (- remaining spent)))))

(fn advance [character plan persist]
  "Submit each phase once; return true after observing the exact allocation."
  (if (= plan.stage :done) true
      (matches? character plan)
      (do (set plan.stage :done) (persist) true)
      (= plan.stage :remove)
      (do (remove-points character plan persist) false)
      (and (= plan.stage :removed) (cleared? character plan))
      (do (add-points character plan persist) false)
      false))

{: capture : advance}
