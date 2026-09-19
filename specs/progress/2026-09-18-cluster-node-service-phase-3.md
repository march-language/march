# DONE 2026-09-18 — cluster node service, phase 3: the shared data plane

Phase 3 of [[2026-09-18-cluster-node-service]]: actor messages, remote
monitors, credit and delivery failures all ride the node's one connection
pair per peer.

## What it does

- **One writer per socket.** Each link gets two writers at link time: its
  `CtlWriter` (control) and a `NodeQueue` writer on the data connection
  (credit flow control, budget 256 KiB). The data writer is the only way to
  send: `ClusterNode.queue_for(node, id)` hands it out (for `Node.enqueue`),
  and `ClusterNode.send_msg(node, to, type_tag, payload, policy)` sends through
  it.
- **Routing.** The data reader hands every ACTOR_MSG to a route: by
  destination pid (`route(node, pid, deliver)`), else by type
  (`route_type`), else DELIVERY_FAILED "no route". A stale creation is
  refused as before. Consumption is announced with CREDIT every quarter
  budget, through the control writer. Routes run in the reader's task; the
  node actor is never on the data path.
- **`on_peer_closed(node, f)`**: when a data connection ends, its reader calls
  every close handler with (peer node_id, why) AFTER its last delivery. `why`
  is the cause the node recorded before shutting the link: "node <name>
  dead: <cause>" (a `Drop(link, why)` from a Dead verdict), "replaced" (the
  duplicate rule), else "connection lost". This is what phase 4's sessions
  cancel on, in the order the drain rule needs.
- **Control frames handled in the control reader** (they touch no core
  state): MONITOR_REQ registers the remote watcher with the C registry with
  **fd -1**; MONITOR_FIRE calls the local watchers once and acks every copy;
  MONITOR_ACK forgets the pending fire; CREDIT goes to the link's queue;
  DELIVERY_FAILED to `on_delivery_failed`.
- **Remote monitors**: `monitor_remote(node, target, on_down)` /
  `demonitor_remote`. A Dead node fires NodeDown locally for every monitor
  on it and `dist_monitor_forget_node`s it.

## The MONITOR_FIRE writer, and why no runtime change

The design proposed either routing the C registry's MONITOR_FIRE through the
control writer or a per-fd frame lock in the runtime. A lock was written
(spin-with-yield, shared by `tcp_send_all` and the registry) and then
discarded for a simpler, stronger arrangement: the service registers every
remote watcher with fd **-1**, so the registry's own write fails at once
(EBADF) and the fire lands in its pending list; the node resends pending
fires once a second through the watcher's CURRENT link's control writer
(`dist_monitor_pending`). Every byte on a control socket then has one writer,
and a fire can never be written to a stale or reused fd. At-least-once plus
the receiver's dedupe gives exactly one Down.

## Fixed on the way (phase 1-2 code)

- **Hidden type errors.** `bin/main.ml` prints no diagnostic whose span is in
  a stdlib file, so a type error in `cluster_node.march` is invisible to a
  program that loads it (see memory "stdlib-diag-filter"). Checked as the
  entry (`march --check stdlib/cluster_node.march`), the module had eight:
  match arms mixing `send(...)` (which returns `Option(())`) with `()`, and
  two missing `needs` (IO.Process, IO.Random). Phase 1 and 2 had shipped with
  some of them and worked by luck. All fixed (`discard(send(...))`), and a
  dune `runtest` rule now requires `--check stdlib/cluster_node.march` to
  print nothing at all (errors and warnings); proved red on a reintroduced
  arm mismatch.
- **The one that crashed.** Phase 3 added a public `ClusterNode.monitor`;
  `register`'s unqualified `monitor(w, pid)` then resolved to it in codegen
  (the typecheck error that should have stopped it was filtered): SIGSEGV in
  `march_vault_get` at the first `register`. Renamed `monitor_remote`; no
  public name in the module now collides with a builtin (checked against
  `typecheck_builtins.ml`).
- The actor was named `Node`, a constructor name `Tree` also defines and the
  name of the `Node` module: renamed `ClusterNodeActor`.

## Witness

`two_node/cluster_mux`: node-a interleaves two 2000-message streams to two
receivers on node-b through the shared data queue (BlockSender), sends one
message to an unrouted pid, monitors a third process and has it killed.
node-b's receivers must see each stream complete and in order; node-a must
get the refusal and exactly one `Down: Killed`. **20/20** runs. Red checks:
routing by type only (the pid route ignored) -- the receivers never
complete (timeout); pending fires never resent -- no Down comes back
(timeout).

Unit tests: 2 more `test_cluster_node` cases (the Drop cause on Dead and on
a lost connection).
