# Excluding `Nil` in a `match` does not give the other arm `len(xs) > 0`

**Filed:** 2026-08-02 — found by sweeping `forge refine` over all 112 stdlib modules
(`specs/progress/2026-08-02-forge-refine-precondition-suggestion.md`).

## Repro

`stdlib/stats.march`:

```march
fn mean_safe(xs : List(Float)) : Result(Float, String) do
  match xs do
  Nil -> Err("Stats.mean_safe: empty list")
  _   -> Ok(mean(xs))          -- `mean` needs a non-empty list
  end
end
```

The `_` arm is reachable only when `xs` is not `Nil`, so `len(xs) > 0` holds there.
The checker does not derive that, so the call to `mean` records an unproven
precondition. `--refine-report` on `stats.march` shows the skip; the same shape occurs
in `variance_safe`, `std_dev_safe`, `min_safe` and `max_safe`.

## Why this one is worth prioritising

It is the shape *every* "safe wrapper" in a standard library has — match on the empty
case, return `Err`/`None`, do the real work in the other arm. As long as the fact does
not propagate, the entire safe-wrapper idiom carries permanent unprovable debt, and any
tool reading the ledger sees a function that looks under-specified when it is in fact
exactly right.

Concretely it already caused a wrong recommendation: `forge refine` proposed
`xs : {List(Float) | len(_) > 0}` for `mean_safe` — provably debt-discharging, and
semantically the opposite of what the function is for. `Precond_infer` now suppresses
that class of suggestion (`contradicts_handled_case`), but that is a guard around the
symptom. Fixing the propagation removes the debt, and then there is nothing to suppress.

## Where to look

`lib/refinecheck/refine_check.ml` — the path-condition accumulation in `visit`'s
`A.EMatch` case. Branch GUARDS already contribute facts (`branch_guard` is pushed onto
`path`); the branch PATTERN does not. What is needed is: when a constructor pattern is
excluded by earlier arms, the remaining arms may assume its negation, and for a list
scrutinee `not (is_Nil xs)` must connect to the `len` measure as `len(xs) > 0`.

The ADT-tester machinery to express `is_Nil` already exists (constructor-tag
refinements, `resolve_tester`); the missing pieces are (a) emitting the arm-order
negation as a path fact and (b) the `is_Nil(xs) <-> len(xs) = 0` axiom linking the
tester to the measure.

## Acceptance

- `stats.march` reports 0 unproven preconditions in `mean_safe` / `min_safe` /
  `max_safe` / `variance_safe`.
- REJECT witness: a function that calls `mean(xs)` with **no** `Nil` arm must still
  record an unproven obligation — otherwise the fix is laundering the goal rather than
  propagating a fact.
- `forge refine --all` over the stdlib no longer needs `contradicts_handled_case` to
  stay quiet on those five functions (the guard stays, but should become unreachable
  for them).

## Related

- `specs/todos/2026-08-02-caller-refinement-dropped-when-it-mentions-another-name.md`
  — a caller promise that is derived and then DROPPED, rather than never derived.
