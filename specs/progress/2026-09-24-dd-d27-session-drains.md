# Distributed deploys: D27 session drains at loop boundaries, and step 6's follow-ups

**DONE 2026-09-24.** Parent:
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md),
sections 6.2 (D27, D11), II.5.4, II.5.5. Closes
[2026-09-23-dd-step06-followups.md](2026-09-23-dd-step06-followups.md) (all five items)
and the matching deviations of
[2026-09-23-dd-step06-epoch-model-and-drains.md](2026-09-23-dd-step06-epoch-model-and-drains.md)
(9, 11, 12, 18; edited there). Five commits, one per item below.

## 1. Drain points in the generator and the transport

`Session.Ops` has two new fields. `suspend_at_boundary(ep, from, handler)` is `suspend`
at a drain point; `on_drain(ep, h)` installs `h(role, undelivered, ep)` for the next
continuation. Every transport fills them: `SessionNode`, `Session.in_process`, and the
five hand-written ones under `test/session/*` plus the two in `test/test_endpoints.ml`
and the t188 reject fixture (a same-thread transport treats the first as `suspend` and
ignores the second).

The generator (`lib/desugar/desugar_endpoints.ml`) knows the loop heads: `LRec` now
carries the loop's `atomic` flag, `boundary_heads` collects the body node of every
non-atomic `LRec` (resolved through the binders, compared physically as `state_of`
does), and a receive, offer or crash-receive at such a node, in both the callback API
and the hosted `await_*`, suspends through `Session.suspend_at_boundary`. Every
`recv_<Msg>` and `offer_<labels>` gains an `_or_drain` form whose last parameter is
`(Int, List(<P>_Message), Drained_<Role>) -> Yield`: the drained role it waited on (0
for its own boundary), the endpoint's own messages that came back, decoded
(`try_decode`; one that does not decode is left out, the transport still counts it),
and a token whose only consumer is the generated `drained(s, token)`. So a drain handler,
like a cancel handler, holds no state any step function accepts. The chaos peer takes
the `_or_drain` form at a loop-head receive one time in two, by the seed; a protocol
without a loop draws exactly the stream it drew before.

`loop atomic do ... end` parses as a contextual identifier after `LOOP` (any other
word is a parse error naming `atomic`); `ProtoLoop` carries it as a `bool`, the
formatter and the JSON dump round-trip it, the eleven other match sites ignore it, and
the fingerprint does not include it (it changes no message: two builds differing only
in `atomic` interoperate, one draining at the head and one not).

Two stdlib-only builtins (`Typecheck_builtins.stdlib_only`): `epoch_draining()` reads
`march_hcr_epoch_draining` for the running proc's epoch, which in `SessionNode` is the
party's Endpoint actor's, the epoch the session formed under (it holds it, D28);
`epoch_drain(soft_ms, hard_ms)` is `march_hcr_drain(current, ...)`, what item 4 wires
to SIGTERM. `Session.Outcome = Finished | Drained(Int)` is declared here.

## 2. The runtime of a drain in `SessionNode`, and the rule for three or more roles

**The rule.** Let a session have any number of roles. A *boundary continuation* is one
installed by `suspend_at_boundary`. A role is *draining* when its own epoch is, or when
the sender of the delivery in hand was (every `Deliver` frame carries the sender's
draining flag; a node that is not draining sends the three-element frame every older
node reads).

1. A delivery to a boundary continuation from a draining sender, or into a draining
   receiver, is **not consumed**: it goes back to its sender as `Undelivered [to, from,
   msg]`, and the receiving endpoint **drains**.
2. A drained endpoint **returns every message addressed to it that it has not
   consumed**: what was parked for it, in the order it came, and every later arrival.
3. It sends `Drained [role]` to every peer, behind everything it sent. A peer marks the
   role drained, and from then on its `emit` to that role returns the message to the
   sender at once (no round trip).
4. An endpoint whose continuation waits on a drained role, with nothing from that role
   queued, **drains in turn** (rules 2 and 3 apply to it). So a role in the middle of an
   iteration finishes its work up to its next receive from a drained role and ends
   there; what it sent meanwhile to drained roles came back at `emit`, and what it sent
   to live roles is delivered (a live role only drains at a boundary or at a receive
   from a drained role, so it takes everything sent to it before that point in FIFO
   order).
5. A drained endpoint's `Bye` to a peer waits for that peer's own end (`Bye`, `Cancel`
   or `Drained`); each reader keeps reading to the peer's `Bye`. Nothing a peer sends
   after its own end needs returning.

