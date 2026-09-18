# DONE 2026-09-18 — cluster node service, phase 1: a running node

Phase 1 of [[2026-09-18-cluster-node-service]]: `stdlib/cluster_node.march`,
`ClusterNode`. A node joins from seed addresses, keeps one authenticated
control + data connection pair per peer, runs SWIM continuously over it, and
tells subscribers when a peer is up, suspect, dead or rejoined.

## Shape (as designed)

- A pure core, `core_new` / `core_tick` / `core_frame` / `core_linked` /
  `core_link_closed` / `core_dial_failed` : `CnState -> ... -> (CnState,
  List(CnEffect))`, unit-tested in `test/stdlib/test_cluster_node.march` (14
  cases; proved to fail on two perturbed assertions).
- One `Node` actor owns the state and performs the effects (`Send`, `Dial`,
  `Install`, `Drop`, `Emit`). Tasks: the acceptor (each connection handshaked
  in its own task, `NetKernel.handshake_addr`, deadline-bounded), one dialer
  per attempt (`Socket.connect_timeout`), a reader per connection, a ticker.
  A `CtlWriter` actor per peer is the only writer of its control socket.
- Members mirrored into a Vault: `members`, `all_members`, `addr_of`,
  `name_of`, `link_count`, `await_members`. `subscribe` gets `NodeUp /
  NodeSuspect / NodeDead(info, cause) / NodeRejoined`.
- Rules, each a core test: seeds are dialled while no linked member
  advertises them; Alive members learned by gossip are dialled (the full
  mesh); an in-flight dial is not repeated, a failed one backs off 200 ms
  doubling to 5 s; the duplicate rule (keep the pair dialled by the lower
  node_id; the same dialler replaces); generations (a close from a replaced
  pair is ignored); a close is Suspect plus an immediate redial, a REFUSED
  redial is Dead ("connection refused"); Dead drops the links (on the edge,
  not the level); Dead members are redialled (the heal path); ping-req is
  relayed; a new creation reports the old life dead and the new one rejoined.

## Deviations from the design

- `peer(node, id) : PeerRegistry.Peer` was not added: `Node.send(peer, ...)`
  writes the data socket directly, and in the service the data socket's one
  writer is its NodeQueue. The data-plane phase exposes the queue instead.
- `config_from_env` defaults MARCH_CLUSTER_SECRET to "march-cluster" when
  unset; a deployment must set it.

## Witnesses (scripts/two-node.sh)

| Scenario | Pins | Red check |
|---|---|---|
| `cluster_join` (3 nodes) | node-c, seeded only with node-a, links to node-b at node-b's advertised address: node_id -> address came from gossip | addr blanked in member frames: node-b and node-c never link (timeout) |
| `cluster_crash` | SIGKILL: node-a reports `dead: connection refused`, not the suspect timeout | refusal not treated as definite: golden shows `dead: suspect timeout` |
| `cluster_stall` | SIGSTOP past the suspect timeout: suspect, dead (the link is shut), rejoined after SIGCONT, through a redial and MEMBERS_SYNC refutation | no MEMBERS_SYNC on a new link: never rejoins (timeout) |

`cluster_stall` heals from the STALLED side (node-b never marks node-a Dead;
it redials when it finds its connection gone), so disabling the redial of
Dead members does not turn it red. The Dead-member redial is exercised by
`cluster_partition` (phase 2), where both sides mark each other Dead.

## Found on the way

- A Perceus bug: a field projected three records deep got no dup before a
  consuming call ([[2026-09-18-perceus-three-deep-field-projection]]).
- The let-then-paren trap (a `let x = ...` followed by a line starting with
  `(` parses as an application), hit four times in the new module; every tuple
  result goes through `let out = ... out`.
- `Map.filter`'s predicate is curried (`fn k -> fn v -> ...`).
- A compiled program does not exit while a task is parked in `tcp_accept`;
  `stop` wakes the acceptor with a connection to its own port.
