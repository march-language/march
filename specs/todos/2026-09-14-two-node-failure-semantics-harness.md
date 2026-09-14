# `[P2]` Distributed actors 3/4: executable failure semantics (two real processes, partitions, restarts)

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

## Non-goals

Three or more nodes (quorum behaviour), Byzantine peers, and performance
under load — the actor-load harness covers single-node load, and a
multi-node load story belongs after flow control exists.
