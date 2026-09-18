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
