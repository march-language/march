# `[P2]` On Linux, every cluster session grows both nodes' memory by ~17 MB, never returned

Measured 2026-09-28 in `ci/Dockerfile.two-node` (ubuntu 24.04, arm64 native), RSS of
`test/two_node/protocol_evolve`'s two nodes sampled every second, on the tree of the D21
split PR (the growth is not from it: nothing it changed runs in the nodes, and
`protocol_evolve` is main's):

- Both nodes rise from ~10 MB to ~1.6 GB during the 14 s node-b drives sessions (one
  every 150 ms, ~93 sessions: ~17 MB per session per node), and level off when it stops.
  Growth starts before any hot deploy.
- The same scenario on macOS stays near 100 MB.
- `test/two_node/protocol_expand_contract` (24 s of driving, first version) reached
  3.8 GB per node and took CI's `two-node` runner down twice ("The runner has received a
  shutdown signal", exit 143); in the container with `--memory=8g` node-a was OOM-killed
  and node-b lost 10 sessions. The scenario now starts a session every 300 ms for 18 s.

Not yet known: which allocation (a green thread's stack committed page by page and never
released, a per-session buffer, a leaked endpoint/Vault per session; #673 fixed the
OfferActor/Vault leak for closed offers, and this tree includes it). Start with one
node pair, sessions in a loop, `/proc/<pid>/smaps` before and after, then
`MARCH_SANITIZE=address` (Linux container, see the ASAN recipe) for leaks.
