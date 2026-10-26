# Two-argument lambdas may capture caller names

Landed 2026-10-26. The n-ary half of R2
(`specs/progress/2026-10-24-refine-relational-filter-capture.md`, whose last ruling left it
declined). No todo was filed for it. Branch `claude/refine-call-lambda-gaps`.

```march
fn go(a : Assoc(Int, Int), n : {Int | _ >= 10}) : Int do
  need_far(filt(a, fn (k, v) -> v > k + n))   -- need_far : Assoc({x : Int | true}, {y : Int | y > x + 5})
end
```

Before: `abstract-refinement-uninstantiated`. Now: proved.

## Root cause

`instantiate_abstract_n` (`lib/refinecheck/refine_check.ml`) required the lambda's reading
to mention nothing but its own parameters. The reason was real: `abstract_flow_n` and
`abstract_param_entry_n` substitute the callee's formals into the instantiated entry
(`instantiate_entry`, review C4) AFTER the abstract is applied, so a caller name `n` in the
reading would be read as the callee's formal `n` (the C4 capture), and any other caller name
made the entry `Unusable` ("mentions a name that is not a parameter").

## Fix (`lib/refinecheck/refine_check.ml` only)

- `instantiate_abstract_n ?stable`: a name of the reading other than the parameters is
  admitted when it is written free in the lambda as written and `stable` holds (R2's rule;
  both call sites pass `stable_local ctx`). It is renamed to a placeholder `$cap$n`, which
  no formal, binder or March variable can spell. A lambda passed by name captures nothing.
- `instantiate_entry_caps` (replaces `instantiate_entry` at both call sites): each
  placeholder in the entry is one more formal whose actual is the caller's own variable, so
  formals and captures are substituted together, simultaneously, and `instantiate_entry`'s
  existing binder renaming (a slot binder to `_`; a relation's binders to `$s<j>` when an
  actual mentions them) keeps a caller `y` apart from a slot binder `y`. Declined when the
  formals and actuals do not line up one to one, or when a placeholder survives.

The produced entry is relational over the caller's scope; `entry_implies` already reads a
relation over caller names (as for a callee formal read at a caller's actual), with their
scope facts.

## Tests (group `gap-nary-capture`, 6 cases)

RED on base (`bc1fef6f1`, lib reverted, tests kept): cases 0, 1, 2, 3, 5 fail (first failing assertion in the base column).

| # | case | base | now |
|---|---|---|---|
| 0 | `fn (k, v) -> v > k + n`, `n >= 10`; curried; `let n = 6` | uncurried `[uninstantiated]` | proved ×3 |
| 1 | too weak `n >= 0`; `n` unrefined | `n >= 0`: `[uninstantiated]` | `too-weak`; not proved |
| 2 | C4: `filtn(a, 1000, …n…)`, caller `n >= 0`; `filtn(a, 0, …n…)`, caller `n >= 10` | second: `[uninstantiated]` (first a control) | not proved / proved |
| 3 | slot binder `y`: caller `y : Int`; control `y > 1000` | `y : Int`: `[uninstantiated]` | `solver-undecided` / proved |
| 4 | rebound: `let f = …n…; let n = 0`; `let n = 0 - 100`; a `let` inside the lambda | (control) | not proved ×3 |
| 5 | parameter slot `need_rel(a, fn (k, v) -> v > k + n)`, `n <= 20` / `<= 30`; C4 on `need_reln(a, 0, …)` with caller `n` and `m` | `n <= 20`: `[]` under `a` (the decline is recorded under the callee) | proved / not proved / `[proved; violated]` both |

Perturbations: reading the capture as the bare name (no placeholder) turns case 2's C4
control RED (proved, `n` read as `filtn`'s 1000) and case 0 to uninstantiated; renaming the
placeholders back without `instantiate_entry` turns case 3's `y` control into proved
(`y > y`), checked through a probe, and case 5's C4 row to `[violated; violated]`.

Edited existing tests, deliberately (each pinned the decline on an UNCONSTRAINED capture,
which now instantiates and is a skip for the honest reason): `abstract-multiarg` "capture
(m7)" → `solver-undecided`, plus a `now >= 0` row that proves; `abstract-map` m7 →
`solver-undecided`, plus m7b (`now >= 0`) proved.

## Oracle

Identical to the pre-edit baseline (8750 lines over 552 fixtures), in the combined run
with all three gaps of the branch; the red perturbation is in the map-filter note. No corpus fixture passes a capturing two-argument lambda.

## Rulings

- Ruling: "stable" is R2's `List.mem n ctx.locals` — March has no mutable binding, and the
  `lets` channel retires a let-bound lambda whose capture is rebound — cost if wrong: a
  capture read at a later binding; none of the rebinding controls proves.
- Ruling: captures ride as extra formals of `instantiate_entry`, not as a separate pass —
  one simultaneous substitution and one binder-renaming rule for formals and captures alike
  — cost if wrong: none found; the two perturbations show each half is load-bearing.
- Ruling: a call whose actuals do not line up with the formals declines a capture — cost if
  wrong: a lost proof.
- Ruling: a module-level name stays declined (not in `ctx.locals`), as at arity 1 — cost if
  wrong: a lost proof.
