---
layout: docs
title: Session Types
nav_order: 10.7
permalink: /docs/session-types/
---

# Session Types

A protocol is an agreement about *who sends what, and in what order*. Two programs that disagree (one sends before the other is ready, or a channel is used after it's closed) deadlock or corrupt data at runtime, usually under load, usually in production.

March's **session types** turn those agreements into types the compiler checks. You declare a `protocol`, the compiler derives each side's obligations, and any program that breaks the protocol **fails to compile**. Two guarantees are hard and unconditional: if your program compiles, **every send and receive happens in the protocol's declared order**, and **no endpoint is used after it's closed**. A handful of related properties (closing a channel you abandoned midway, handling every branch a peer might choose) are weaker (they hold *usually*, not mechanically) and are collected once in [The guarantees, in one place](#the-guarantees-in-one-place).

These are *binary* session types: a protocol describes exactly two roles talking over one channel. (For data-parallel fan-out across a whole collection, see [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/); for actor mailboxes, see [Actors]({{ site.baseurl }}/docs/actors/), and the [section below](#session-types-and-actors) on how the two relate.)

**Binary vs multi-party, and what's safe to compile today.** The **binary channel plane**
(`Chan.*`) with `Int`/`Bool`/`String` payloads, correctly interleaved, works identically
interpreted and compiled; this is the production-ready surface, and every example on
this page uses it. **Multi-party session types (`MPST.*`) are typing-only right now**:
every `MPST.*` program crashes compiled even though the interpreter runs it correctly.
Stick to binary (two-role) protocols if you need a compiled binary.

---

## The idea

Without session types, a channel is just a pipe: there is no protection against reading when you should write, or closing while the other side is still talking. With them, the channel is given a **linear type that advances at every operation**. After you `send`, the type states "now receive"; after you `receive`, it states "now send" or "now close." The compiler reads that type and rejects code that does the wrong thing next.

Two classes of bug become compile errors:

- **Wrong-order / wrong-direction communication.** `Chan.send` on a channel with a protocol that states "receive next" doesn't type-check.
- **Use-after-close.** The channel is *linear*: you cannot keep using an endpoint after `Chan.close`, or use the same continuation twice.

These two are the hard guarantees: if your program compiles, the two sides agree on the conversation and the channel is never used after close. The narrower, weaker properties (unhandled `offer` branches, and abandoning a channel before it reaches `end`) are collected in [The guarantees, in one place](#the-guarantees-in-one-place) below.

---

## Declaring a protocol

A protocol is declared with the `protocol` keyword (not `session`). Each step is `Role -> Role : Type`, read as "this role sends a value of this type to that role." Roles are **inferred** from the steps; there is no `between A, B` clause to write.

```march
protocol Echo do
  Alice -> Bob : String
  Bob -> Alice : String
end
```

This reads: Alice sends a `String` to Bob, then Bob sends a `String` back to Alice. The compiler **projects** the global protocol onto each role's local view and checks **duality**: that one side's "send" is exactly the other side's "receive." For `Echo`:

- Alice's view: `send String`, then `recv String`, then end.
- Bob's view: `recv String`, then `send String`, then end.

These are duals, so the protocol is well-formed. If they weren't (say both roles tried to send first), the protocol itself would be rejected.

---

## The `Chan` API

A session-typed channel is created from a protocol and used through five operations. Each one advances the channel's linear type, so the idiomatic style is to **rebind the channel** at every step (`let ch = Chan.send(ch, …)`), threading the freshly-advanced endpoint forward.

A channel endpoint's type is written `Chan(Role, Protocol)`; for example, `Chan(Alice, Echo)` is Alice's end of the `Echo` protocol. That annotation is what lets the compiler project the protocol onto the role and check each operation; a bare `Chan` has no role and can't be checked.

| Operation | Type transition | Returns |
|-----------|-----------------|---------|
| `Chan.new(Proto)` | creates two **dual** endpoints (protocol named bare, not as a string) | `(Chan, Chan)`, one per role |
| `Chan.send(ch, v)` | `send T, then S` ⟶ `S` | the advanced `Chan` |
| `Chan.recv(ch)` | `recv T, then S` ⟶ `S` | `(value, advanced Chan)` |
| `Chan.choose(ch, :label)` | `choose {…}` ⟶ the chosen branch | the advanced `Chan` |
| `Chan.offer(ch)` | `offer {…}` ⟶ the picked branch | `(label, advanced Chan)` |
| `Chan.close(ch)` | requires the protocol be **complete** (`end`) | `()` |

A few rules the type checker enforces, so they never reach runtime:

- **`Chan.new(proto)` returns the two endpoints.** Hand one to each role. They are linked: what one side sends, the other receives.
- **`send`/`recv` must match the protocol's next step.** Calling `Chan.send` when the protocol states "receive next" is a type error.
- **`Chan.close` only type-checks at the end of the protocol.** If there are still steps left, closing is rejected: you can't hang up mid-conversation.
- **The endpoint is linear.** Each rebinding consumes the previous one, so you can't accidentally reuse a stale (pre-advance) handle, including a channel parameter (its re-use is tracked as affine). A `let`-bound channel that reaches the end of the protocol and is then dropped without `Chan.close` is also rejected. See [The guarantees, in one place](#the-guarantees-in-one-place) for the precise shape of what this check does and doesn't cover.

---

## A worked example: request–reply

Here is the `Echo` protocol, fully implemented and **runnable**. Because a channel's two directional queues have no scheduler behind them (`Chan.recv` never suspends; see the Runtime note below), a working program interleaves both sides' *steps* into a single control flow, so every `send` runs before its matching `recv`:

```march
fn main() do
  let (alice, bob) = Chan.new(Echo)
  let alice = Chan.send(alice, "hello")     -- Alice sends first
  let (msg, bob) = Chan.recv(bob)           -- Bob receives
  let bob = Chan.send(bob, "echo: " ++ msg) -- Bob replies
  let (reply, alice) = Chan.recv(alice)     -- Alice receives the echo
  Chan.close(bob)
  Chan.close(alice)
  println(reply)   -- echo: hello
end
```

`Chan.new(Echo)` takes the protocol as a bare name and returns Alice's and Bob's dual endpoints; each `Chan.send`/`Chan.recv` advances one of them, and both are closed once the protocol reaches `end`. Every operation is checked against the protocol: a `send` out of order, or a `recv` of a value that isn't due yet, simply wouldn't compile.

### Each role's view

The same protocol can be written as two functions, one per role; each takes its own endpoint as `Chan(Role, Echo)` and threads it through `send` → `recv` → `close`. This is the shape you'd use if each side ran as its own actor or under an external scheduler:

```march
mod EchoDemo do

  protocol Echo do
    Alice -> Bob : String
    Bob -> Alice : String
  end

  -- Alice's side: send, then receive the echo, then close.
  fn client(ch : Chan(Alice, Echo)) : String do
    let ch = Chan.send(ch, "hello")
    let (reply, ch) = Chan.recv(ch)
    Chan.close(ch)
    reply
  end

  -- Bob's side: receive, send the echo back, then close.
  fn server(ch : Chan(Bob, Echo)) : Unit do
    let (msg, ch) = Chan.recv(ch)
    let ch = Chan.send(ch, "echo: " ++ msg)
    Chan.close(ch)
  end
end
```

Each function documents *one role's own view* of the protocol, enforced through the type system rather than by discipline. If `client` tried to `Chan.recv` before `Chan.send`, the projected type for Alice's endpoint states "send next," so the receive is a type error; if `server` forgot to `Chan.close`, the linear endpoint would be left unconsumed, also an error.

**But these two functions are not, by themselves, a call sequence you can drop into one `main`.** `client` starts with a `send`, `server` with a `recv`; because `Chan.recv` never suspends, calling them as two ordinary uninterrupted calls, in *either* order, crashes at the first `recv` for which the value hasn't been sent yet, on both backends. The two-function form documents each role's view; the interleaved `main` above is the form that actually runs. (The function-structured form is exactly that interleaving split across two functions; it does not run the two sides concurrently on separate green threads.)

> **Runtime note.** A channel is backed by two directional queues (one per direction), on **both** backends. Session *safety* (correct order, no use-after-close) is checked entirely at compile time; the runtime does not re-verify it. `Chan.recv` does **not** block or suspend on *either* backend: if the matching value hasn't been sent yet, `recv` fails immediately with a runtime error (interpreted) or aborts (compiled); there is no scheduler backing channels the way there is for actor mailboxes. Session types here are a linear protocol-conformance checker over a same-thread mailbox, not a concurrent scheduler: the compiler checks that operations happen in the right order, not that they happen on different threads at the same time.

---

## Choice: `choose` and `offer`

Protocols can branch. One role actively **chooses** a labeled branch; the other passively **offers** to handle whichever is picked. The branch point is declared in the protocol with `choose by Role:`, listing each labeled alternative:

```march
protocol Decision do
  Client -> Server : Int        -- client sends a request
  choose by Server:             -- the server then picks a branch
    ok  -> Server -> Client : Bool
    err -> Server -> Client : Int
  end
end
```

The role named in `choose by` (here `Server`) drives the choice with `Chan.choose(ch, :label)`; the *other* role (here `Client`) receives the picked branch with `Chan.offer(ch)`:

```march
-- Server's side: receive, pick the :ok branch, send the Bool, close.
fn server_side(ch : Chan(Server, Decision)) : Unit do
  let (n, ch)  = Chan.recv(ch)
  let ch       = Chan.choose(ch, :ok)
  let ch       = Chan.send(ch, true)
  Chan.close(ch)
end

-- Client's side: send, then offer — handling each label the server might pick.
fn client_side(ch : Chan(Client, Decision)) : Unit do
  let ch          = Chan.send(ch, 42)
  let (label, ch) = Chan.offer(ch)
  match label do
    :ok  -> ...   -- recv a Bool, then close
    :err -> ...   -- recv an Int,  then close
  end
end
```

`Chan.choose(ch, :label)` advances the channel into the chosen branch; `Chan.offer(ch)` returns `(picked_label, advanced_channel)`. An invalid label passed to `choose` (one the protocol didn't declare) is rejected at typecheck time. Handling the picked label is an ordinary `match` on the returned `Atom`, so ordinary `match` rules apply, including that a missing arm is only a warning (see [The guarantees, in one place](#the-guarantees-in-one-place)), not the hard error you might expect from "the compiler enforces the protocol."

---

## The guarantees, in one place

If a program using session-typed channels compiles, then:

- **No protocol violations.** Every `send`/`recv` matches the protocol's next step, on both sides, by construction (duality is checked when the protocol is declared).
- **No use-after-close.** The channel is linear; an endpoint cannot be used after `Chan.close`, and `close` only type-checks once the protocol is complete.
- **A `let`-bound endpoint that reaches the end of the protocol must be closed.** Dropping it unclosed at that point is rejected, and re-using a channel *parameter* (not just a `let`-bound continuation) is also caught.

These properties are the same ones you'd otherwise chase with runtime assertions and integration tests, promoted to compile-time checks that hold for *all* executions, not just the ones your tests happened to hit.

**Two things that sound like guarantees but aren't, yet:**

- **An `offer` that doesn't handle every label is a warning, not an error.** `match`'s exhaustiveness check (the same one that governs every other `match` in March) only warns on a missing case, so an unhandled label still compiles.
- **Abandoning a channel mid-protocol isn't caught.** The must-close check only fires once an endpoint has reached the *end* of its protocol. Creating a channel and never touching one side again, before either endpoint reaches `end`, still typechecks and runs cleanly.

---

## Session types and actors

Session types and [actors]({{ site.baseurl }}/docs/actors/) are **complementary** mechanisms, not competitors. They solve different shapes of problem:

| | Actors (mailboxes) | Session-typed channels |
|---|---|---|
| **Shape** | identity + state + a mailbox; many senders, one receiver | a two-party conversation over one linear channel |
| **Typing** | each `on Msg(...)` handler is typed, but message *order* is unconstrained: any actor can `send` any message at any time | the *sequence* of sends/receives is typed; order is enforced |
| **Multiplicity** | one mailbox, fan-in from anywhere | exactly two endpoints, point-to-point |
| **Lifetime** | long-lived process; mailbox always open | the channel *ends*, `close` is checked once the protocol is complete, and (see above) dropping it unclosed once it gets there is now also rejected, though no check forces the conversation to *reach* the end in the first place |
| **Best for** | stateful services, supervision, fan-in event handling | strict request/reply or multi-step handshakes where ordering correctness matters |

The mental model: **an actor's mailbox guarantees each message is well-typed; a session channel additionally guarantees the sends and receives that do happen arrive in the agreed order.** Reach for an actor when you have a stateful entity that many parties talk to (a counter, a connection, a supervised worker). Reach for a session channel when two parties run a fixed protocol and you want the compiler to prove they follow it: a login handshake, a request/reply exchange, a negotiation with branches.

**The two do not layer as freely as they might first appear.** An actor's mailbox is backed by the scheduler: `receive()` truly suspends the actor's green thread until a message arrives, so two actors can `send`/`receive` in whatever order and the scheduler sorts it out. A session channel has no such backing: `Chan.recv` never suspends (see the Runtime note above), so a session conducted between two actor handlers still needs its `send`s and `recv`s to land in the right order relative to each other; the channel does not gain scheduler-backed blocking just because its endpoints happen to live inside actors. An actor handler *can* open a session channel to conduct a typed sub-conversation with another actor, but only if the two handlers' message-driven control flow already guarantees each `send` happens before its matching `recv` is attempted.

### Worked example: handing an endpoint to an actor

An endpoint is an ordinary (linear) value, so it can ride inside an actor message. This
is the safe composition pattern, verified on both backends: the requester advances its
side of the session *before* handing the peer endpoint over, so mailbox causality (
messages are processed after they are sent) guarantees the responder's `recv` finds its
value waiting:

```march
mod Main do
  needs IO.Console

  type Alice = Alice
  type Bob = Bob

  protocol Echo do
    Alice -> Bob : String
    Bob -> Alice : String
  end

  actor Responder do
    state { done : Int }
    init  { done: 0 }

    on Serve(ch : Chan(Bob, Echo)) do
      let (msg, ch2) = Chan.recv(ch)          -- safe: sent before Serve was
      let ch3 = Chan.send(ch2, "echo: " ++ msg)
      Chan.close(ch3)
      { done: 1 }
    end
  end

  fn main(_cap_console : Cap(IO.Console)) do
    let (alice, bob) = Chan.new(Echo)
    let pid = spawn(Responder)
    let alice2 = Chan.send(alice, "hello")    -- 1: advance OUR side first
    send(pid, Serve(bob))                     -- 2: then hand Bob's end over
    run_until_idle()                          -- 3: responder has now replied
    let (reply, alice3) = Chan.recv(alice2)   -- safe: causally after the send
    Chan.close(alice3)
    println(reply)
  end
end
```

Two disciplines make this correct, and both generalize:

1. **Send-before-handoff.** Every `Chan.send` the receiving handler will `recv` must
   happen *before* the actor message that delivers the endpoint. The mailbox's
   sent-before-processed ordering then does the work a channel scheduler would.
2. **Synchronize before the reply direction.** The requester must not `Chan.recv` the
   response until the responder has demonstrably run; here `run_until_idle()` provides
   that; in a live system, an `Actor.call` round-trip to the responder (or a completion
   message back) is the equivalent causal fence.

Linearity persists across the handoff: after `send(pid, Serve(bob))`, the endpoint is consumed;
any further use of `bob` in the sender is rejected at compile time (`The linear value
`bob` is used more than once`), so the protocol's exactly-once discipline is maintained even
though the conversation now spans two actors. What the compiler does *not* check is the
causal ordering itself: skip discipline 1 or 2 and the program still typechecks, then
dies at runtime with `Chan.recv: … no pending value`; that footgun is the scope
boundary described above, repeated in concrete terms.


---

## Swapping the transport: `Session`

`Chan` and `MPST` run over an in-process queue baked into the runtime. For code
that must run over a *real* transport in production and *deterministically* in
a test, the standard library's `Session` module puts the transport behind a
capability instead.

`Cap(Session.Live)` carries a **dictionary** — the transport — and every
operation dispatches through it:

```march
type Ops = {
  register : Int -> Int -> Int,                     -- access point, role -> endpoint
  emit     : Int -> Int -> Bytes -> Int,            -- endpoint, to-role, msg -> endpoint
  suspend  : Int -> (Int -> Bytes -> Int -> Int) -> Int,  -- install a handler, yield
  close    : Int -> ()
}
```

It is protocol-agnostic on purpose: no field is named after a protocol, a role
or a message. Endpoints, roles and access points are opaque `Int` handles the
transport hands out, and a message is `Bytes` — a transport must serialise
anyway, and the code that knows the real message type sits on both sides of
it. There is no `recv`: an event-driven endpoint never blocks; delivery is the
handler you pass to `suspend`, which is entered exactly once, in tail position.

`Session.attach(io, ops)` is the only way to obtain a `Cap(Session.Live)`, and
a session with nothing attached **panics** rather than silently doing nothing.

An endpoint for the `Stream` protocol above, written the way a projector would
emit it — it names no transport:

```march
pfn prod_send(s : Cap(Session.Live), ep : Int, next : Int) : Int do
  let ep1 = Session.emit(s, ep, cons(), enc_item(next))
  Session.suspend(s, ep1, fn (_from, msg, ep2) ->
    if tag(msg) == "M" do prod_send(s, ep2, next + 1)
    else Session.close(s, ep2)  ep2 end)
end
```

Under test, attach an in-process transport whose `emit` only *enqueues* and
whose run queue is drained in FIFO order after every endpoint has had its turn;
the interleaving is then fixed and the trace is the same on every run. The
worked version, with both `Stream` roles and the deterministic trace they
produce, is `test/session/stream_replay.march`. (A transport that delivers
synchronously inside `emit` is wrong for this shape: an endpoint sends *before*
it suspends, so a synchronous reply arrives before its handler exists.)

Any module that takes a `Cap(Session.Live)` parameter declares
`needs Session.Live`, as for any proof capability.

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): mailboxes, `spawn`/`send`, and the scheduler these channels run on.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): the linearity discipline that makes "use exactly once, then close" checkable.
- [Choosing a concurrency primitive]({{ site.baseurl }}/docs/actors/#choosing-a-concurrency-primitive): where session channels fit among the other concurrency tools.
