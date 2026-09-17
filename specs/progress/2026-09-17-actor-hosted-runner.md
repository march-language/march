# The actor-hosted runner: a role's session in an actor, across nodes

Shipped 2026-09-17. Phase 2 of [[2026-09-16-role-runner]], the item that record left out:
"hosting the runner's session in a user actor -- the event API
([[2026-09-13-endpoints-event-api-actor-state]]) exists in-process; wiring `run`'s
deliveries to it".

## What a node writes

```march
let pc = spawn(ConsActor)                          -- state { budget : Int, parked : Stream_Cons.Parked_Cons }
match Stream_Run.host_Cons(c, "node-b", secret, Stream_Run.addrs_from_env(), pc,
        fn s -> send(pc, StartC(s)),
        fn (s, from, msg, ep) -> send(pc, DeliverC(s, from, msg, ep))) do
  Ok(_) -> ...
  Err(SessionNode.HostGone(ep)) -> ...             -- the actor died; the session is abandoned
  Err(e) -> panic(SessionNode.run_error_message(e))
end
```

The actor is exactly the in-process one (`test/session/stream_actor_events.march`): its
start handler does `take_idle` + `register` + `await_*`, its deliver handler `resume`s and
re-parks. Nothing in it knows it is on a network.

## How the party drives an actor

`SessionNode.run_hosted(io, my_role, peers, node_id, secret, addrs, on_close, host, start,
deliver)` is `run` with a `forward` slot on the party instead of a body:

- A delivery for an endpoint whose handler is installed (the actor called `await_*`, which
  called `Session.suspend`) is handed to `forward` -- the user's `deliver` closure -- instead
  of the installed handler running (which would panic: "this endpoint is actor-hosted").
  The handler is consumed as before, so the endpoint is "not awaiting" until the actor
  re-parks. **One delivery per suspension.**
- The actor's re-park (`await_*` → `ops.suspend`) runs in the *host's* turn. What was parked
  meanwhile must be drained, and the drain's look-then-act on `handlers`/`pending` must not
  race the endpoint actor's own `deliver`, so `suspend` in hosted mode sends the endpoint
  actor `Drain(p, ep)` and the drain runs in *its* turn. Every check-then-act on those two
  vaults happens in one mailbox order.
- `Party.forward` is a vault holding the closure (key `"f"`), set by `run_hosted` before
  `start`. The callback API's parties never set it and behave exactly as before
  (`fan_loopback`, `fan`, `gone` unmoved).

## Decision: what a dead host means, and how the party learns it

A restarted host starts `Idle`; the parked session state died with the old incarnation.
The session is over for everyone, as [[2026-09-16-role-runner]] decided for a dead peer.
Two things were learned building the witness (`test/two_node/hosted_restart`):

1. **Detecting it at delivery time is not enough.** The first design had `deliver` return
   whether the host took the message (`send_checked` on the incarnation's epoch cap, as the
   in-process supervised fixture does). The witness crashes Cons *after* it has answered
   `more` but *before* it re-parks -- so no handler is installed when Item(2) arrives, the
   delivery is parked, `forward` never runs, and nobody ever looks. Every scenario where the
   host dies mid-turn is this one. So the party **monitors the host**: a dedicated
   `HostWatch` actor reads the `Down` (a raw mailbox message, `receive()`), and `run_hosted`
   sets the monitor from outside with `monitor(watcher, host)`.
2. **Host gone = no Bye.** `host_gone` sets the flag and `tcp_shutdown`s every link's data
   fd: the readers end, `serve_outcome` settles, `finish` tears down, `run_hosted` returns
   `Err(HostGone(ep))`. No `Bye` is sent, so the peers' readers see the connection drop and
   their `run` returns `PeerGone` -- not a clean end, which is what a Bye would have claimed.
   A host that exits *after* closing its endpoint is not this (the `closed` flag wins).

## Decisions carried over, and two explicitly not built

- **Cross-node restart coordination / a generated supervisor: not built**, as the runner's
  record said. The contract makes it unnecessary for correctness: every party learns the
  session ended (`HostGone` here, `PeerGone` there), no one hangs, and `run`/`run_hosted`
  can be called again for a fresh session. *Who* re-runs every role for the same new session
  is whoever started the nodes; a supervisor over `run` calls on one node cannot restart the
  peers' roles on other nodes, and pretending it can would be the wrong abstraction.
- **Resuming a session (journaling): not built.** The parked state is linear and lives in
  the actor; reconstructing it after a crash means replaying every message, which is event
  sourcing, a feature on its own. Both APIs stay available per instance: the callback API's
  "host is replaceable" ([[2026-09-11-actor-hosted-session-endpoint]]) against the event
  API's "the step can see the state".

## Two things found on the way

- **`Pid(a)`'s parameter must be phantom to the linearity checker.** `consumed_var_ids`
  counted `a` in `Pid(a)` as consumed, so `pid_to_int(pc)` -- or `host_<Role>`'s
  `host : Pid(a)` parameter -- was refused for exactly the actors this feature is for (their
  state holds the linear `Parked_<Role>`): "is linear, but `pid_to_int` is generic in a
  parameter of that type". A pid is a handle; the state never travels with it. Fixed in
  `typecheck.ml`, witness `event_pid_handle` in `test/test_endpoints.ml`.
- **A proc parked in `receive()` inside a handler was an RC underflow at exit.** The watcher
  sits in `receive()`; if `main` returned while it was still parked, the shutdown wake made
  `receive()` return the no-message sentinel and the process aborted. Fixed in the runtime
  (`stop_jmp`, `march_actor_recv`) together with the one-argument `monitor(pid)` -- a
  silently discarded partial application, now an arity error:
  [[2026-09-17-receive-in-handler-shutdown-rc-underflow]]. `run_hosted` still sends the
  watcher `Stop` at session end.

## Tests

- `test/two_node/hosted`: Stream with Prod a body on node-a and Cons an actor on node-b;
  the `stream_actor_events` trace split by node. 3/3 locally.
- `test/two_node/hosted_restart`: Cons under a one_for_one supervisor crashes in its
  deliver handler after answering `more`; node-b's `host_Cons` returns `HostGone(2)`,
  node-a's `run_Prod` returns `PeerGone(2)`, both exit. 3/3 locally.
- `test/test_scheduler_fdwait.c` gained the case `tcp_shutdown` relies on: a `shutdown(2)`
  on the fd another green thread is parked on wakes it (kqueue and epoll both report EOF).
- `fan`, `gone`, `session_node_fan_loopback`, `stream_actor_events*` unmoved.
