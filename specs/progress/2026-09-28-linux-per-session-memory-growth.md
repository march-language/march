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

## Fixed 2026-10-13 (already flat on main; closed with a re-measurement and a guard)

**Measured on origin/main 3d2925fce**, `ci/Dockerfile.two-node`-equivalent container
(`march-ci-ubuntu-step6b`, ubuntu arm64, 8 GB cap), both nodes' RSS sampled every second
through the whole scenario: `protocol_evolve` peaks at ~65 MB per node (node-a 66, node-b
67) and stays there; `protocol_expand_contract` peaks at ~65 MB. macOS, same tree: ~63 MB.

**Which change fixed it**, bisected on main's first-parent history in the same container,
`protocol_evolve` peak RSS per node:

| main commit | what it is | node-a / node-b |
|---|---|---|
| 9ee1f648b (10-04, before #785) | | 585 / 573 MB, and a session refused |
| 78c124921 (#785) | Vault releases displaced values at their type; every session's 13 SessionNode tables closed and freed | ~240 / ~235 MB |
| 7b1db5973 (#812) | session-leak follow-up (Perceus/borrow) | ~185 / ~240 MB |
| 91f5e00e4 (#814) | `--hot-reload` builds leaked every capture-free lambda they called | ~80 / ~85 MB |
| 3d2925fce (today) | | ~65 / ~66 MB |

So the ~17 MB per session was two leaks: the per-session Vault tables (and everything a
Vault overwrite displaced, which a session's tables hold plenty of), fixed by #785, and
the hot-reload lambda-cell leak, fixed by #814 (both scenario nodes are `--hot-reload`
builds; plain-build scenarios such as `session_churn` were never as bad: ~50 MB on the
pre-#814 tree too). Why macOS stayed near 100 MB with the same leaks was not pursued:
both fixes are in, and the Linux number now matches macOS.

Not the cause: green-thread stacks (single-node in-process session probe, 200 sessions:
44 MB flat on Linux, 14 MB on macOS, ~16 heap objects left per session either way).

**Guard:** `test/two_node/protocol_evolve/scenario.sh` now fails when either node holds
more than 200 MB of RSS after its sessions (read with `ps` once node-b prints its
summary). RED on the pre-#785 tree (`node-a holds 269 MB of RSS after its sessions`),
GREEN on main on Linux and macOS.

A separate per-session cost found while re-measuring (the registry answering every pushed
name change with its whole contents) is
[2026-10-13-registry-push-answered-with-full-dump.md](2026-10-13-registry-push-answered-with-full-dump.md).
