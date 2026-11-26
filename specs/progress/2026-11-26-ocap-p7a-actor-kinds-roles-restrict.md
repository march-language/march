# ocap phase 7a gap fixes: actor kinds in roles, topologies and `restrict`

Done 2026-11-26. Found by the post-merge review of phase 7a (PR #1321), which made
`Actor.Introspect` and `Actor.Debug` top-level capability kinds but left three places
looking only at the `IO` family.

- **Roles.** `Typecheck.check_role_needs` refused any non-IO grant, so
  `role R needs Actor.Introspect` was rejected with a message (the grant "is narrowed by
  the runner from `main`'s `Cap(IO)`") that no longer described the rule.
  `check_role_grants` compared only IO caps, so a role body reaching
  `Actor.introspect()` / `Actor.pid_from_int` / `Actor.debug()` passed the compile-time
  check and was refused only at run time. Both now use `Cap_lattice.is_authority` (the IO
  kinds and the actor kinds). An actor kind is not a body parameter
  (`Desugar_endpoints.grants_of` still keeps IO paths only); the body uses it through its
  own checked call. The `role_grant_exceeded` help and the `role_grant_too_wide` help say
  so (`add Actor.Introspect to the grant`, `add needs Actor.Introspect to main`).
  `--dump-role-authority` lists the actor kinds a role reaches. The hot-deploy manifest's
  role closures (`role_capability_closures`) stay IO-only: node policies grant IO.
- **Topologies.** `Desugar_topology.grants_of` keeps every kind; `param_grants_for` (IO
  only) sizes the body parameters. A role's actor-kind grant is checked against its pool's
  written caps, `Topology_gen.derive` reports the actor kinds a pool reaches (so a pool
  reaching one beyond its written caps is refused), and the generated `main` gets
  `needs IO, <kinds>` for the actor kinds its pools' roles are granted or written.
- **`restrict`.** `Scope_expr.is_cap_path` recognised only `IO` paths, so
  `restrict Actor.Introspect do ... end` was an unknown constructor. It now accepts every
  lattice kind; the literal check, the run-time frame and every runtime follow.

Tests (each written first and seen failing): `test_endpoints` (role reaching
`Actor.Introspect` refused; granted accepted; `Actor.Debug` grant wider than `main`),
`test_topology_flag` (granted role's generated `main`; grant beyond written caps; reach
beyond written caps), `test/cap_conformance/restrict_actor_kinds` (all five modes),
`test/errors/cap_restrict_5` (direct `Actor.debug()` inside `restrict Actor.Introspect`).

Also removed the unused `intro` parameters left in `test/native/actor_on_stop_deadline`
and `actor_on_stop_tree` by the 7a migration (`pid_from_int` is checked itself).

Found on the way: `specs/todos/2026-11-26-jit-user-fn-named-show-segfaults.md`.
