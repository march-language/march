`[P3]` The formatter drops an actor's attributes, including `@[stdlib_internal]` (2026-11-13)

Found by the ocap phase 2b final re-review (m3,
`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-rereview.md`). The `DActor` arm of
`lib/format/format.ml` prints no attributes: `@[remote]`, `@[compat:...]` and
`@[invariant(...)]` were already lost (the AST keeps them only as `actor_remote`,
`actor_compat`, `actor_invariant`), and now `@[stdlib_internal]` (`actor_internal`), which
is a gate: formatting `stdlib/node_queue.march` or `stdlib/cluster_node.march` would
silently reopen `NodeQueue.Writer`, `ClusterNode.CtlWriter` and
`ClusterNode.ClusterNodeActor` to user code. Nothing in CI formats the stdlib, so it is
latent.

Expected: the formatter prints the attributes it can reconstruct from those fields, and a
round-trip test over an attributed actor pins it.
