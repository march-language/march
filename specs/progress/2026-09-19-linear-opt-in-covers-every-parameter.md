# FIXED 2026-09-19: every parameter holding an opted-in type variable must be marked

## Cause

`linear x : a` puts `a` in `linear_ok_ids`, so callers may pass a linear value
for every parameter of type `a`. Only `x` was tracked in the body, so a second
`y : a` could be dropped or duplicated: `f(linear x : a, y : a) = (x, y, y)` turned
one `S1` into two.

## Fix

Option 1 from the filing. `check_opt_in_params`, run after a function's body
and return annotation are solved, rejects any parameter not declared `linear`/`affine` whose solved type
holds an opted-in type variable *as data*: `a`, `List(a)`, `(a, Int)` or a
record field. This is `holds_linear_ok_var`. The message names the parameter and
says to mark it `linear`.

- Run for top-level functions (`check_fn`) and for local `fn ... end` blocks
  (both `ELetFn` sites). Code review found the local form still accepted
  (`reject/t267_linear_opt_in_local_fn`): it is typed apart from top-level
  functions and never reaches `check_fn`.
- Checked after the body, so a variable the body unified with `a` counts too
  (`ys : List(b)` with `b := a`). The message prints the parameter's type as
  written and says it *holds* an opted-in variable, which stays accurate when
  that variable is only reached through unification.
- Not run for actor handler parameters, whose types come from the declared
  message type; an opted-in generic variable there has no known repro.
- A function-typed parameter (`f : a -> Int`) holds no `a` and is exempt, as is
  the phantom `Pid(a)`. `ap2(f : a -> Int, linear x : a)` stays valid.
- `@[trusted_linear]` functions are exempt: their bodies are reviewed, not
  checked.
- Option 2 (tracking such parameters linear implicitly) was not taken: it would
  change the meaning of existing code.

## Verification

- `reject/t263_linear_opt_in_second_param` (the filing's `f`) and
  `reject/t264_linear_opt_in_param_via_unify` (`List(b)` unified with `a`):
  both accepted by the pre-fix compiler, both rejected now.
  `accept/t266_linear_opt_in_every_param_marked` (both parameters marked, plus
  an exempt `k : a -> Int`) passes before and after.
- No stdlib function declares a `linear` parameter (LinearMap uses
  `@[trusted_linear]`), and the stdlib `--check` A/B was byte-identical.

---

The original filing follows.

# `[P2]` Linearity: a parameter sharing an opted-in type variable is not checked

Filed 2026-09-18 during the LinearMap work ([[2026-09-18-linear-map]]).

## Symptom

```march
always_linear type S1 = S1(Int)
fn f(linear x : a, y : a) : (a, a, a) do (x, y, y) end
...
let (p, q, r) = f(S1(1), S1(2))       -- accepted; S1(2) is now two
```

The opt-in is keyed on the type variable: `linear x : a` puts `a` in
`linear_ok_ids`, so every use of `f` at a linear `a` is accepted. But only `x` is
tracked linear in the body. `y` has the same type and is unrestricted there, so the
body may drop or duplicate it.

The same happens when the body unifies another variable with `a` (since 2026-09-18
the mark follows the link, which was needed for
[[2026-09-18-linear-ok-mark-lost-on-tyvar-link]]); it was already the case for two
parameters annotated with the same name.

## Fix options

1. After checking the body, reject a function where a linear-ok variable appears in
   the type of a parameter that was not declared `linear`/`affine` ("`y` has type `a`,
   which `x` opts in to linear values; mark `y` linear too").
2. Track every parameter whose type mentions a linear-ok variable as linear in the
   body. Changes the meaning of existing code; option 1 is the smaller step.

`@[trusted_linear(v)]` (stdlib LinearMap) is exempt by design: its bodies are
reviewed, not checked.

## Tests

Reject: `f` above. Accept: `fn f(linear x : a, linear y : a) : (a, a) do (x, y) end`.
