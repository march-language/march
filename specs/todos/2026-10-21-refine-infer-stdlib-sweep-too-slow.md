# `[P3]` `--refine-infer --refine-infer-stdlib` on the whole stdlib takes 48 minutes and reaches a fraction of it

Filed 2026-10-21 from the inference-lite evaluation
(`specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`).

A dry run on a trivial entry file (`mod EvalStd do fn main() : Int do 0 end end`) with every
stdlib function a target took 2862 s under a private HOME, against 1 s for a plain `--check`.
It spent the whole default budget (3000 probes, global) in round 1 and noted
`budget-exhausted` for 1554 functions; `HashMap.filter`, `Seq.filter`, `Flow.filter` and
`Gen.filter` were never probed. A probe averages about 1 s: each one re-walks a pruned tree whose
callers include large stdlib modules, and an undecidable candidate can hold the solver to its
timeout.

Per-file user-code runs stay in budget (test/native: median 1.35×, aggregate 1.44× of a cold
`--check`). The stdlib dry run was meant as the rediscovery corpus (design §6). Options: a
per-module time budget, progress output, or rediscovery fixtures (one stripped function plus a
caller, as in the `infer-abstract` tests) instead of a whole-stdlib run.
