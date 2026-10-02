`[P2]` A hot patch of a topology role body is refused by the node policy (`ERR cap_policy Session.Live`)

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
