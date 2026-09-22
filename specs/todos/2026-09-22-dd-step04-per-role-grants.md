# `[P2]` Distributed deploys, build step 4: per-role grants as values, authority report, scripted and chaos peers

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), sections 2, 7.1, 7.2, II.2, D2, D34-D36.

**What.** `role R needs ...` in protocols (`ProtoRoleNeeds`, not part of the
fingerprint); generated body types carry one `Cap(P)` per declared cap;
`check_role_grants` runs `Cap_rows.solve` from each role root and compares with
`cap_subsumes`, reporting with `cap_reach_chain`; role grant subset of `main`'s grant.
`--dump-role-authority` report. `ClusterHandle` becomes `Cap(Cluster.Live)` with an
`Ops` dictionary (D35). The generator emits a scripted peer and a chaos peer per role
(D36). A new builtin goes in both capability tables (pinned equal by
`test/test_cap_attrib_agreement.ml`).

**Acceptance.** A role body that reaches a capability outside its `needs` fails with
the chain from body to the capability; a grant wider than `main`'s fails; the scripted
and chaos peers drive an existing two-role protocol in a unit test with no sockets.
