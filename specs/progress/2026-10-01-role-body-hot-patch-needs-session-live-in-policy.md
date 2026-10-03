`[P2]` A hot patch of a topology role body is refused by the node policy (`ERR cap_policy Session.Live`) — FIXED 2026-10-02

Found 2026-10-01 by forge/test/test_deploy_e2e.ml, once the hot-reload boundary
fixes (specs/progress/2026-10-01-hcr-topology-app-functions-no-dispatch-slots.md)
made an edit inside `Back.serve_one`'s closure plan as a hot patch instead of
a restart. forge (not the compiler) side: forge/lib/host_init.ml.

`forge host init` writes a pool's node policy (`MARCH_DEPLOY_POLICY`) from the
pool's written `caps` (else its derived ones, both IO caps only, D22) plus the
topology runner's caps (`runner_caps`). The node's per-function admission gate
(ACTIVATE4+, each activated function's own `caps=` from the manifest) checks
EVERY cap the function holds, and a role body holds the session it is handed:
`Back.serve_one`'s manifest line reads `caps=IO.Console,Session.Live`. So with
examples/topology_app's `caps = ["IO.Console"]`:

```
==> pool back: hot patch
  FAILED Back.serve_one: ERR cap_policy Session.Live — deploy rejected by node capability policy
```

A role body cannot be hot patched at all unless the user writes `Session.Live`
into the pool's `caps` (what the e2e test now does in its scratch copy, with a
pointer here). Before 2026-10-01 nobody hit it: a role body edit planned a
restart (renumbered generated names, no slot for closures), and under the
entry-module prefix a top-level role body had no slot.

Options: grant the live-handle caps a pool's served roles are handed by
construction (`Session.Live`, and `ClusterNode.Live` for a hook that takes the
node) the way `runner_caps` grants the runner's, from the manifest's ROLE
lines; or have the gate compare only the IO caps a policy speaks about. Either
is a security decision for the deploy plane's owners: the policy must still
refuse a patch that reaches an IO cap the pool was not written with.

Acceptance: test_deploy_e2e passes without its `Session.Live` grant.

## Fixed 2026-10-02

Two rules in the node's admission gate (runtime/march_reload.c), and the
policy `forge host init` writes (forge/lib/host_init.ml, `policy_text`).

**1. The policy polices IO capabilities only** (`check_cap_policy`). A cap
outside the IO lattice (not `IO` or `IO.…`) is not checked against
`MARCH_DEPLOY_POLICY`, in a function's own caps or in a role closure. Such a
cap is a proof capability (`Session.Live`, `ClusterNode.Live`,
`Actor.Introspect`, a user's `Db.Migrated`) or an FFI root, and carries no IO
authority of its own:

- D31 / II.1: proof caps already have "only the declaring module mints"
  semantics (Check 6), minted from a `Cap(IO)` that is charged to the minter,
  so the type system, not the node, decides who holds one.
- Section 2 and D1: a session's dictionary is the transport the runner built;
  the IO it performs is charged to its creator (the runner, charged to
  `main`), not to the role body it is handed to.
- II.2 / D34: the compiler's own grant checks (`check_main_grant`,
  `check_role_grants`) skip non-IO caps for the same reason; a pool's `caps`
  are IO caps (D22), so a policy generated from them could never name one.
- Calling foreign code is charged `IO.Foreign`, which stays policed.

This is the option the todo called "have the gate compare only the IO caps a
policy speaks about". The other option, writing `Session.Live` (and
`ClusterNode.Live`, and any user proof cap) into the generated policy, would
leave every existing hand-written or generated policy refusing role bodies,
and would make proof caps look like authority a policy grants. Neither rule
widens a node's IO authority: an IO cap outside the policy is refused
whatever proof caps stand beside it.

**2. The policy bounds the closures of the roles the node serves.** Found by
the new two-node scenario: with a `[control]` section every manifest carries
`ROLE Ctl.Agent` and `ROLE Ctl.Control` (the control plane's generated
protocol, spliced into every node's `main`), and the back pool's policy
refused every hot patch with `ERR role_cap_policy Ctl.Agent IO.FileRead`. The
same held for a shared build whose other pool serves a role with wider caps.
`policy_text` now ends with a `serves <Proto.Role> ...` line (bare `serves`
for a pool that serves nothing), and the gate checks only those roles'
closures (`policy_bounds_role`); a function's own caps are still checked
against every cap line. A role the node does not serve is another pool's, or
the control plane's, charged to the generated `main` as the runner's own caps
are (section 2), and granting its closure in this pool's policy instead would
widen what any patch on the node may do. A policy with no `serves` line (a
hand-written one, or one written before this fix) bounds every role, as
before; an older server reads the line as a cap path no capability equals.

Both paths: the control plane's Agent relays a release's `ACTIVATE` lines
through `march_reload_request`, the socket's own dispatch, so one gate serves
`forge deploy hot` over ssh and a release through the control plane.

### Tests

- test/two_node/hcr_role_policy: a topology app on two nodes under the policy
  `Host_init.policy_text` generates (`hcr_deploy policy`), with `[control]`.
  Version 2 of the role body `Back.serve_one` goes over the reload socket
  (what `forge deploy hot` sends), version 3 as a release through the control
  plane; front observes each answer change, and both versions add a Vault
  mark the base build's code set. Version 4 widens a back-pool
  function no role reaches to `IO.FileWrite` (its own cap) under the operator's `--grant-cap`: the node
  refuses it (`ERR cap_policy IO.FileWrite`), the batch rolls back, and front
  never sees its answer. Before rule 1, version 2 was refused with
  `ERR cap_policy Session.Live`; before rule 2, with `ERR role_cap_policy
  Ctl.Agent IO.FileRead`.
- test/test_reload_activate4.c, policy mode (`test_reload_policy.txt` now has
  a `serves` line): proof caps beside IO caps admitted (ACTIVATE4, ACTIVATE6,
  and in process, the Agent's path); an IO cap outside the policy (`IO.Process`,
  an unknown `IO.Bogus`, the `IO` root) refused beside them; a served role's
  closure widened to `IO.FileWrite` beside `Session.Live` is
  `ERR role_cap_policy Echo.Server IO.FileWrite`; an unserved `Ctl.Agent` is
  admitted. New mode `policy-all` (`test_reload_policy_all.txt`, no `serves`
  line): `Ctl.Agent` is bounded and refused.
- forge/test/test_host_init.ml: the `serves` line, including a pool that
  serves nothing.
- forge/test/test_deploy_e2e.ml no longer writes `Session.Live` into the back
  pool's caps.

The scenario does not reach `ERR role_cap_policy` end to end: a role body's
grant caps are its parameters (D34), so a closure widened beyond the policy
usually widens the body's own caps too, and the own-caps gate (or the
compiler's grant check) refuses it first. The C harness pins it.
