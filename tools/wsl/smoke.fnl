;; Checks the installed toolchain, not WH3 gameplay or engine behavior.
(macro twice [value] `(+ ,value ,value))

(describe "Fennel compiled for Lua 5.1"
  (fn []
    (it "runs under the required Lua version"
      (fn [] (assert.equals "Lua 5.1" _VERSION)))
    (it "expands macros before runtime"
      (fn []
        (assert.equals 12 (twice 6))
        (assert.is_nil package.loaded.fennel)))
    (it "preserves UTF-8 strings through compilation"
      (fn []
        (local label "永世神选")
        (assert.equals 12 (length label))
        (assert.equals 230 (string.byte label 1))))
    (it "loads Lua 5.1 native dependencies"
      (fn []
        (local lfs (require :lfs))
        (local system (require :system))
        (assert.equals :directory (lfs.attributes "." :mode))
        (assert.equals :number (type (system.gettime)))))))
