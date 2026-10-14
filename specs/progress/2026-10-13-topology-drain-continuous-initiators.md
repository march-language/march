# `[P1]` A topology node under continuous session traffic never drains on SIGTERM

**Filed and fixed** 2026-10-13, found with the choreo-demo app
(github.com/Ch4s3/choreo-demo): three pools (warehouse serves `Order.Stock`, books
serves `Order.Ledger`, shop's hook starts 8 tasks that loop `Order_Run.initiate_Shop`
back to back), run with `forge run --processes --hot-reload`. With traffic still
flowing, Ctrl-C did not stop it: shop-1 logged `draining`, then its soft and hard
deadlines with 8 sessions still running; books-1 later logged a soft deadline with 6
sessions running; minutes after the signal two processes were still up and ignored
SIGTERM, and only SIGKILL ended them. With traffic that stopped before Ctrl-C, all
three drained and exited 0 within 2 s.

## Causes (three, plus how forge made them add up)

1. **A draining node kept starting sessions.** `Topology.drain` closed the node's
   offers, but nothing stopped the node's own tasks from calling `initiate`. Measured
   with prints in `SessionNode.initiate`: in a 4 s drain the 8 traffic loops started
   ~430 new sessions, every one of which completed `Ok`. `drain_wait` waits for
   `Topology.unfinished` (offer sessions + `SessionNode.initiated`) to reach 0, and
   with 8 loops it was always 8, so every drain ran to its hard deadline and exited 1.
2. **A session whose initiator's node died while it formed held its offer's slot for
   30 s.** When shop exits (hard deadline or SIGKILL), the sessions books and
   warehouse had accepted but not yet formed wait in `find_peers` (for the
   initiator's endpoint name, which will never be registered) or in `cluster_links`
   (for a link to shop's node, which will never come back), each up to 30 s. Neither
   wait looked at membership: SWIM declared shop dead after ~5 s, and the sessions
   (stage markers in `run_cluster_party`: all stuck in one of those two waits) kept
   counting toward books' drain, which ran to its own hard deadline.
3. **A second signal was ignored.** `drain_on_signal`'s doc says a second signal
   "escapes the watcher and stops the process at once". The runtime's escape
   (`march_signal_dispatch`, second delivery of a watched Term/Int) only sets
   `g_http_shutdown`, which only an HTTP server loop reads, and `Topology.drain`
   called again returned at once (`closing` already set). So a draining node ignored
   every further SIGTERM until its hard deadline.

**How forge made this minutes long.** `Procs.stop_all` stops a `--processes` run's
pools one at a time, in reverse start order, giving each `[drain] hard_ms` + 2 s
before SIGKILL. So shop drained for its full 120 s (cause 1) before books got
SIGTERM at all; books then waited on its stranded sessions (cause 2, plus the
sessions that formed and then lost shop), and warehouse had not been signalled yet.
That is the "two processes alive 3 minutes after Ctrl-C". shop-1 itself did exit at
its hard deadline (the run reported `exited 1` for it); a separate "hard deadline
reached but the process stayed up" failure was not reproduced (10+ runs of the
scenario and two runs of the demo). The sequential stop order is filed separately:
`specs/todos/2026-10-13-forge-run-processes-sequential-stop.md`.

## Fix

- `SessionNode.refuse_initiations(node)` (new, public; `refusing_initiations` reads
  it) sets a flag in the per-node `session_node_initiated_<id>` table; from then on
  `initiate` returns `Err(Left("draining"))` before it counts or invites anything.
  `Topology.close_all` (what the SIGTERM drain and `Topology.stop` run) calls it. A
  per-node flag rather than `epoch_draining()`: a hot reload drains OLD epochs too,
  and old-code tasks would then be refused for the life of the process.
- `cluster_links` gives up at once when a missing peer's node is `Membership.Dead`
  (`node_dead`), instead of at the 30 s limit.
- An offer treats a session as abandoned while forming when its initiator withdraws
  it (as before) OR when the invitation's node (`Delivery.from_node`) is dead, so
  `find_peers` stops waiting for the dead initiator's endpoint.
- `Topology.drain` called while a drain is already running (a second signal) reports
  `second signal: stopping <node> now with N session(s) still running` and exits 1.

## Tests

Three scenarios under `test/two_node/`, each red before the fix (3 of 3 runs) and
green after (5 of 5):

- `drain_traffic` (three nodes, the demo's shape): node-c's 8 tasks loop
  `initiate_Shop`; SIGTERM to node-c must end it within 12 s with exit 0 (hard
  deadline 4 s), then node-b and node-a drain. Before: node-c reached its hard
  deadline with 8 sessions running and exited 1.
- `drain_initiator_killed` (three nodes): node-c is SIGKILLed mid-traffic; once node-b
  sees it dead, node-b's and then node-a's SIGTERM drains must exit 0. Before: node-b
  hit its hard deadline with 1-4 stranded sessions and exited 1.
- `drain_second_signal` (two nodes, from `drain_initiated`): a second SIGTERM to a node
  draining a 30 s session must stop it within 5 s with status 1. Before: still running
  6 s later.
