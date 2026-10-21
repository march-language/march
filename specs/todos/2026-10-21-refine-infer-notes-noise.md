# `[P4]` `--refine-infer` notes `scc-unsupported` for SCCs with nothing to infer, and repeats refusals

Filed 2026-10-21 from the inference-lite evaluation
(`specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`).

`forge refine --infer` on `~/code/depot` (30 files, zero unsettled obligations, 0 probes)
prints 966 `scc-unsupported` notes: every SCC of size > 1 that got no proposal is noted, even
when none of its members has an open site. Only SCCs with an unsettled site should be noted.

Separately, a refusal found in round 1 is reported again in round 2 (the JSON `refused` array
lists `pop_n param j _ == 0 caller-violation` twice). Refusals should be deduplicated by
(slot, predicate).
