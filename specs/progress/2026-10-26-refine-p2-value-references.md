Refinements: P2 classifies every name a body references, not only call heads (a false proof on main)

Found by the independent soundness review of the container-gap batch (branch
`claude/refine-container-gaps`). The hole predates the batch: it gives a false proof on
main with no `Map` involved. The batch's opaque-container rule
(`2026-10-26-map-element-flow.md`) made it reachable through `Map` as well.

## Root cause

P2 (`Refine_param.parametric_safe`, computed by `compute_safety`) decides that a
generic function's body cannot create a value of its type variable. It collected only
the named call heads of a body (`call_heads`: `EApp (EVar n, …)`) and classified each
one. A name used any other way was never looked at: passed as an argument, `let`-bound,
stored in a record or tuple. A local name was "harmless" because its definition was
assumed to be covered, but a `let`'s right-hand side was only walked for call heads.
So with an interface method `fn dflt : Int -> t` whose `Int` impl returns `0 - 5`:

```march
fn apply1(f : Int -> b, n : Int) : b do f(n) end
fn sneak(xs : List(v), _d : v) : List(v) do Cons(apply1(dflt, 1), xs) end
fn go(xs : List({Int | _ > 0})) : Int do list_pos(sneak(xs, 1)) end   -- was proved; runs with -5
```

`sneak`'s only call head is `apply1` (generic, safe; `Cons` is a constructor), so `sneak` counted
as parametric, and the demand was discharged against `xs` alone.

## Fix

`lib/refinecheck/refine_param.ml`: `call_heads` became `value_refs`, which collects
EVERY `EVar` in the body and guard (call heads included), and `compute_safety` classifies
each with the unchanged `classify_head`:
- a top-level function: depends on that function's own safety;
- an extern, a creating builtin, or an interface method returning a type variable:
  taints the body;
- an unresolved name: taints it, as before.

A local (`expr_binders`) is still `Ok`. That is now sound because its definition is part
of the same walk: `let g = dflt` records `dflt`. A parameter's value comes from the
caller, and the source analysis already constrains it. A record or tuple holding a
tainting function taints the body through the same rule, since the field's expression is
walked.

## Tests

New group `p2-value-refs` in `test/test_refinecheck.ml` (12 cases; real `list`, `option`,
`map` stdlib). RED with `refine_param.ml` at the parent commit:
`7 failures! in 0.233s. 12 tests run.` Each of the 7 is a false proof on the base:
"recorded" passes and "not proved" fails.

| # | Shape (`dflt` the interface method above) | Base | Fixed |
|---|---|---|---|
| 0 | `let g = dflt` then `Map.insert(m, "z", g(1), …)` (review `p2/b_alias`) | proved | not proved |
| 1 | `let r = {g: dflt}` then `r.g(1)` (`p2/g_record`) | proved | not proved |
| 2 | `Map.map_values(m, dflt_of)`, `dflt_of` calling `dflt` (`p2/e_map_values_val`) | proved | not proved |
| 3 | `Map.insert(m, "z", apply1(dflt, 1), …)` (`p2_mapval`) | proved | not proved |
| 4 | `Cons(apply1(dflt, 1), xs)` into `List({Int \| _ > 0})` (`p2_listval`; proved on main too) | proved | not proved |
| 5 | scalar demand: `pick(o, d) : a` returning `apply1(dflt, 1)` (review `p1_ifaceval`) | proved | not proved |
| 6 | a tuple `(dflt, 0)` destructured, then `g(1)` | proved | not proved |
| 7-11 | controls: `List.map(xs, f)` passing the callback parameter on; `let g = f`; `Map.map_values(m, f)` in a generic wrapper; a concrete top-level function as a value (`List.map(ys, len_of)`); `Map.insert(m, "z", Map.get_or(m, "a", d, …), …)` | proved | proved |

The review's own files (`reviewC/p2/*.march`, `p2_*.march`, `p1_ifaceval.march`), swept
with `--check --refine-report-sites`:
- every shape that was proved is now a `parametric-source-unproved` skip;
- `a_direct`, `c_qualified_mod`, `d_map_values`, `f_pipe`, `h_assume_keys` and
  `i_assume_plain` were already skips and are unchanged.

## Verification

- **Refine oracle.** Baseline at `63379fa9b` (the batch's last commit), check after:
  `REFINEMENT DIAGNOSTICS IDENTICAL (8738 lines over 552 fixtures)`. No stdlib or
  `test/native` proof was lost.
  - That the corpus can see a P2 change: with `parametric_safe` forced to `false`,
    `stdlib/list.march` (an oracle fixture) drops from 36 to 28 proved in user code,
    with 8 skipped (user + stdlib: 46 skipped, against 36).
  - Restored: 36 proved, 0 skipped; user + stdlib 110 proved, 36 skipped (the CI
    ratchet ceiling is 42).
- `test_refinecheck` with the fix: `Test Successful … 1807 tests run` before the scalar
  case was added. No existing group lost a proof, including the stdlib sweep's Queue
  rows, fold invariants and abstract refinements, all of which route through P2.
- Full suite: see the batch report.

## Rulings

- Ruling: classify every referenced name with the existing `classify_head`, rather
  than a separate value-position classifier. Why: a function's safety does not depend
  on how it is reached. A value-position use can be called later through any alias, so
  the call-head classification is exactly the right question. Cost if wrong: a lost proof
  for a body that mentions a creating function without ever producing a `v` from it
  (none in the corpus).
- Ruling: an unresolved name keeps tainting, now in value position too. This covers
  module-level constants and anything `resolve_key` does not know. Why: a typed global
  can be a `v`, and the oracle shows nothing in the corpus depends on it. Cost if wrong:
  a lost proof.
