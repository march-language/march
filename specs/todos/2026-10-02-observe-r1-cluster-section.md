`[P2]` **Observe R1.3: the `CLUSTER` section, published by March code and read by C.**

Split out of R1 of [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md)
(the rest of R1 landed: [`progress/2026-10-02-observe-r1-snapshot-verbs.md`](../progress/2026-10-02-observe-r1-snapshot-verbs.md)).

The observe thread cannot run March code, so cluster membership and cluster
names (which `ClusterNode` keeps in Vault tables, `stdlib/cluster_node.march`)
have to be pushed to C. The plan's shape, unchanged:

- A stdlib-only builtin `observe_publish_section : String -> String -> Unit`
  copies a JSON string into a C table (name -> owned string + `published_at_ms`,
  under a small mutex in `runtime/march_observe_snapshot.c`). Adding a builtin
  touches about nine sites (typecheck, eval, defun's builtin names, llvm_builtins'
  declare lists, the REPL finalizers, tests).
- A `CLUSTER` verb returns the stored string verbatim inside the envelope with
  its age, or `{"available":false}` before `ClusterNode.start`.
- `ClusterNode`'s ticker publishes `"cluster"` every SWIM period (1 s).
- `SNAPSHOT` includes every published section.

Acceptance: a two-node test where `CLUSTER` on each node lists both members
within 2 SWIM periods; the published string is valid JSON (the C side does
not validate it, so the stdlib publisher's output is tested).
