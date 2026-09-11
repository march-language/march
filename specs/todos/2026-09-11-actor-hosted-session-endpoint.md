# `[P2]` The actor-hosted session endpoint, and the mailbox transport

**Status:** specced 2026-09-11, not started. Step 6 — the last one — of
`specs/progress/2026-09-03-protocol-projector-typed-endpoints.md`, whose item
3 deferred it. This is the demonstration the whole capability line was aimed
at: a session endpoint driven by an actor's mailbox, restartable by its
supervisor, with the protocol enforced by the generated types.

**It is not blocked.** That file said two prerequisites were needed, "neither
designed yet", and it named a third state of the world in item 3 that this
design avoids entirely. The correction is below, with the probes.

## What the progress file got wrong

> 1. **A place to keep the state that the checker actually tracks.** Either
>    the L3 gap is closed for actor state, or the endpoint state does not live
>    in actor state at all — it rides in each message and is `let`-bound
>    inside the handler, where tracking is real.
> 2. **A transport whose `suspend` delivers into a mailbox.**

Both premises were shaped by putting the session state in the actor. Measured
on `main` at `87101987`:

- **The recommended shape does not give the guarantee it claims.** An actor
  handler's parameters are tracked for neither must-use nor at-most-once, so a
  session state riding in a message can be dropped or duplicated by the
  handler before any `let` touches it. Filed as
  [[2026-09-11-linear-actor-handler-parameter-untracked]]. A `let`-bound copy
  *is* tracked, so the idiom helps — but it is a convention, not a check.
- **The state does not need to live in the actor at all.** The generated API
  is callback-shaped: `recv_X(s, st, k)` and `offer_…(s, st, on_a, on_b)` put
  the continuation in a closure, and the session state is already captured
  there. Keep it there, and neither the actor-state gap nor the handler-param
  gap is on the path.
- I also claimed in conversation that both prerequisites were "filed". Only
  the actor-state one was
  ([[2026-09-10-linear-actor-state-field-retained-after-consume]]); the
  mailbox transport had never been written down. This file is it.

## The mechanic works today, on both backends

The whole transport reduces to three moves, and all three are ordinary March.
Probed end to end (`--check` exit 0, interpreted and `--compile` both printing
the same two lines):

```march
-- a continuation stored by non-actor code, invoked inside a handler turn
fn install(ks, ep : Int, k) : () do Vault.set(ks, "k" ++ int_to_string(ep), k) end
fn fire(ks, ep : Int, msg : Bytes) : Int do
  match Vault.get(ks, "k" ++ int_to_string(ep)) do
    Some(k) -> k(0, msg, ep)
    None    -> panic("no continuation for endpoint")
  end
end
-- a delivery routed to the endpoint's owning actor
fn route(owners, ks, ep : Int, msg : Bytes) do
  match Vault.get(owners, "o" ++ int_to_string(ep)) do
    Some(p) -> send(p, Deliver(ks, ep, msg))
    None    -> panic("no owner for endpoint")
  end
end

actor Ep do
  state { n : Int }
  init  { n: 0 }
  on Deliver(ks, ep : Int, msg : Bytes) do
    let _ = fire(ks, ep, msg)
    { state with n: state.n + 1 }
  end
end
```

Two facts that shaped it, both found by probing:

- **One `Vault` per element type.** Owners (`Pid`) and continuations
  (closures) cannot share a table — typed vault handles reject it with
  ``expected `Pid({ n : Int })` but got `a -> Bytes -> Int -> Int` ``.
- **Do not use `self`.** `self` inside a handler does not compile at all
  (`use of undefined value '@self'`), filed as
  [[2026-09-11-self-in-an-actor-handler-does-not-compile]]. The spawner knows
  the pid, so ownership is registered at the spawn site. The probe above
  compiles precisely because it avoids `self`.

## Design

### The transport

A second `Session.Ops` dictionary beside the in-process one in
`test/session/stream_endpoints.march`. The dictionary shape does not change —
that is the point of the parent design — only what the four operations do:

| op | mailbox transport |
|---|---|
| `register(ap, role)` | hand out an endpoint id, as the in-process one does |
| `emit(ep, to, msg)` | enqueue `(to, ep, msg)`; on drain, look up `to`'s owner and `send(owner, Deliver(ep, from, msg))` |
| `suspend(ep, k)` | store `k` in the continuations vault under `ep` |
| `close(ep)` | drop the continuation and the owner entry |

Plus one operation that is **not** in the dictionary, because it is about
actor identity rather than about sessions: `own(t, ep, pid)`, called at the
spawn site to say which actor drives an endpoint. Keeping it out of
`SessionOps` is deliberate — a dictionary field named after actors would
couple the transport-level contract to one transport, which the parent design
forbids.

Delivery ordering stays the in-process transport's: `emit` enqueues, a drain
step routes. The mailbox hop is what makes it actor-hosted; the fixed drain
order is what keeps a test reproducible.

### The endpoint actor

The actor is a thin shell. Its only handlers are `Start`, which registers and
drives the endpoint to its first suspension, and `Deliver`, which invokes the
stored continuation for that endpoint. Everything protocol-shaped is the
generated API, called from ordinary functions exactly as in
`test/session/stream_endpoints.march`; the actor never names a session state
type.

**The one real limitation, and it must be documented rather than discovered:**
an endpoint callback cannot read the actor's `state` record. The callback was
built in an earlier turn and closed over what was in scope then. For a v1
whose actor exists to run the endpoint this costs nothing. If a callback must
reach actor state, that is the follow-on below, not a patch.

## Order of work

1. The mailbox transport beside the in-process one, with `own` and the two
   vaults, as an ordinary March module in the test tree.
2. An endpoint actor for `Stream`'s consumer, spawned and owned at the spawn
   site, driven by `Deliver`.
3. A golden with a pinned trace, run on both backends, sharing
   `stream_endpoints.expected`'s shape so the actor-hosted and function-hosted
   runs can be compared line for line.
4. Put the endpoint actor under a supervisor and kill it mid-session. Decide
   and pin what a restart means: the session is gone and the endpoint must
   re-register, or the transport holds the continuation and the restarted
   actor resumes. **The first is almost certainly right** — a session has
   linear state and half of it lives in the peer — and whichever is chosen,
   the test must show the choice, since this is the question an actor-hosted
   endpoint exists to answer.
5. Update the parent progress file's item 3 to point here.

## Tests

- Golden: the `Stream` protocol with an actor-hosted consumer, same trace on
  both backends. **Prove it non-vacuous** by dropping the `route` call and
  watching the trace stop, the way the in-process fixture was proved.
- A delivery to an endpoint with no owner, and one with no continuation, must
  panic with the messages above rather than silently doing nothing. The
  in-process transport learned this the hard way: its first version dropped
  such deliveries and a two-line trace looked like a protocol bug.
- The supervisor case from step 4.
- The existing `stream_endpoints` golden must not move. If it does, the
  transport change reached into the generated API, which it must not.

## Out of scope

- **Changing `SessionOps`.** If this design seems to need a fifth field,
  re-read the parent design's "protocol-agnostic / transport-level" section
  first.
- **A parked, handler-shaped generated API** (`@[endpoints(actor)]` emitting
  transitions that return to the mailbox instead of taking a callback). That
  is the answer to the callback-cannot-read-actor-state limitation, it is a
  generator change rather than a transport, and it should be specced on its
  own once something actually needs it.
- **A network transport.** Same dictionary, different delivery; nothing here
  should assume in-process.
- Fixing the three linearity holes or `self`. Each is filed, and this item is
  deliberately built so that none of them is on its path.
