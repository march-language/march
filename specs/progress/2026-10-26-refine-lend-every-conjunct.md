# Lend every conjunct of a proved list return (L3)

Landed 2026-10-26 on `claude/refine-length-facts`. No todo tracked it; the source is row 11 of
the 2026-10-24 stdlib refinement audit (probe p12: `fa`'s `subset(elts(_), elts(xs)) &&
len(_) <= len(xs)` post proved, its consumer `need_le(xs, fa(xs, …))` solver-undecided, while
a `len`-only post was lent).

```march
fn cp(xs : List(a)) : {List(a) | subset(elts(_), elts(xs)) && len(_) == len(xs)} do
  match xs do
    Nil -> Nil
    Cons(h, t) -> Cons(h, cp(t))
  end
end
fn u1(xs : List(Int)) : Int do need_len_eq(xs, cp(xs)) end   -- was solver-undecided; now proved
fn u2(xs : List(Int)) : Int do need_sub(xs, cp(xs)) end      -- was solver-undecided; now proved
```

## Root cause

`Refine_call.check_call`'s `set_of_call m0 fname cargs` stands a call's result up as a fresh
constant for ONE measure `m0` (`len` or `elts`) and loads the callee's proved post over it.
Its measure resolver `rm` answers only `m0` of the binder (a `len` constant says nothing about
`elts(_)`), and the post was translated WHOLE, so for a two-measure conjunction the other
measure's conjunct failed to translate and `smt_of` dropped the entire predicate. The
definition side proved the post; the caller got neither half. (The audit saw the `elts` half
lent in some shapes: a `let`-bound result goes through `load_scope_measure_facts`, whose
resolver answers every measure of the bound name, which is why the let-bound test passed on
the base.)

## Fix (`lib/refinecheck/refine_call.ml`)

`set_of_call` translates the post conjunct by conjunct (`conjuncts_of`) and pushes each one
that translates. Every conjunct of a proved (or `@[assume]`d) post holds on its own. A
conjunct carrying a division is reflected with its own definedness side condition, which
held, since the whole conjunction evaluated to `true`. Nothing changes about what is lent:
`gate_unverified_posts` still clears an unproved post entirely before any call site sees it.

## Tests (`gap-lend-conjuncts`, 4 cases)

RED on the base (received): `need_len_eq(xs, cp(xs))`: `solver-undecided`, expected proved
(`need_sub(xs, cp(xs))` and `need_ne(cp(xs))` also asserted proved); name capture
`need_len_eq(ys, cp(ys))`: `solver-undecided`, expected proved. Controls that held before and
after: a let-bound `ys = cp(xs)` proves; a body that DROPS elements (`Cons(_, t) -> cp(t)`,
`elts` half true, `len` half false) is not proved and lends nothing, not even the true `elts`
half; `need_len_eq(xs, cp(ys))` is not proved (the callee's `xs` is the actual `ys`).
GREEN: all 4.

## Oracle

`scripts/refine-oracle.sh check` against the pre-L1 baseline: the diff is exactly L2's (one
`partial-conjunct` skip per fixture becomes a proof, the stdlib `nth` line) and nothing
more, so this gap moved no corpus verdict. No fixture calls a function with a two-measure
proved list post at a demand for one of its halves.

## Rulings

- Ruling: split at the top-level `&&` only — a disjunction or negation is one fact and stays
  whole — cost if wrong: none; a deeper split would be unsound for `||`.
- Ruling: an unproved conjunction lends nothing even when one conjunct is true — the
  definition side records one verdict per post, and lending a conjunct the checker never
  proved separately would be an unproved fact — cost if wrong: a lost proof (the control
  pins it).
