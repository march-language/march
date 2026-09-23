# Nested modules get Check 1's own-proof-cap exemption

Check 1 in `check_module_needs` (lib/typecheck/typecheck_caps.ml) lets the
module that declares `proof cap X` use `Cap(M.X)` without `needs M.X`. For a
nested `DMod`, `check_decl` (lib/typecheck/typecheck.ml, `DMod` arm) called
`check_module_needs` with the OUTER `env`. The module's own `DProofCap`s are only
registered into `inner_env`, so the outer env never held them and the exemption
never matched: every `Cap(M.X)` in a nested `M` drew a false "`Cap(M.X)` used in
module `M` but `M.X` is not declared in `needs`". The entry module was fine
because `check_module_core` passes it `final_env`.

**Fix:** the nested call passes `{ env with proof_caps = inner_env.proof_caps }`.
Only `proof_caps` is taken from the inner env. Every other field Check 1/1b/2
read is unchanged.

## How it surfaced

#591's whole-stdlib ratchet (`check_stdlib_like_cli`) checks every stdlib file as
a nested module under a `StdlibBaseline` wrapper. All 9 of `session.march`'s rows
(`Cap(Session.Live)`) were this bug, and #594 added 7 more for `actor.march`
(`Cap(Actor.Introspect)`), which #595 worked around with `needs Actor.Introspect`.
`march --check stdlib/session.march` never showed them because there `Session` is
the entry module. #595 diagnosed it as the wrapper prefixing the cap path
(`StdlibBaseline.Actor.Introspect`). A debug print of `env.proof_caps` at Check 1
disproved that: the caps register as `Actor.Introspect` / `Session.Live`, and
`Actor`'s check saw an EMPTY list. The bug hit users too: a user file with
`mod App do mod Vault do proof cap Key … fn f(k : Cap(Vault.Key)) …` got the
same false error from `march --check`.

## Changes

- `session.march` row dropped from `stdlib_known_internal_errors` (9 → 0).
- `needs Actor.Introspect` removed from `stdlib/actor.march`: it was only the
  workaround, and `actor.march` stays at its 2 pre-existing (`Pid` arity) errors
  without it. Leaving it out means both of stdlib's proof-cap-declaring modules
  exercise the exemption, so the ratchet catches a regression in two files.
- New typecheck tests: `test_nested_module_own_proof_cap_needs_no_needs`, and
  `test_sibling_module_proof_cap_still_needs_needs` to check the exemption is
  not overbroad. Both the first test and the ratchet go RED with the old call
  restored.
- `2026-09-22-stdlib-distributed-module-errors.md` / `…-internal-type-errors.md`
  no longer list session's 9.
