`[P2]` Object capabilities phase 7: `mock`; retire `Cap(IO.*)`, `cap_narrow` and `with_cap` (2026-11-22)

Filed by the 2026-11-22 todo sweep: phase 7 of `specs/2026-11-10-object-capability-design.md`
(§17, §21) had no todo and no plan. Its prerequisite, phase 4 (run-time authority), is on main.

What it is: `mock` replaces `with_cap` for tests; `fn main(c : Cap(IO.X))` goes away in favour
of `needs` on `main`; `cap_narrow` is removed; a choreography `role R needs ...` becomes a
limit around the role's body with no generated `Cap` parameters; `Session.attach`,
`ClusterNode.attach` and `ClusterNode.start` become checked operations; `Actor.Introspect`
becomes a capability kind.

Not started (checked on `40f901bab`): no `mock` keyword in `lib/lexer/lexer.mll`, `cap_narrow`
is still in `lib/typecheck/typecheck_builtins.ml`, and `fn main(c : Cap(...))` is accepted.

Closes with it: `2026-11-05-direct-runner-root-cap.md` (`run_<Role>` / `host_<Role>` taking
`Cap(IO)`). Reshapes: `2026-11-05-topology-role-grant-unenforced.md` and the per-role grants
bullet of `2026-11-09-host-scope-phase-2.md`. After it, revise
`specs/lang/capability-threat-model.md` and the capability pillar's claim.

Breaking for every program with a `Cap(IO.*)` parameter, so it lands before the 1.0 freeze.
