# Excluding `Nil` in a `match` now gives the other arm `len(xs) > 0`

**Filed:** 2026-08-02 · **Fixed:** 2026-08-03 — found by sweeping `forge refine` over all 112 stdlib modules
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

## How it was fixed

Two pieces in `lib/refinecheck/refine_check.ml`, and **neither does anything alone** —
verified by landing (a) first and measuring no change.

**(a) Arm-order exclusion.** `visit`'s `A.EMatch` case already pushed `is_Ctor(s)` for an
arm's own constructor pattern. It now also pushes `not (is_Ctor(s))` for every EARLIER arm
whose failure is decided purely by the tag. The branch walk became a `fold_left` carrying
the preceding arms.

`arm_excludes_tag` is where the soundness lives: an earlier arm licenses a conclusion only
if its pattern is a constructor with **irrefutable sub-patterns** and it carries **no
guard**. `Cons(0, _)` fails on `Cons(1, [])`, and `Nil when flag` fails when `flag` is
false — in both cases the tag still matched, so concluding anything would be unsound. All
three original guards on the positive narrowing carry over (bare-variable scrutinee,
registered constructor, scrutinee not rebound by the arm).

**(b) The measure link.** Rather than a datatype axiom, `path_resolve_tester` now
translates a tag test on a **list** directly onto the same memoized `len$x` symbol the goal
uses:

    is_Nil(xs)   ->  len$xs = 0
    is_Cons(xs)  ->  len$xs > 0

Both are exact for lists, and `measure_of_var` already asserts `len >= 0`, so
`not (len$xs = 0)` gives z3 `len$xs > 0` directly. No datatype declaration, no quantified
axiom, and — the point — the fact lands on the *same symbol* as the obligation instead of
on an unrelated opaque constant. Gated on the constructor belonging to the built-in `List`
sort, since a user ADT is free to declare its own `Nil` and a `len` claim about that would
be invented rather than derived.

## Result

`stdlib/stats.march` went from **0 proved / 1 skipped** to **4 proved / 1 skipped**:
`mean_safe`, `variance_safe`, `min_safe` and `max_safe` all discharge now.

The remaining skip is `std_dev_safe`, and it is correct:

```march
match xs do
Nil -> Err(…)
Cons(_, Nil) -> Err("need at least 2 elements")
_ -> Ok(std_dev(xs))
end
```

the second arm has a refutable sub-pattern, so reaching the third genuinely does not
exclude `Cons` — and `std_dev` needs two elements, not one. The checker declines rather
than inventing `len > 1`. That is `arm_excludes_tag` doing its job.

Downstream, `forge refine --all` over `stats.march` now returns **no suggestions at all**:
the debt is gone, so `contradicts_handled_case` has nothing to suppress. The guard stays —
it is cheap and covers shapes this does not reach — but it is now unreachable for the case
that motivated it.

False positives: **0** refinement violations across all 112 stdlib modules.

## Original acceptance criteria

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
