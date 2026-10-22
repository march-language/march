# `[P4]` `--refine-infer` notes `scc-unsupported` for SCCs with nothing to infer

Filed 2026-10-21 from the inference-lite evaluation
(`specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`).

`forge refine --infer` on `~/code/depot` (30 files, zero unsettled obligations, 0 probes)
prints 966 `scc-unsupported` notes: every SCC of size > 1 that got no proposal is noted, even
when none of its members has an open site. Only SCCs with an unsettled site should be noted.

(The repeated-refusal half of this item, a refusal listed once per round, is fixed: refusals are deduplicated by slot, predicate and reason.)
