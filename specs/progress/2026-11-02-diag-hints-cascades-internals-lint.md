First cheap items of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (§X3, §X4).

Wrong or leaking hints (§X4):
- `callback_arity_mismatch`: the curried rewrite (`fn a -> fn b -> …`) is offered only when the
  callee's parameter type is itself curried at least that deep (a fold's `b -> a -> b`); for
  `List.filter`'s `pred : a -> Bool` the hint is now a one-parameter function.
- `type_mismatch` notes: an occurs-check failure shows only its own note (it used to stack
  "Did you mean to pass this as a callback?" under it); a session or same-name note pre-empts the
  generic conversion hint.
- `refinement_violated`: a callback's synthetic parameter (`$cb_arg`) is "the argument passed to
  `f`"; the guard suggestion substitutes the real argument (`if x * 2 >= 0`, not `if _ >= 0`), and
  a closed argument (`f(-3)`) says it never satisfies the predicate instead of suggesting a guard.
- `cap_root_broad` on a type/extern/actor/interface says "this declaration uses", not "this
  function takes".
- Internals lint in `test/run_errors.ml`: a prose line naming a `$` binder, a generated `S_`
  state, a generated `_Msg` type, or `Cons`/`Nil` that the program never wrote fails the case.
  Known leaks (8, all generated actor/protocol names) are listed in
  `test/errors/internals-allowlist.txt`, which may only shrink.

Cascade suppression (§X3), `Errors.suppress_cascades`, applied in the driver after
`dedupe_cap_hints` so `--check` and `--check-json` agree:
- a `type_mismatch` on the span of a `callback_arity_mismatch`;
- an `unused_binding` for `x` when an `unbound_variable` error suggests `x`;
- `cap_grant` / `cap_root_broad` while a non-capability error exists;
- `cap_ceiling:X` when `cap_needs:X` reports the same missing `needs`.
Only diagnostics the user is shown can trigger a rule: the corpus caught a version where a hidden
stdlib-file error suppressed `cap_grant_21`'s only error and the program checked clean. A final
guard keeps the set unchanged if a rule would ever remove the last visible error.

Still open in those todos: poison types for follow-on errors, merging the capability reach-chain
HINT into its error, a check that a hint's fix fixes, and the LSP path (it does not run
`suppress_cascades` yet).
