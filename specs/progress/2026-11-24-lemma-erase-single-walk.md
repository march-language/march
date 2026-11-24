# Lemma erasure walks the program once, not once per lemma (2026-11-24)

`Lemma_erase.drop_unreferenced` called `mentions name whole` for every `@[lemma]`
declaration. Each call walks every expression of the whole program, and the stdlib has
128 lemmas, so hello world spent ~0.39 s in `Lemma_erase.erase_module`, the largest single
stdlib cost after typechecking.

Now `mentioned_names` collects, in one walk with the exact traversal `mentions` used, the
set of last-segment names any expression mentions, and `drop_unreferenced` checks
membership. `mentions n` is `SS.mem n (mentioned_names decls)`, so the result is the same by
construction. Both callers (`erase_module_with` and `Ghost.erase`) get it. `bin/main.ml`
also builds `lemma_reserved` once instead of per call.

Tests: `test/test_refine_lemma.ml` `drop_unreferenced_cases` (registered in
`test_refinecheck.ml`'s reflect-lemma group): a lemma used only as a value from a nested
module, an impl method or an actor handler is kept; an unmentioned one is dropped;
`mentioned_names` agrees with `mentions`. Proven red by blinding the traversal to `DImpl`.

Design: `specs/2026-11-24-stdlib-compile-floor-design.md` Part 1. Part 2 (a reachability
prune before mono) follows as its own PR, per
`specs/plans/2026-11-24-stdlib-compile-floor-plan.md`.
