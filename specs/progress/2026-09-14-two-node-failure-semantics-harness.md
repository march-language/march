# Distributed actors 3/4: executable failure semantics (two real processes, partitions, restarts)

**Closed as a design record 2026-09-14.** The harness and scenarios
`restart`, `stream`, `stall` shipped (#462). The remaining scenarios and the
Docker variant are their own item now:
[[2026-09-14-two-node-scenarios-partition-skew-monitor]].


Filed 2026-09-14. `specs/lang/clustering.md`'s conformance status says it
plainly: the live layers are exercised only by single-process TCP-loopback
goldens, and "netsplit, node restart/incarnation, clock skew across hosts
remain undocumented in executable form". This is the harness that changes
that sentence.

## Why loopback is not enough

`node_call_loopback` and `node_discovery` run both nodes as green threads in
one process. That proves the wire format and the handshake, and nothing
about the properties a distributed system is *for*: the two "nodes" share
one scheduler (a stalled one stalls the other, which hides flow-control
bugs), one address space (a pid or a `creation` reused across a "restart" is
the same number), and one clock. A partition cannot be induced except by
closing a socket, which is a different failure (the peer notices at once).

## Design: one harness, scenarios as goldens

`scripts/two-node.sh <scenario>`: starts two compiled March binaries as
separate OS processes (locally: plain processes on distinct ports; in CI:
two containers on a user-defined Docker network, which the aarch64 leg
already runs). Each scenario is a March program per node plus a **fault
script** the harness applies from outside: SIGSTOP/SIGCONT a process (a
stall, distinct from a crash), SIGKILL and restart with a new `creation`,
`iptables`/`pfctl` drop rules between the two (a partition, distinct from a
close). The golden is each node's stdout, sorted per node, diffed.

Scenarios, each pinning a claim the docs make in prose today:

1. **Stall vs death.** SIGSTOP node B for longer than SWIM's suspicion
   timeout, then SIGCONT. Claim: B is marked `Suspect` then `Dead` on A,
   and on resume B's *higher incarnation* refutes the death (the SWIM
   refutation path, never executed by a golden).
2. **Partition and heal.** Drop packets A→B for 10 s. Claim: both mark the
   other dead; the global registry on each keeps its own bindings; on heal,
   `GlobalRegistry.merge`'s concurrent-conflict tiebreak on `(node_id, pid)`
   picks the *same* winner on both sides (the CRDT law, checked in a real
   split rather than by the `g44` in-process merge).
3. **Restart with a new creation.** SIGKILL B while A holds a `GlobalPid`
   for an actor on B; restart B (creation +1) which spawns an actor at the
   *same* local pid. Claim: `Node.send` from A is refused with a stale
   creation (from [[2026-09-14-remote-send-to-a-global-pid]]); A's monitor
   on the old actor fires `NodeDown`, not `Normal`.
4. **Clock skew.** Start B with `faketime` +30 s. Claim: `VectorClock`
   ordering is unaffected (it is causal), and the load gossip's staleness
   (`load_stale_ms`, wall-clock based) mis-ages B's reports — which is
   either a documented limit or a bug to fix; the scenario decides.
5. **Monitor across a reconnect** (once 2/4 lands): the at-least-once
   contract's "exactly one `Down`".

## What has to exist first

- Remote `send` (1/4), for scenario 3 and for anything that moves a message
  rather than a call.
- **The torn-stdout race.** `node_discovery` is quarantined because two
  green threads' `println`s tear (see
  [[2026-09-14-distributed-plane-known-gaps]]). Two OS processes do not
  share a stdout, so this harness sidesteps it for cross-node output — but
  each node's own concurrent output still can tear. Sorted-per-node goldens
  tolerate reordering, not torn lines; scenario programs should print from
  one actor per node.

## Where it runs

Local: `scripts/two-node.sh` with plain processes, `pfctl` on macOS for the
partition rule (needs sudo; the scenario is skipped without it, loudly).
CI: a new `two-node` job on the ubuntu leg, Docker network, ~3 min. Not in
`scripts/run-tests.sh`; it is a nightly-class gate like the sanitizer runs.

## Shipped so far (2026-09-14): the harness and scenario 3

`scripts/two-node.sh <scenario>`: compiles `test/two_node/<scenario>/node_{a,b}.march`
(from a copy, so no `.ll` lands under `test/`), runs them as two OS
processes on a random port, sources the scenario's `scenario.sh` with
`start_node` / `kill_node` / `stop_node` / `cont_node` / `wait_line` /
`wait_exit` in scope (every wait has a deadline and fails with both nodes'
output), and diffs each node's sorted stdout against `node_{a,b}.expected`.
Runs on the ubuntu CI leg after the `node_discovery` soak (~5 s); not in
`scripts/run-tests.sh`.

Scenario `restart` (item 3 above, minus the monitor half): node-b hosts an
actor and announces its `GlobalPid` on connect; node-a sends one message;
the harness SIGKILLs node-b after it prints the delivery and restarts it at
the same port with creation 2, where deterministic spawn order gives the
actor the SAME local pid; node-a notices the drop, reconnects, and its send
to the pid it held is refused `stale creation 1, node is at 2` while its
send to the re-announced pid is delivered. 5/5 runs identical locally.

Measured on the way: a user fn named `connect` miscompiles into a stack
overflow (second instance of
[[2026-09-14-user-fn-named-own-miscompiled-as-resource-builtin]]); and
there is no sleep builtin, so the reconnect backoff is
`Process.run("sleep", …)`.

Scenario `stream` (added the same day, no fault): the Stream protocol's two
endpoints on the two nodes over the `Session.Ops` network transport, each
node's ORDERED trace its projection of `stream_endpoints.expected` — see
[[2026-09-14-remote-send-to-a-global-pid]]. The harness gained `ORDERED=1`
for a node that prints from one actor. CI runs every scenario
(`scripts/two-node.sh --list`).

Scenario `stall` (scenario 1, added the same day): both nodes run a real
SWIM loop over one connection (`Socket.recv_timeout` for 50 ms, every
complete frame to an event, `SwimDriver.step` with the wall clock, the
actions performed; period 500 ms, ack timeout 300 ms, suspect timeout 1 s).
The harness SIGSTOPs node-b after node-a's first ack — a stall, not a crash:
the socket stays open and nothing is refused — and node-a takes node-b
through `Suspect` to `Dead` on timeouts alone; on SIGCONT node-b reads the
Dead gossip about itself, refutes at incarnation 2, and node-a accepts it as
`Alive (incarnation 2)`. The SWIM refutation path had never executed in a
golden. 6/6 runs identical; with the stall removed node-a never leaves
`Alive` and the harness times out, as it must.

Still open: the monitor half of scenario 3 (`NodeDown`, needs 2/4 step 4),
scenario 2 (needs `pfctl`/`iptables`), scenario 4 (clock skew), and the
Docker network variant.

## Non-goals

Three or more nodes (quorum behaviour), Byzantine peers, and performance
under load — the actor-load harness covers single-node load, and a
multi-node load story belongs after flow control exists.
