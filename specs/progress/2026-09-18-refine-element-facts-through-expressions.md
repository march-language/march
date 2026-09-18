# Element facts flow through expressions, proved container returns, and return tails

**Landed 2026-09-18.** Design: `specs/2026-09-18-parametric-element-flow-design.md` §2. Plan: `specs/plans/2026-09-18-parametric-element-flow-plan.md`, Phase 1.

## What changed (`lib/refinecheck/refine_check.ml`)

- **`container_entry_of_expr`** answers "which element refinements does this
  value's container hold?" in one place: a variable (its `contenv` entry),
  `e : T`, a call through the parametric rule with its actuals resolved
  recursively (`take(reverse(xs), 2)`), a structural self-call (Phase 2), or a
  call whose declared container return was proved (`declared_elem_return`).
  `check_elements`' variable arm, `parametric_return`'s actuals, the
  `let` binding arm and `match`'s element facts all go through it, so
  `sum_pos(List.reverse(xs))` and `match List.head_opt(xs) do Some(h) ->`
  work like their `let`-bound spellings. `check_elements` gained the
  `cbenv` for it.
- **`elem_ret_proved`** (`Refine_param`) holds every function whose
  container-return tails were all proved. `gate_elem_returns` fills it before
  the walk: each candidate is walked by the ordinary `visit_fn` inside
  `Obligation.with_scratch`, with a throwaway error context and
  `strict_verified` / `unverified_hinted` saved, and reads
  `last_elem_return_proved` (the `check_elements` verdicts of its tails).
  Rounds repeat while something new proves, so a chain in reverse declaration
  order resolves. An element predicate that names a parameter
  (`List({Int | _ < n})`) is never a fact at a call site (`entry_is_closed`).
- **Return tails are checked inside the walk.** `visit_fn` used to check
  container-return tails against the parameter-only env before walking the
  body, so a tail naming a block-local `let` was a skip. Now `visit` checks
  each tail (identified physically, from `tails`) when it reaches it, with the
  scope, path and container env at that point (`ret_elem_demand`, suspended
  in nested lambdas and local `fn`s). A tail the walk never reaches falls back
  to the old check, so every tail is checked exactly once, which a ledger test
  pins.

## Tests

`test/test_refinecheck.ml`, group `element-flow` (7 cases, typed harness):
a polymorphic call as an argument; nested calls; a `match` on a call; a
proved declared return (with an unproved-return control); the
reverse-declaration-order fixpoint; a return tail through a `let`; a
violating tail under a `let` reported once. With the test file copied onto an
untouched `HEAD` checkout, every case fails; with the change, all pass.

## Measurements

`stdlib/list.march`: 43 proved / 40 skipped before and after, with an
identical per-site skip list. The stdlib declares no element-refined returns,
so the gate walks nothing there.
