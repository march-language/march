# `[P2]` `MONITOR_FIRE` at-least-once, and the fire written on the control connection

Filed 2026-09-14 as the remaining step 4 of
[[2026-09-14-distributed-plane-flow-control-and-control-channel]] (now a
progress record). Today a cross-node monitor fires once, best-effort, from
the C runtime (`march_dist_monitor_fire_pid` in `do_actor_death`, ignoring
write errors) onto whatever fd the `MONITOR_REQ` arrived on; a fire during
a reconnect is lost, and a `MONITOR_REQ` for a pid that has already died
gets nothing. The supervised-endpoint fixtures assume the contract this file
states: a `DistSupervisor` that never learns a remote child died restarts
nothing.

## Measured 2026-09-15 before starting: the cross-node monitor path is not wired at all

`runtime/march_monitor_registry.c` has the registry (`march_dist_monitor_register`,
`_fire_pid` from `do_actor_death`, `_fire_nodedown`, `_clear_fd`) and
`stdlib/dist_link.march` has the codecs and the March-side table — but no
builtin exposes the registry to March (nothing in `typecheck_builtins.ml`,
`llvm_builtins.ml` or `eval_builtins.ml` names `dist_monitor`), and no
fixture sends a `MONITOR_REQ` end to end. `DistSupervisor` monitors its
children "via DistLink.encode_req frames" in comments only. So this item
has a step 0 before the contract below: expose registration
(`dist_monitor_register(target_pid, watcher_node, watcher_pid, control_fd)`,
a nine-site builtin; the interpreter keeps its own table and fires from its
actor-death path), have the receiving node's `PeerReader` dispatch for tag 7
call it with the peer's control fd, deliver tag 8 as a `Down` to the local
watcher, and pin it with a loopback fixture (node-a monitors an actor on
node-b, kills it through a remote call, receives exactly one `Down`). Only
then do acks and retries mean anything.

## Contract

- `MONITOR_FIRE(target_pid, reason, ref)` is retried until the watcher's
  node answers `MONITOR_ACK(ref)` (new tag `0x0C`), with backoff, across
  reconnects; the entry expires when SWIM declares the watcher node dead
  (its watchers get `NodeDown` locally anyway).
- A `MONITOR_REQ` for a pid that has already exited is answered at once
  with `MONITOR_FIRE(reason)` — the "registered after death" race becomes
  a normal fire. The terminal reason is already kept on the actor meta
  (`terminal_message`, `terminal_set`).
- Watchers dedupe by `(target_pid, creation, ref)`, so a retried fire after
  a lost ack delivers one `Down`.