**Why no message is lost.** Every message is either consumed by a continuation, or
returned to its sender, or (before the session ends) still queued. A message to a live
role is consumed or parked (rule 4 keeps a live role from ending while anything from a
live role is queued for it: it only ends at a boundary refusal, which returns the
delivery in hand and, by rule 2, everything parked, or at a wait on a drained role
with nothing queued from it, when everything else queued for it has already been
consumed in order or is from a drained role, which rule 2 returns). A message to a
drained role is returned at `emit` (rule 3) or by the drained endpoint (rule 2). And
every role ends: a draining role ends at its next boundary; every other role's
continuation either receives from a live role (consumed, progress) or waits on a
drained one (rule 4), and a protocol whose every message is eventually followed by a
loop head or an end reaches one of those. What can be lost is only what the failure
rules already lose: messages to a role that crashed or was cancelled.

In `SessionNode` this is `consume` (rule 1, in place of `resume_with` on both the
direct and the drain path), `drain_endpoint` (rules 2, 3, 5, the drain handler, and the
hosted party's cancel route with cause `"drained"`), the `Returned`/`DeliverDraining`
handlers and the `Undelivered`/`Drained` frame kinds on both the standalone and the
cluster readers, `emit`'s early return (rule 3), `check_waiting`'s `"drained"` arm
(rule 4), and `peer_gone`'s deferred `Bye` (rule 5). `run_R` returns
`Ok(Session.Drained(n))` when the endpoint drained or `n > 0` of its messages came
back, else `Ok(Session.Finished)`; every generated front is
`Result(Session.Outcome, RunError)`, and every existing `Ok(_)` match compiles.

The single-process fixtures `test/session/drain_peers.march` and `drain_peers_multi.march`
(both backends, one golden each; two files for the frontend's sake, deviation 2) pin the
rule before the network: three scripted runs with the transport's trace
(Stream: Cons drains at its boundary, then Prod drains waiting on it with item 3 in
hand; Prod's epoch drains and Cons ends at its next boundary; Ring: C drains, B
mid-iteration and A both drain waiting on C), then five protocols × 60 seeds with the
chaos peers, a seed-chosen role draining after a seed-chosen number of `step`s: Stream,
Ring (three roles, A's loop head is a send), Pair (two sends in a row to a loop head:
the second is parked when the first is refused, rule 2), Relay3 and Fork (a send to a
role after it drained, rule 3). Each session asserts `sent = consumed + returned`,
nothing dropped, nothing stalled, nothing queued, every role ended, and that the roles'
own `undelivered` counts sum to the returned count and to the trace's `undelivered`
lines. Two perturbations: dropping a drained endpoint's parked messages instead of
returning them (rule 2) is RED on 32 sessions; dropping a send to a drained role at
`emit` (rule 3) is RED on 7. `loop atomic` with both roles draining runs to
its end. The network version: `test/two_node/drain_stream` (two nodes, node-b drains
after its third item: Prod's fourth comes back, both `Ok(Drained(..))`, Prod's count is
the one message in flight) and `test/two_node/drain_ring` (three nodes: C drains, B's
`b` is refused and comes back, A drains with nothing back).

## 3. Follow-ups 3 and 4: the hard deadline

A party whose held Endpoint is killed at a hard deadline (`Crash("draining")`,
`hcr_hard_kill`): `await_outcome` now asks the Endpoint every second instead of once
per hour (the actor keeps only the newest asker), so a dead Endpoint is noticed;
`endpoint_died` reads `actor_terminal_reason`, ends the session as `Left("draining")`
(any other death: `Cancelled(my_role, "session endpoint gone: ...")`), and shuts the
standalone party's sockets so the peers see it at once. Test:
`test/two_node/drain_hard` (a `loop atomic` session, node-b arms a 300 ms hard
deadline: `Err(Left(draining))` on node-b, a cancellation waiting on Cons on node-a).

Tasks at the hard deadline: `march_sched_stop_epoch` sets `cancel_requested` beside the
stop request and raises the preemption flag; `march_sched_cancel_point` (at
`march_yield_from_compiled`, in `march_sleep_ms`, and on the stopped-receive path of
`march_actor_recv`) unwinds a task to its trampoline's `task_jmp`, which completes the
`Task` handle with the same `Err("task cancelled")` `task_cancel_by_id` stores and
counts it (`march_tasks_cancelled`). A task computing without receiving is cancelled at
its next yield point; one parked in an fd wait, a `task_await` or an `Actor.call` is
cancelled at its first cancellation point after that wait ends. Test:
`test/test_hcr_migrate_order.c`, `test_hard_deadline_cancels_tasks` (a task spawned
before the activation is cancelled through `task_await`, one spawned after it keeps
running and finishes).

## 4. Follow-up 5: SIGTERM drains the epochs

`Topology.drain` (what `drain_on_signal` runs on SIGTERM/SIGINT, and step 3's
loopback-only level-0 node) calls `epoch_drain(soft_ms, 0)` after closing the offers:
every session on the node ends at its next loop boundary (D27) and every actor still on
an old epoch takes the soft deadline; the process's own hard deadline exits before an
epoch hard deadline would matter, so none is armed. `SessionNode.drain_epochs(io, soft,
hard)` is the same from code.

## 5. Follow-up 1: `DELIVERY_FAILED` for a remote delivery the receive loop drops

`march_mbox_node` carries `origin_conn`/`origin_seq` (runtime-owned, like the epoch
stamp): the cluster node's data reader sets a thread-local delivery origin around the
route of each remote delivery (`delivery_origin_set(l.cw, d.seq)` / `delivery_origin_clear()`;
the loopback stamps a negative connection), `mbox_node_new` copies it, the deferred
queue carries it, and the actor loop's two drop sites (`migrate_msg` returned `None`; no
`migrate_msg` or two changes behind) call the hook `ClusterNode.start` installed with
`delivery_failed_watch`: it sends `DELIVERY_FAILED(seq, reason)` on that link's control
writer (or to the node's own handler for the loopback), so the sender's
`on_delivery_failed` hears it as for a route's `Err`. Three more stdlib-only builtins.
Test: `test/test_hcr_migrate_order.c`, `test_dropped_remote_delivery_reports_origin`
(five old-format messages stamped "connection 7, seqs 42..46" and one local one are
dropped after a message-type change; the hook hears exactly the five, with connection,
seq and reason; the local drop is not reported). The March side (the stamps around every
remote route, the hook installed by `ClusterNode.start`) runs in every `cluster_*`
two-node scenario, which all pass; see deviation 1 for why no scenario performs the
drop itself.

## Follow-on review findings absorbed the same day

The step-6 review found the epoch-hold mechanism this rule sits on broken in three ways,
all fixed on this branch after the five commits above: the party's hold arrived behind
its Endpoint's spawn marker (so a session formed by an old-epoch unit was not held at
all, and the `Undelivered` rule could not be trusted for it), cluster parties never
released their hold, and only one hosting pattern held. See
`2026-09-24-dd-review-party-hold-queued-behind-spawn-marker.md`,
`…-cluster-party-never-releases-epoch-hold.md`, `…-hosted-register-path-takes-no-hold.md`,
`…-session-hold-epoch-public.md` and `…-drain-current-epoch-kills-every-actor.md` in
this directory.

## Deviations

1. **Follow-up 1 has no two-node scenario that performs the drop.** A remote delivery is
   only dropped after a hot deploy changed the receiving actor's message type, and a
   two-node scenario cannot perform one: `forge deploy hot` reaches the reload server
   through an SSH tunnel only, and the scenario shell has no other signed client for
   `CAS_PUT`/`ACTIVATE5`. The drop, the origin and the hook are pinned in the C harness
   (above), which drives a real activation; the March wiring is compiled into every
   cluster node and runs (stamping every remote delivery, installing the hook) in every
   `cluster_*` scenario. A local `forge deploy hot --socket <path>` would make the
   end-to-end scenario a small addition.
2. **The drain fixture is two files.** One module with the six protocols typechecks in
   eight minutes (three: seconds; five: 48 s), so `drain_peers.march` (Stream, Ring,
   Steady) and `drain_peers_multi.march` (Pair, Relay3, Fork) split it. Filed as
   `specs/todos/2026-09-24-endpoints-frontend-superlinear-in-protocol-count.md`.
3. **`task_cancel_by_id`'s handle representation changed with follow-up 4.** It stored an
   `Err` cell in `task[3]`, which the compiled `task_await` wrapped in `Ok` and normalised
   as a tagged result, so March code never saw the `Err` (an `Ok` of a wild value
   instead). Both cancellations now store the sentinel 0 and `task_await` returns
   `Err("task cancelled")`; `task_await_unwrap` panics, as unwrapping any `Err`.
4. **A hard deadline on the current epoch cancels every pinned task in the process.**
   `SessionNode.drain_epochs(io, soft, hard)` with `hard > 0`, and `DRAIN` on the current
   epoch, stop whatever is pinned there, which is every task (tasks spawned from the
   unpinned `main` pin the current epoch). That is the existing `DRAIN` contract, now
   with a real cancel; `Topology.drain` therefore arms no epoch hard deadline (its own
   exits the process). A task parked in an fd wait, a `task_await` or an `Actor.call` is
   cancelled only at its first cancellation point after that wait ends (deviation 12 of
   the step-6 entry, narrowed).
5. **`endpoint_died` waits for the data readers** (up to 5 s) before returning, because
   `finish` closes the sockets and a `close()` under a reader still parked in the socket
   drops its wait for good (the process then never exited; found by the `drain_hard`
   scenario, diagnosed with a temporary dump of the live procs at shutdown). The normal
   path never had the race: `serve_outcome` waits for the readers' `LinkEnded`.
6. **The `drain_hard` scenario prints no per-item lines**: the number of items before a
   300 ms hard deadline varies with load, so only the two outcomes are in the goldens.
7. **Commit 1 touched one line each of `lib/desugar/desugar_topology.ml` and
   `forge/lib/topology.ml`** (step 8's files) for `ProtoLoop`'s new flag; nothing else in
   them. `stdlib/topology.march` changed only in `drain`'s body.
8. **`Deliver` frames gain an optional fourth element** (the sender's draining flag), sent
   only while draining; a node built before this reads every frame from a node that is
   not draining unchanged, and refuses a draining sender's frame as a bad payload. Both
   sides of a session are built from one source in every scenario, so no compatibility
   shim was added.
9. **Three-or-more-role rule: an atomic `loop` inside a draining session still ends at the
   hard deadline only**, by design (6.2); the fixture's `Steady` protocol pins it.

## Results

`scripts/run-tests.sh` (full) plus `test_jit`, at the final tree, load 8-15 on the
14-core Mac:

| suite | tests | result |
|---|---:|---|
| compiler | 1270 | pass (one case, `builtin_borrow_classification`, failed on the first full run: the new `delivery_failed_watch` builtin had no borrow classification; classified as owned, the group and the JIT suite rerun green) |
| eval | 282 | pass |
| codegen | 626 | pass |
| stdlib | 886 | pass |
| stdlib_march | 72 | pass |
| test_jit | 24 | pass |
| LSP (lsp, utf16, jsonrpc, incremental, query_cli) | 361, 5, 36, 10, 7 | pass |
| refinecheck | 959 | pass |

Dune-rule tests run directly: `test_hcr_migrate_order` 73/73 (four new checks for
follow-up 4, three for follow-up 1), `test_dispatch`, `test_scheduler` and its eight
siblings, `test_broadcast_migrate_leak`, `test_signal_watch`, `test_actor_registry`,
`test_reload_activate4` (both modes), the fifteen `test/session/*` fixtures on both
backends, `native_session_node_fan_loopback`, and forge's `test_topology_run` (3/3, the
level-0 Ctrl-C drain included). `scripts/check-docs.sh`, `check-runtime-sources.sh` and
`check-actor-rc-stores.sh` pass.

Two-node (`scripts/two-node.sh`): `stream`, `stream_labelled`, `fan`, `hosted`,
`topology_move`, every `cluster_*` (twenty; `cluster_partition` skips without root), and
the new `drain_stream`, `drain_ring` and `drain_hard` (three runs each of the last two).

Perturbations on the drain fixtures (compiled): rule 2 disabled (a drained endpoint's
parked messages dropped) is RED on 32 of the 300 seeded sessions; rule 3 disabled (a
send to a drained role dropped at `emit`) is RED on 7. The generator tests go RED with
the boundary suspension or the `atomic` flag removed.

**ASAN** (`march-amdr-repro` container, Linux arm64, `specs/lang/golden/sanitize.sh` as
CI's `sanitize-gate` runs it): 47 golden, 32 native and 45 two-node programs clean, 2
two-node scenarios skipped (need root); `test_hcr_migrate_order` under
`-fsanitize=address -O1`: 73/73, no report.

Not run: `bench/` (no change touches a benchmarked path: the new yield-point check is
one atomic load on a proc field, behind the existing preemption flag test).
