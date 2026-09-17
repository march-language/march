# The role runner: from a protocol and a role→address table to a running node

Filed 2026-09-16, after [[2026-09-16-session-node-multiparty-routing]] and its follow-ups
shipped; **shipped 2026-09-16** (see the last section for what landed and where it
departs from the plan). This is the piece between "the compiler generates typed endpoints for every
role" and "write the choreography and the nodes set themselves up": today every node
hand-writes the same ~15 lines of wiring, and gets the connect direction, the join order
and the `require` check right by copying the last one.

## What a node writes today (`test/two_node/fan/node_c.march`)

```march
let listen_fd = listen_on(Env.require_int("MARCH_PORT_C"))
let conn_a = connect_retry(Env.require_int("MARCH_PORT_A"), "node-c", 100)
let p0 = SessionNode.party(Fan_Msg.role_C(), "node-c", fn _ep -> ())
let p1 = SessionNode.connect_to(p0, Fan_Msg.role_A(), conn_a)
let p  = SessionNode.require(SessionNode.accept_from(p1, accept_on(listen_fd, "node-c")), Fan_Msg.peers_C())
let s  = Session.attach(c, SessionNode.ops(p))
let _  = Fan_C.recv_Msg_A_C_1(s, Fan_C.register(s, 0), fn (a, st1) -> ...)     -- the role's code
SessionNode.serve(p)
SessionNode.finish(p)
tcp_close(listen_fd)
```

Everything but the role's own line is derivable from the protocol: which roles exist,
which pairs exchange messages (`peers_<R>()`), and the connect rule "for roles `i < j`,
`i` listens and `j` connects". The only inputs that are NOT derivable are the addresses.

## Decision 1: where topology comes from

**Addresses are a runtime value; their SHAPE is compile time.** A compile-time
declaration of hosts and ports is the wrong tool — the compiler cannot know them, and a
binary that bakes them in cannot be deployed twice. What the compiler does know, and
should check, is the shape: this role needs its own listen port iff some peer has a higher
index, and needs `(host, port)` for every peer with a lower index. So:

- The runner takes an **address table** value, `Addrs`: one entry per role,
  `(role_index, host, port)`. A role's own entry is where it listens; a peer's entry is
  where the role dials it.
- A helper reads the table from the environment under one convention:
  `<P>_<Role>_ADDR = host:port` (e.g. `FAN_C_ADDR=127.0.0.1:20002`). The two-node harness
  already exports one port per node; a scenario builds these from `MARCH_PORT_<X>`. No
  other config surface: the runner is not a service registry, and the moment it needs one
  the caller has `GlobalRegistry`.
- **Missing entries fail at startup, by name**, the way `require` does for links: a role
  with peer `B` and no `B` address panics `role C needs an address for role B` before it
  opens any socket. The check is the compiler's knowledge (`peers_<R>()`) applied to the
  runtime table — no partially-connected session ever starts.

The runner is a **stdlib function** (`SessionNode.run`); the generator adds only the typed
two-line wrapper per role. Reason: the wiring names no protocol constructor, exactly like
the transport, and a library is testable without a protocol. What the wrapper adds is
what only the generator knows — the role index, the peer set, and the type of the role's
entry state — so the caller cannot hand the runner the wrong role or a body for a
different one.

```march
-- stdlib
SessionNode.run(io, my_role, peers, node_id, addrs, on_close, body : Cap(Session.Live) -> ()) : Result((), RunError)

-- generated, one per role, in <P>_Run
fn run_C(io : Cap(IO), node_id : String, addrs : SessionNode.Addrs,
         body : Cap(Session.Live) -> Fan_C.S_recv_Msg_A_C_1 -> Fan_C.Yield) : Result((), SessionNode.RunError) do
  SessionNode.run(io, Fan_Msg.role_C(), Fan_Msg.peers_C(), node_id, addrs,
                  fn s -> do let _ = body(s, Fan_C.register(s, 0)) () end)
end
```

`node_c.march` becomes:

```march
fn main(c : Cap(IO)) do
  match Fan_Run.run_C(c, "node-c", SessionNode.addrs_from_env("FAN"), fn (s, st) -> cons(s, st)) do
    Ok(_) -> ()
    Err(e) -> panic(SessionNode.run_error_message(e))
  end
end
```

### Inside `SessionNode.run`

1. `party(my_role, node_id, on_close)`.
2. If any peer has a higher index: `tcp_listen` on my own address's port.
3. **Connect to every lower-index peer, ascending**, with retry; `connect_to` each.
4. **Accept one connection per higher-index peer**, in whatever order they arrive
   (`accept_from` learns the role from the hello; a wrong or duplicate role is a loud
   error).
5. `require(p, peers)`, `attach`, run `body` to its first suspension, `serve`, `finish`,
   close the listener.

Step 3 before step 4 is what makes it deadlock-free, by induction on the role index: role
1 has nothing to connect to, so it is accepting at once; role `k` connects only to roles
below it, each of which finished its own connects (to roles below *them*) and is accepting.
No node ever waits on a node that is waiting on it. This is the ordering the fan scenario
wrote by hand and got right by luck of having three roles.

## Decision 2: what a restarted role does

**A session is not resumable. A restart is a new session, and it ends the old one for
every peer.** The reasons, in order of weight:

- The endpoint state is linear and lives on the stack of the continuation that suspended
  it. There is nothing to resume from after a crash; reconstructing it would mean
  journaling every message, which is a different feature (event sourcing), not this one.
- The peers hold connections and parked continuations for the dead role. They must learn
  it is gone, or they hang. The transport already sees a peer's connection close;
  `serve_link` today treats that as clean only after a local close. The runner makes it a
  **`RunError.PeerGone(role)`** on every surviving node, returned from `run` — uniform,
  named, and after `finish` has torn the party down.
