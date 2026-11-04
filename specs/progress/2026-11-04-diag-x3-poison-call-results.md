Closes §X3 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (logged 2026-11-02 as `[P2]` one root
cause, one report) with its poison part (the suppression table,
merging and the multi-error review landed 2026-11-02/03,
`specs/progress/2026-11-03-diag-x3-x4-finish-x7-traces.md`).

**Cascade.** A call whose argument fails its type check could leave a type variable of the callee
bound to the wrong thing, and every later use of the result reported again. `List.append([1, 2],
["a"])` binds `a` to `Int` from the first list. `["a"]` then fails, but the result was still
`List(Int)`, so `List.map(xs, fn x -> x ++ "!")` reported a second mismatch on `x`.
`Option.unwrap_or(Some(1), "none")` did the same for the `p ++ "!"` after it.

**Poison.** `infer_app` (`lib/typecheck/typecheck.ml`) collects the parameter's type variables, bound
or not, before checking each argument. If the check adds a `type_mismatch` and the call's result
shares one of those variables, the result is `TError`, which unifies with everything and reports
nothing. The remaining arguments are still checked, for their own errors.

**What is not poisoned, on purpose.**
- A result the callee declares outright, with no variable shared with the failed parameter, is
  kept: `parse(n)` with `parse : String -> Option(Int)` still gives a `match` over it its
  exhaustiveness check, and a field of a `Cfg` result its own type check. A first version that
  poisoned every call with a failed argument hid those independent errors. Rust and TypeScript
  keep declared results the same way.
- Only a `type_mismatch` counts. A capability, linearity or visibility error inside an argument says
  nothing about the result's type. Poisoning on those hid `cap_root_broad_2`'s `Cap(IO)` mismatch
  (behind a `stdlib_internal` error) and `linear_never_used_19`'s never-used binder.
- `x ++ "no"` in an `Int` function keeps its two errors (`x` is not a `String`, and `++`'s `String`
  result is not the `Int` the function returns): `++` declares both, so they are independent.

Linearity and exhaustiveness skip poisoned bindings without further work: a `TError` binder is not
linear, and a `TError` scrutinee has no constructor universe.

Corpus: `test/errors/type_mismatch_39` (`List.append`), `_40` (`Option.unwrap_or`), `_41` (the
declared-result guard, two independent errors). No existing case changed: the 41 remaining
multi-error cases were already judged independent by the 2026-11-03 review.

Types oracle against main: see the PR (accepted programs identical by construction, since no
argument of a well-typed program fails its check).

Left for §F3 (`specs/todos/2026-11-02-diag-choreography-session-messages.md`): the out-of-order
role step's `S_end` follow-ons in `linear_used_twice_6`.
