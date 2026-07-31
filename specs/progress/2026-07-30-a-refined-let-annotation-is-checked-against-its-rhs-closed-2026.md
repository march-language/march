# A refined `let` annotation is checked against its RHS (CLOSED 2026-07-30)


`let ys : {List(Int) | len(_) > 0} = []` used to report `1 proved, 0 violated,
0 skipped` and exit 0 even under `cap verified`: the annotation entered the
scope channel unconditionally, so `inner(ys)` was **falsely proved** off a
premise nothing had established. It was the one refined position in the
language that obliged nobody.

**Closed** by `check_let_annotation` (`lib/refinecheck/refine_check.ml`), which
reflects the binding as a synthesized one-parameter call — the annotation is the
precondition, the bound expression the sole argument — and routes it through
`check_call`, inheriting every resolver and the definite-failure stance. Two
details are load-bearing: `param_names` carries the LET NAME (not the
refinement's binder), which is what makes the `len(ys)` spelling resolve; and
the bound name is shadowed out of all three fact channels first, so an outer
value's fact can never be attributed to this binder.

An unproven annotation now grants **no fact**, rather than being
unverified-but-trusted: `let ys : {List(Int) | len(_) > 0} = zs` for an opaque
`zs` leaves the annotation skipped AND the downstream call skipped, instead of
proving the call off an assumption the binding failed to establish. A proof
resting on an unverified premise is precisely what this closes.

Side effect: the bound-name spelling at `Int` (`{Int | n > 0}` over `let n`),
previously not resolved at all and merely skipped, is now checked too. All three
spellings (`_`, a declared binder, the bound name) behave alike. Bracketed by
`accept/t130_refine_let_annotation_checked_and_composes` /
`reject/t131_refine_let_annotation_false`; +7 refinecheck tests (358 → 365).
Stdlib and corpus contain zero refined `let` annotations, so nothing in-tree
changed behaviour.

---
