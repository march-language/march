`[P4]` Refinement: `Hamt.fold` is unannotated and was not in the fold-invariant survey

Filed 2026-10-18 with phase 3 of `specs/2026-10-18-fold-accumulator-invariants-design.md`.
§6's survey listed the unannotated stdlib folds; a re-sweep (`grep -n "^  fn fold\|^  fn
reduce" stdlib/*.march`) found three it did not:

- `Hamt.fold(node, acc, f)` (`stdlib/hamt.march`), unannotated. Its callback is CURRIED
  (`hamt_fold` calls `f(acc)`, then that result with `k`, then with `v`), unlike every other
  stdlib fold, so the arrow to declare is `b -> (k -> (v -> b))`-shaped, not the uncurried
  `b -> k -> v -> b` of `Map.fold`. Phase 3 did not annotate it: the design never surveyed
  it, and a wrong arrow shape is exactly the change §6 warns surfaces only in the compiler
  suite. Needs: the right curried annotation, a probe that a demand through it proves (a
  curried step, §3.3's peel), and the compiler suite.
- `JsonStream.fold(chunks, z, f)` and `Flow.reduce(stage, start, f)` delegate to `Seq.fold`,
  so they stay skips for the same reason `Seq.fold` does (church-encoded; decision 5). No
  change planned; listed here so the next survey does not rediscover them.
