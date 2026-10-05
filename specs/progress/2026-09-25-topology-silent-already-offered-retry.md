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

## Fixed 2026-10-04

**Cause.** `Topology.open_role` swallowed every `AlreadyOffered` ("the previous
offer's name is released asynchronously: try again on the next tick without
reporting it"). That was right for one case and wrong for the other: a role
whose endpoint name another role on the same node holds can never be offered,
and was retried every tick in silence.

**Fix** (`stdlib/topology.march`, report-path option; `place`/topology.toml
are not rejected, since the name collision depends on the build's protocols
and fingerprints, which the topology check does not see). `open_role` now
tells the two apart by time since the node last retired an offer:

- `retire` stamps `rt` (node-wide) when it closes an offer. An `AlreadyOffered`
  within `MARCH_PLACEMENT_CONFLICT_GRACE_MS` (default 5000) of that is the
  closed offer's name still being released (a placement move, a capacity
  change, supervision, a deploy, or a conflicting holder that just closed): it
  is retried every tick, quietly, as before.
- Anything else is a conflict: reported once, naming the likely holder (this
  node's other open offers with the same role index; the refusal carries only
  the index), stored as `x:<role>` and written by `status_text` as
  `conflict <role> held-by <roles|unknown>` (so `write_status` puts it in
  MARCH_TOPOLOGY_STATUS; forge's report parser ignores unknown lines). It is
  retried only when this node's set of open offers changes, an offer closes,
  or a backoff doubling 1 s -> 60 s expires; when it finally opens, that is
  reported and the conflict line goes. A role no longer wanted here drops its
  conflict.

The refused offer's actor is still freed by `SessionNode.open_offer` (#673);
the backoff also means far fewer doomed opens.

**Test.** `test/session/topology_conflict.march` (fake ClusterOps whose
`register` refuses a held name and whose `unregister` is deferred, like the
node actor's): two roles share `Echo_Run.offer_Server`; asserts the report,
the status line, no per-evaluation retry, and that the role is offered once
the holder moves away (through the deferred-release transient). On main it
prints no report or conflict line and retries on all 6 evaluations.
