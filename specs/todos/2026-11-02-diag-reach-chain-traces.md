`[P3]` Diagnostics: render "reached from `main`: main → step" chains (caps, role grants, no_panic,
pure, deterministic, no_alloc) as a span-per-hop trace with the USE as the primary span, via one shared helper.
specs/plans/2026-11-02-diagnostics-depth-plan.md §X7.

2026-11-03: `cap_grant_exceeded` traces and the `cap_needs` chain fold landed
(`specs/progress/2026-11-03-diag-x3-x4-finish-x7-traces.md`). Open: role grants, `no_panic`, `pure`,
`deterministic`, `no_alloc` chains on the same helper.