- The fire is written on the peer's **control** connection. Today the C
  runtime writes to the fd `DistLink` registered with
  `march_dist_register_watcher(..., watcher_fd)` — whichever connection the
  REQ arrived on. With the split (#465) the REQ arrives on control when the
  caller dispatches it there, so the fd is already right for a split peer;
  this item makes it explicit: the registration takes the peer's control fd
  from the `PeerRegistry` entry, not the REQ's fd.

## Design

### Where the retry table lives

Not in the C runtime. `do_actor_death` fires once, as now, and additionally
records `(watcher_node, watcher_pid, target_pid, reason, ref)` in a March-
visible pending table (`march_dist_pending_fires` → a builtin that drains
it, or a `Vault` the runtime cannot reach — so the builtin). A `MonitorRetry`
March task per node drains the pending table every 200 ms, re-sends fires
whose ack has not arrived, doubling the interval per entry up to 5 s, and
drops entries whose watcher node SWIM marks `Dead`. Acks arrive on the
control connection and are handed to `MonitorRetry.ack(ref)` by the
`PeerReader` dispatch.

Why March and not C: the retry needs SWIM's membership (March) and the
peer registry (March), and a reconnect changes the fd — the runtime knows
none of that. The runtime's job stays "fire once at death, from the death
path"; the table is the only new runtime surface.

### After-death answer

`DistLink`'s REQ handler (March) consults `is_alive(pid_of_int(target))`
and, when false, the meta's terminal reason through a small builtin
(`actor_terminal_reason(pid) : Option((Int, String))`) and fires
immediately with it instead of registering. `pid_of_int` on a pid whose
record has been freed returns the dead sentinel; the terminal reason for a
long-dead pid is then `Normal` — documented as the limit: a watcher that
registers after the record is gone learns "dead", not "why".

### Dedupe

`DistLink.MonitorTable` keeps the refs it has delivered a `Down` for until
the monitor is removed; a second `MONITOR_FIRE` for a delivered ref is
acked and dropped.

## Tests

- Unit (interpreter): `MonitorRetry` with an injected send function —
  backoff schedule, ack removes the entry, `Dead` node expires it.
- `test/native/monitor_after_death_loopback.march`: kill the target, then
  send the REQ; exactly one `Down` with the real reason.
- Two-node scenario `monitor_reconnect` (harness scenario 5): register a
  monitor, `kill_node`-and-restart the *watcher's* connection between the
  death and the ack (drop the control connection with `stop_node` timing
  or a fault that closes the socket); exactly one `Down` after reconnect.
- The monitor half of the `restart` scenario: node-a's monitor on the
  killed node-b actor fires `NodeDown`, not `Normal`, once SWIM marks the
  incarnation dead.

## Order of work

1. Control-fd registration (small, unblocks nothing but removes an
   assumption).
2. After-death answer + `actor_terminal_reason` builtin (nine-site
   addition; see the memory note on builtin sites).
3. `MONITOR_ACK` + pending table + `MonitorRetry` task + dedupe.
4. Scenario 5 and the `restart` monitor half.


---

## Shipped so far (2026-09-15): step 0

`dist_monitor_register(target_pid, watcher_node, watcher_pid, fd)` — the
March surface of `march_dist_monitor_register` (nine-site builtin; the
runtime wrapper `march_dist_monitor_register_pid` copies the March string
to a C string; capability `IO.NetConnect`; the interpreter refuses it with
a message naming the compiled backend, the `block_sender` discipline).
Witness `test/native/dist_monitor_loopback`: node-a's Watcher monitors an
actor on node-b by `MONITOR_REQ`, node-b's reader registers it with the
connection's fd, node-a asks node-b to `kill` it, the runtime's death path
writes `MONITOR_FIRE` on that fd, node-a's reader delivers a `RemoteDown`
to the Watcher: exactly one Down, reason `Killed`. 10/10 identical.

Measured: `dune build @install` does not restage `_build/default/runtime`
either (the first compile of the witness failed to link the new symbol);
a rule with a runtime dep does. The fd registered is whatever connection
the REQ arrived on — with the split, callers dispatch REQ on control, so
that is already the control fd; the explicit registration from the
`PeerRegistry` entry is still the contract's step 1.

## Shipped (2026-09-15): the after-death answer (order-of-work step 2)

`actor_terminal_reason(pid_index : Int) : Option((Int, String))` — a
nine-site builtin on both backends (the interpreter reads its own
`ai_terminal_reason`; the runtime reads the META's terminal fields by pid
index, never the record, so a request for a pid whose record has been freed
is safe). Witness `test/native/monitor_after_death_loopback`: node-a asks
node-b to kill the target FIRST, then sends `MONITOR_REQ`; node-b's reader
finds it dead and answers `MONITOR_FIRE(Killed)` at once instead of
registering a watcher that would never fire. Exactly one Down; 10/10.
The "registered after the record is gone" case reads `None` and the
fixture answers `NodeDown` for it, the documented limit.

Remaining: step 1 (registration takes the peer's control fd from the
`PeerRegistry` entry — today the fixture passes the REQ's fd, which under
the split is control), step 3 (`MONITOR_ACK`, the pending table, the
`MonitorRetry` task, dedupe), step 4 (scenario 5 and the `restart` monitor
half).

## Shipped (2026-09-15): at-least-once with acks (order-of-work step 3)

Runtime: `march_dist_monitor_fire_pid` no longer frees a watcher after the
best-effort write — the entry moves to the target's `fired` list with its
reason and stays there until `march_dist_monitor_ack(target_pid,
watcher_pid)`; `march_dist_monitor_pending_walk` exposes the list. March
surface: `dist_monitor_pending() : List((target_pid, (watcher_node,
(watcher_pid, (reason_tag, reason_msg)))))` (nested pairs: the runtime can
build tuples and cons cells, not records) and `dist_monitor_ack(target_pid,
watcher_pid)`; both `IO.NetConnect`, both refused by the interpreter.
`DistLink`: `encode_ack`/`decode_ack` (tag 12) and `resend_pending(reg)`,
which writes each pending fire on the watcher node's CURRENT control
connection from the peer registry — the fd it was first written on may be
gone. The retry cadence is the caller's (a timer, or after a reconnect);
the `MonitorRetry` task the design named is a loop around it.

Witness `test/native/monitor_ack_retry_loopback`: node-a monitors, asks for
the kill, and never reads connection 1 again (the fire is written into a
socket nobody drains); node-a reconnects; node-b resends twice; node-a
delivers ONE Down (dedupe by target pid), acks both; pending is empty.
10/10 identical.

Remaining: expiry of pending entries when SWIM declares the watcher node
dead (needs the SWIM loop of the `stall` scenario wired to
`dist_monitor_pending`), and step 4 (scenario 5 in the harness, the
`restart` monitor half).
