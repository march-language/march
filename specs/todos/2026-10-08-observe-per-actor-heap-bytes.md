# Per-actor heap bytes in the observe tier

`TOP stack` ranks by committed stack, the only per-actor memory the runtime can
attribute today. Heap bytes owned by an actor are not tracked (shared RC heap, no
owner per object). Options and costs are in
`specs/progress/2026-10-08-observe-top-actors.md`: allocation-time counting
(hot-path cost, wrong for shared values; benchmark on `bench/binary_trees.march`
and `bench/list_ops.march`) or an on-demand state walk for the top N in the debug
tier next to `STATE`. Then `TOP heap` / `forge top --sort heap`.
