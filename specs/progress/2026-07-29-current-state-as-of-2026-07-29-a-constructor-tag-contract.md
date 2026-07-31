# Current State (as of 2026-07-29, a CONSTRUCTOR-TAG contract composes too)


**Counts:** `test_refinecheck` 358 (was 352), typing corpus 231/231 (was
229/229), `check-docs.sh` exit 0, stdlib false-positive sweep EMPTY.

The last refined form that did not compose across a call boundary now does.

**The gap.** `fn inner(o : {Option(Int) | is_Some(_)})` called with a caller's
own parameter `p : {Option(Int) | is_Some(_)}` reported `1 proved, 1 skipped` —
the proof being `main`'s literal call, the skip being `inner(p)` inside
`outer`'s body — while the identically-shaped MEASURE contract
(`{Tree | size(_) > 0}`) composed. `refined_scope_ty` admits every registered
ADT, `Option` included, so the scope entry carrying `p`'s promise DID exist; the
gap was downstream, in `reflect_dt`'s `EVar` arm, which declares a bare
caller-scope name as a FRESH, UNCONSTRAINED datatype constant and never
consulted the scope channel. The VC was therefore satisfiable both ways. Same
shape of gap `measure_of_var` had before the measure fix earlier the same day.

**The fix.** `load_scope_tester_facts` in `lib/refinecheck/refine_check.ml`,
the tester analogue of `load_scope_measure_facts`, wired into `check_call`'s
`resolve_tester` immediately before it reflects the subject (load-before-reflect,
mirroring the measure side). It fires only when the actual is a bare name whose
measure-only ADT scope entry's predicate is EXACTLY a bare tester over its own
refined value — all three spellings accepted (`_`, the declared binder, the
parameter's own name) — for the SAME constructor the goal tests and at the same
datatype sort. It then asserts that tester over `Const x`, the very term the
goal side builds, so assumption and goal meet on one symbol; both sides emit the
same `(x, SData adt)` declaration and the VC builder's existing (name, sort)
dedup covers it, with a per-(name, sort, ctor) memo keeping the assumption from
being asserted twice.

**Deliberately narrow.** A caller promising `is_None(_)` into a callee wanting
`is_Some(_)` loads NOTHING and stays skipped. Assuming the caller's promise
verbatim there would also be sound — and, the two testers being exclusive on
`Option`, would turn the call into a reported violation — but it is a strictly
wider claim than "the caller already promised the goal", and a missed report
costs nothing while a wrong fact is the failure this subsystem exists to
prevent. Compound predicates, negations and conjunctions likewise load nothing.

**+6 tests (352 → 358)**, a new `compose-tag` group asserting obligation COUNTS
rather than absence of a diagnostic: the three spellings compose (2 proved,
0 skipped each — all three were `1 proved, 1 skipped` pre-fix, verified against
a file-copy-swapped pre-fix binary), and the different-constructor, `let`-rebind
and `match`-shadow cases must not (1 proved, 1 skipped each — the cardinal-sin
controls). Bracketed in the corpus by `accept/t129_refine_tag_contract_composes_call`
and `reject/t130_refine_tag_composition_narrowed_violation`, the latter pinning
that a real failure through the same non-composing shape is still reported.

For everything prior to this point, see
[specs/progress_through_july_2026.md](progress_through_july_2026.md) — the
prior progress log, archived because it had grown too large to be a useful
implementer-level record. New entries go above this line, newest first, in
the same format as the archive.