- A protocol violation (the generated catch-all "unexpected message") and an
  undecodable message are the same shape: **`RunError.Protocol(role, why)`**, also fatal
  to the session.

What the runner does NOT do is restart anything. Restart is the caller's supervision
decision, made per node with the tools that exist: a `run` that returned `Err` can be
called again (fresh party, fresh connections), and an actor that owns it can sit under a
supervisor. Cross-node coordination of that restart — every peer re-running its role for
the same new session — is the job of whatever started the nodes (the harness, a
deployment), and this spec deliberately leaves it there. Saying this in the API is the
point: the `Result` makes "the session ended, decide what to do" impossible to ignore,
where today a dead peer is a hang.

Explicitly out of scope: resuming a session after reconnect, and any generated
supervisor. The event-shaped actor API (`Parked_<Role>`, `resume`) exists for hosting a
session in actor state in-process; wiring the runner's deliveries to it across nodes is
a possible phase 2, and nothing in this design forecloses it, but the goal here is met
without it — `SessionNode`'s own endpoint actor already serializes a node's resumptions.

## Order of work

1. `SessionNode.Addrs`, `addrs_from_env`, `RunError`, `run` — stdlib only. Unit tests:
   the missing-address check names the role; the direction computation (who listens, who
   dials, for a 4-role peer set) — pure functions, interpreter-testable.
2. `PeerGone`: `serve_link` reports a peer's close before the local close as a link
   failure instead of a panic; `run` maps it. Witness: a two-process scenario where one
   node is `kill_node`'d mid-session and the survivor exits with `Err(PeerGone)`, not a
   hang — the harness has the hook.
3. The generator: `<P>_Run` with `run_<Role>` per role. `test/test_endpoints.ml` shape
   test lists the module; a reject fixture is not needed (the wrapper is total).
4. `test/two_node/fan` rewritten on the runner, goldens unchanged; each node's `main` is
   the four-line match above. The scenario sets `FAN_A_ADDR` etc. from `MARCH_PORT_*`.
5. Docs: the `SessionNode` section of `specs/lang/clustering.md` and `docs/clustering.md`.

## Out of scope, stated so it stays out

- A compile-time deployment declaration. Wrong tool; see Decision 1.
- Resuming a session, or journaling messages to make that possible.
- A generated supervisor or any cross-node restart coordination.
- Hosting the runner's session in a user actor (phase 2, if a caller needs it).

## Shipped (2026-09-16)

Everything in the order of work, with these departures from the text above:

- **`run` takes `secret`** (`run(io, my_role, peers, node_id, secret, addrs, on_close,
  body)`), the cluster secret `ClusterConn`'s handshake needs; the node's identity is
  derived from `node_id` the way every fixture already did. The generated wrapper is
  `run_<Role>(io, node_id, secret, addrs, body)` and `<P>_Run.addrs_from_env()` supplies
  the protocol's name and `<P>_Msg.role_names()` (new) to `SessionNode.addrs_from_env`.
  Variables are upper-cased: `FAN_C_ADDR`.
- **`RunError`** is `PeerGone(role, why) | Protocol(role, why) | Listen(port, why) |
  Accept(why) | Connect(role, why)`. `Protocol` covers what the TRANSPORT cannot deliver
  (a bad `Deliver` payload, an unexpected tag); a message the generated code cannot
  decode still panics, because it runs inside the endpoint actor's turn where there is
  no caller to return to. Making that an error would need the actor to catch a panic —
  a different feature.
- **How a survivor learns a peer is gone.** Readers report to the endpoint actor
  (`Expect` the link count, one `LinkEnded` per reader) and `serve_outcome` waits on it
  with a retained reply (`AwaitOutcome`, the NodeQueue `Wait` pattern), answered at the
  FIRST failure or the last clean end. The survivor's other readers are still parked on
  peers that are alive: they are ended with the new **`tcp_shutdown(fd)`** builtin
  (`shutdown(2)` without close). A `close()` would not do: it silently drops the fd's
  kqueue/epoll registration, so a waiter in `march_sched_wait_fd` never wakes, and a
  process whose `main` returned with a reader still parked never exits (the scheduler
  waits for every live proc). `SessionNode.serve` keeps its contract (a panic) on top of
  `serve_outcome`; `run` maps the outcome.
- **`sleep_ms(ms)`** (new builtin, `march_sched_park_self_until` in a loop) for the
  connect-retry backoff (200 × 100 ms): the stdlib cannot shell out to `sleep` the way
  the fixtures did, and there was no parking sleep at all.
- **Missing addresses panic by role** before any socket opens, as planned; the check is
  the pure `missing_addrs(my_role, peers, addrs)`, unit-tested with `dials`, `accepts`
  and `parse_addr` in `test/stdlib/test_session_node.march` (registered in
  `test/test_stdlib_march.ml`, which also had to load `session_node.march`).
- **Witnesses.** `test/two_node/fan` rewritten on the runner, goldens unchanged (each
  node prints its own "closed" line after `run` returns `Ok`, where `on_close` printed
  it before); `test/two_node/gone` (new): node-b is SIGKILLed mid-session and node-a's
  `run_A` returns `Err(PeerGone(2, _))` and the process exits. `Ok(())` is not a
  pattern; the match is `Ok(_)`.
- **A test seam.** `Desugar_endpoints.emit_runner` (a ref, on by default) lets
  `test/test_endpoints.ml` typecheck generated code against its three-file stdlib, which
  has no `SessionNode`; the `_Run` module's shape is asserted with it on, and the native
  and two-node fixtures typecheck and run it for real.
