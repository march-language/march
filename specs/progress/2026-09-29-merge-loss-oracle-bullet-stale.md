# Merge-loss todo: "differential oracle cannot see these crashes" was already fixed

Docs-only. The bullet in
`specs/progress/2026-07-24-merge-loss-round-2-14-commits-on-docs-core-march-types-skeleton.md`
asked for an expected-stdout anchor for `iolist_template`, `string_pipeline` and `deque_ops`
so a compiled crash is not invisible to an interpreter-leg differential sweep.
`test/test_bench_gate.ml` already does this: lines 110-113 pin `tree_transform`,
`iolist_template` (`2092654`), `string_pipeline` (`644449`) and `deque_ops`
(`20001000000`) as `Exact`, compiled and run with no interpreter involved. The bullet is
struck through with that pointer. The `.ll` placement bullet is left open (#653 decided the
`.ll` stays beside the source, so that one is a decision to record, not work to do here).
