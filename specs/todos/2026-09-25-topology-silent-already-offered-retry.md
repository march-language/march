# `[P3]` Topology silently retries `AlreadyOffered` forever when two roles share an endpoint

Filed 2026-09-25 while diagnosing the `topology_place` CI failure on PR #646.

Two roles placed on one node that serve the same protocol through the same
`offer_*` function want the same registry name: `SessionNode.offer_with` builds the
name from protocol + role + node id, not from the Topology role name. The second
offer gets `AlreadyOffered`. Topology's reconcile loop retries that on every tick and
never reports it. So a role can be missing from `Topology.offered` forever with no
diagnostic. Whichever role wins also depends on timing: `ClusterNode.register`
checks the names Vault straight away, but the node actor binds the name later, in
its own turn. That race made `test/native/topology_place` flaky (~5% under load on
main; its fixture now gives each role its own protocol).

Options:
- Reject it at `Topology.place` / topology.toml check time: two roles on one node
  whose offers resolve to the same endpoint name are a configuration error.
- Or report it: print once per role (like the "its offer or hosting actor died"
  line) when an offer fails with `AlreadyOffered`, and surface it in
  `write_status`.

A regression test should place two roles sharing one offer function and assert the
diagnostic, not the timing.
