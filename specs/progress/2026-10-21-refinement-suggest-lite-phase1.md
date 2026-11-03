# Inference-lite, phase 1: slots, mined vocabulary, the oracle; K5 relational preconditions

Landed 2026-10-21. Design: `specs/2026-10-20-refinement-suggest-lite-design.md` §1-§2. Plan Tasks 4-6.
Not yet reachable from the CLI (that is `--refine-infer`, plan Task 11); CHANGELOG and the language
reference are updated then.

## What landed

| Module | Responsibility |
|---|---|
| `lib/refinecheck/infer_slot.ml` | Refinable slots per user function: scalar params/returns, element slots of registered containers (nested, through tuple components), kinds K1-K5; refined positions and `trusted`/`assume` functions yield none; `unannotated` signatures; `respell` (whole annotation with the slot refined) |
| `lib/refinecheck/infer_vocab.ml` | Mined candidates, four ranks (transported demands of skipped obligations in the function, house signature refinements, body comparisons, the fixed grammar); filters (known predicate vocabulary, names in scope — parameters earlier in the list for a parameter slot — no `p(_)` outside K6); cap 12 with truncation reported; weakest-first order by implication asked of the real checker, cached |
| `lib/refinecheck/infer_oracle.ml` | One probe per (slot, candidate) on target + callers; per-kind admissibility: preconditions close a body site, open none, no caller violation (else `Refuse`), satisfiable; returns TRUE by `post_holds` and USEFUL by closing a caller site; `best_for_slot` (preconditions: best net gain; returns: most callers closed; ties to the weaker) |

## Tests

`test_refinecheck` group `infer-vocab` (14): slots (element param K3, refined element skipped,
trusted skipped, unannotated reported, tuple-component respell); vocabulary (R1's demand first,
cap 12 + truncation, no `p(_)` outside K6, implication order with dedup, parse-back); oracle (R1
proposes `_ < n`; `_ <= n` preferred over `_ < n`; a return takes the candidate closing the most
callers, `_ > 0` over `_ != 0`; an exhausted budget is reported).

## Perf

`stdlib/list.march`, cold, 3 runs, medians: `--check` 1.754 s, `--refine-suggest-all` 1.862 s (1.06×).
