# Return contracts on builtins, starting with `pmap_threshold`

**Landed 2026-09-16.** Plan: `specs/plans/2026-09-16-refinement-precision-plan.md`
(Part A, phase A2). Census that sized it:
`specs/progress/2026-09-16-refine-skip-census.md`.

## The gap

A builtin has no `fn_def`, so `postcond_of` could compute nothing for it and
`let t = pmap_threshold()` reached the next call site as an unconstrained
constant. Three of `stdlib/list.march`'s four user-code skips were exactly
that: `List.pmap`, `pfilter` and `preduce` each call `chunks(xs, t)` against
`{Int | _ > 0}`.

`Refine_encode.builtin_ret_refinements` supplies the contract as
`(builtin -> binder, predicate)`, the same shape `fn_sig.ret` uses, and
`postcond_of` consults it **after** name resolution and the callee env — a
user function or local binding sharing the spelling is the one the call
reaches, and its contract must win. A fixture pins that: a user
`pmap_threshold()` returning `-5` is reported as a violation, not proved.

## The bar for an entry, and the bug found while meeting it

A propagated postcondition joins the assumption set of every downstream proof,
so a wrong entry is a false-*positive* engine. `@[assume]` at least declares
its trust in the source and counts itself in the ledger's `trusted` column; an
entry here is invisible to a reader of the program. The bar is therefore
higher than `@[assume]`'s: **the contract must be true by construction,
enforced somewhere a test pins.**

Checking that for `pmap_threshold` turned up a bug. Its only producer is
`--pmap-threshold`, which took any integer — and `--pmap-threshold 0` does not
mean "always parallel", it **hangs**:

```
$ march --pmap-threshold 0 probe.march
0          <- the threshold prints
           <- List.pmap never returns
```

bin/main.ml now rejects a value below 1 before it reaches the interpreter or
codegen. That check earns its place on its own (a hang is a bug regardless of
refinements) and it is what makes the contract enforced rather than assumed.
The CLI rejection is pinned in the same test group as the contract it
justifies: separating them is how the enforcement quietly disappears later
while the contract stays.

## Measurements

- `stdlib/list.march`, user-code slice: 12 proved / 5 skipped -> **15 proved /
  2 skipped**. Whole ledger: 38 proved / 46 skipped -> **41 proved / 43
  skipped**. The delta is exactly the three `chunks` sites.
- CI's skip ceiling lowered 46 -> 43 in the same change. A precision win that
  does not tighten the ratchet silently licenses a regression back to the old
  number.
- Coverage audit unchanged: 114 enforced, 0 inert, 0 unenforced.
- `test_refinecheck.exe`: 890/890. The new `builtin-contract` group's two
  propagation cases are RED without the table (verified by deleting the
  `postcond_of` arm and re-running).

## What is deliberately NOT in the table

Only `pmap_threshold`. Every other value-returning builtin either has no
contract worth stating or has no enforcement point to rest one on, and an
entry without an enforcer is the failure mode this table's comment exists to
prevent.
