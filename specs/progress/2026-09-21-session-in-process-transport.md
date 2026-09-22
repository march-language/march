# `Session.in_process()`: a stdlib network-free session transport

**Done:** 2026-09-21. Moved from `specs/todos/2026-09-20-session-in-process-transport.md`
(original text kept below).

## What shipped (`stdlib/session.march`)

`Session.in_process() : InProcess` and `Session.in_process_with(trace)`, where

```march
type InProcess = {
  ops    : Ops,                           -- all eight fields
  drain  : () -> (),                      -- deliver until nothing more can run
  take   : () -> Option((Int, Int, Bytes)), -- for actor-hosted endpoints
  crash  : Int -> String -> (),           -- a role dies without running
  queued : () -> Int
}
```

**Name.** `Session.in_process`, not `SessionNode.loopback`: it is a
same-process transport with no network in it, and a role's unit test should
need `Session` only; `SessionNode` declares `IO.NetConnect`, `IO.NetListen`,
`IO.Process` and `IO.Spawn`, none of which a unit test should have to grant.
"Loopback" also suggests a socket.

**Semantics follow `SessionNode`**, with every role local:
- `emit` enqueues; `drain` delivers in FIFO order. Endpoint ids are role
  numbers, so one transport carries one session; registering a role twice
  panics.
- A delivery its endpoint is not waiting for (it waits on another role) is
  **parked**: skipped over and left queued, in order, until a continuation
  wants it.
- A role that closed, left, was cancelled or crashed is **gone**; messages to
  it are dropped (trace `dropped a -> b`).
- When nothing queued can be delivered, an endpoint whose continuation waits
  on a gone role (or, waiting on "any", with every peer gone) takes that
  receive's crash branch if `on_crash` installed one, else is **cancelled**:
  its `on_cancel` handler runs with `(role, cause, ep)` and it is gone in
  turn, so failure cascades. A closed role's cause reads `role N closed
  without sending`, as in `SessionNode.check_waiting`.
- `leave(ep, why)` cancels `ep` with cause `left: why`.
- `fail(ep, why)` cancels the receiving endpoint, blaming the sender of the
  delivery being resumed (its cancel handler is the "current" one, as in
  `SessionNode.protocol_failed`). The two `Session` doc comments that said
  same-thread transports panic now describe this.
- `crash(role, cause)` is the test's stand-in for a node dying.
- `take(())` is for endpoints hosted in actors (the generated event API),
  which resume themselves: it pops the next delivery some endpoint is
  waiting for and forgets that continuation, with no failure handling.
- `in_process_with(trace)` reports `close`, `cancel`, `crash`, `crash
  branch`, `dropped`, and `stalled: N queued` when a drain stops with
  deliveries nobody waits for (a silent stall is how a lost message hid
  before; see `stream_replay.march`'s header).
- Vault tables get a unique suffix from a counter, so two transports in one
  program never share state.

## Migrated

- `test/session/stream_endpoints.march`: hand-rolled transport deleted;
  `.expected` **unchanged**, byte for byte.
- `test/session/stream_actor_events.march`: deleted; routes with `take`;
  `.expected` **unchanged**.
- `test/session/logging_crash.march`: deleted (its crash-aware transport was
  the largest copy); uses `crash`. Every role line of `.expected` is
  unchanged; the transport's own lines are now the stdlib trace's wording.

Left hand-written, on purpose or by shape:
- `stream_replay.march`: written against raw `Session` calls, and its
  comments are the design record of why an in-process transport must
  enqueue. Kept as the worked "write your own transport" example.
- `stream_actor.march`, `stream_actor_supervised.march`,
  `stream_actor_restart.march`, `stream_actor_events_supervised.march`: each
  actor calls the handler `suspend` installed from its own turn, reading it
  from the fixture's own table; `take` does not hand the handler out. They
  also test supervision/restart behaviour of that routing, so the transport
  is part of what they pin.
- `test/test_endpoints.ml` / `specs/lang/types/reject/t188…`: an inline
  no-op `Ops` literal for typecheck-only cases, not a transport.

## Verification

- New `test/session/in_process.march` (whole session; `leave` cascading to
  the peer's cancel handler; undecodable bytes -> `fail` cancels the
  receiver) and `in_process_logging.march` (a delivery parked until wanted;
  `crash` -> crash branch). Compiled dune rules; interpreted output
  identical (checked by hand).
- Red controls, perturbing `stdlib/session.march` and confirming the staged
  copy changed: `leave` as a no-op removed the three cancel lines from
  `in_process`; ignoring installed crash branches turned
  `in_process_logging` and `logging_crash` into a cancel; `stream_endpoints`
  (no failure path) stayed green. Restored: all green.
- Split one protocol per file because two `@[endpoints]` protocols in one
  module break the first one's sends: filed as
  `specs/todos/2026-09-21-endpoints-two-protocols-one-module.md`.
- Docs: "Testing without a network" (`docs/` and `specs/lang/`
  `choreography.md`) and "Swapping the transport" (both `session-types.md`,
  whose `Ops` listing was also missing `on_cancel`/`leave`/`on_crash`).

---

# `[P3]` A stdlib in-process session transport

Filed 2026-09-20 by the choreography UX pass ([[2026-09-20-choreography-ux-hardening]]).

The guide's "Testing without a network" says to attach an in-process transport and points
at a hand-written `Session.Ops`. Every test that does this carries its own copy
(`test/session/stream_actor_events.march` has a complete one in about sixty lines: a
mailbox per endpoint, `suspend` installing the handler, `emit` delivering in the same
turn or parking). Ship it once, as `Session.in_process()` (or `SessionNode.loopback()`),
returning the `Ops` and a way to drive parked deliveries, so a role can be unit-tested
with `Session.attach(c, Session.in_process())` and nothing else. Include cancellation
(`on_cancel`, `leave`, `fail`) so the failure paths are testable in-process too.
