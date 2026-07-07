> Part of the March Language Reference — see [specs/lang/index.md](index.md).

# Session Types

A protocol is an agreement about *who sends what, and in what order*. Two programs that disagree — one sends before the other is ready, or a channel is used after it's closed — deadlock or corrupt data at runtime, usually under load, usually in production.

March's **session types** turn those agreements into types the compiler checks. You declare a `protocol`, the compiler derives each side's obligations, and any program that breaks the protocol **fails to compile**. Sending in the wrong order and using a channel after it's closed are both type errors, not surprises. (Forgetting to close a channel, and not handling every branch a peer might choose, are related but *weaker* guarantees — see [The guarantees, in one place](#the-guarantees-in-one-place) for the precise, verified story.)

These are *binary* session types: a protocol describes exactly two roles talking over one channel. (For data-parallel fan-out across a whole collection, see [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/); for actor mailboxes, see [Actors]({{ site.baseurl }}/docs/actors/) — and the [section below](#session-types-and-actors) on how the two relate.)

**What is byte-identical interpreted vs compiled, and what is NOT.** The **binary channel plane** (`Chan.*`, not `MPST.*`) with `Int`/`Bool`/`String` payloads, correctly interleaved, produces identical observable output on both backends — mechanically pinned by the golden conformance corpus (`specs/lang/golden/g38`–`g39`, verified `MATCH` interpreted-vs-compiled; see the [operational reference](core-march.md) §4.11.5). **Multi-party session types (`MPST.*`) are typing-only**: every `MPST.*` program segfaults compiled (exit 139) even though the interpreter runs it correctly — a filed open finding (`specs/todos.md`, F3). This document's examples all use binary (two-role) protocols, which are the safe, byte-identical, production-ready surface; MPST is documented as a typing concept in the [typing reference](core-march-types.md) §2.7.4 but should not be relied on compiled today.

For the typing side (protocol declaration, projection, duality, per-operation channel-state typing) see the [typing reference](core-march-types.md) §2.7; for the runtime model (the crossed-queue representation, why `recv` never suspends, and the no-scheduler deadlock boundary) see the [operational reference](core-march.md) §4.11.

---

## The idea

Without session types, a channel is just a pipe: nothing stops you from reading when you should write, or closing while the other side is still talking. With them, the channel carries a **linear type that advances at every operation**. After you `send`, the type says "now receive"; after you `receive`, it says "now send" or "now close." The compiler reads that type and rejects code that does the wrong thing next.

Two classes of bug become compile errors:

- **Wrong-order / wrong-direction communication.** `Chan.send` on a channel whose protocol says "receive next" doesn't type-check.
- **Use-after-close.** The channel is *linear* — you cannot keep using an endpoint after `Chan.close`, or use the same continuation twice.

Two more classes *sound* like they'd be compile errors but, as verified against the current implementation, are not always caught — see [The guarantees, in one place](#the-guarantees-in-one-place) below for the precise (narrower) story on dropped channels and unhandled `offer` branches.

The result is a static guarantee: if your program compiles, the two sides agree on the conversation and the channel is never used after close. (Two related properties — a channel is always eventually closed, and every offered case is handled — are *usually* true in practice but are not, in fact, mechanically enforced; see [The guarantees, in one place](#the-guarantees-in-one-place).)

---

## Declaring a protocol

A protocol is declared with the `protocol` keyword (not `session`). Each step is `Role -> Role : Type`, read as "this role sends a value of this type to that role." Roles are **inferred** from the steps — there is no `between A, B` clause to write.

```march
protocol Echo do
  Alice -> Bob : String
  Bob -> Alice : String
end
```

This reads: Alice sends a `String` to Bob, then Bob sends a `String` back to Alice. The compiler **projects** the global protocol onto each role's local view and checks **duality** — that one side's "send" is exactly the other side's "receive." For `Echo`:

- Alice's view: `send String`, then `recv String`, then end.
- Bob's view: `recv String`, then `send String`, then end.

These are duals, so the protocol is well-formed. If they weren't (say both roles tried to send first), the protocol itself would be rejected.

---

## The `Chan` API

A session-typed channel is created from a protocol and used through five operations. Each one advances the channel's linear type, so the idiomatic style is to **rebind the channel** at every step (`let ch = Chan.send(ch, …)`), threading the freshly-advanced endpoint forward.

A channel endpoint's type is written `Chan(Role, Protocol)` — for example `Chan(Alice, Echo)` is Alice's end of the `Echo` protocol. That annotation is what lets the compiler project the protocol onto the role and check each operation; a bare `Chan` carries no role and can't be checked.

| Operation | Type transition | Returns |
|-----------|-----------------|---------|
| `Chan.new(Proto)` | creates two **dual** endpoints (protocol named bare, not as a string) | `(Chan, Chan)` — one per role |
| `Chan.send(ch, v)` | `send T, then S` ⟶ `S` | the advanced `Chan` |
| `Chan.recv(ch)` | `recv T, then S` ⟶ `S` | `(value, advanced Chan)` |
| `Chan.choose(ch, :label)` | `choose {…}` ⟶ the chosen branch | the advanced `Chan` |
| `Chan.offer(ch)` | `offer {…}` ⟶ the picked branch | `(label, advanced Chan)` |
| `Chan.close(ch)` | requires the protocol be **complete** (`end`) | `()` |

A few rules the type checker enforces, so they never reach runtime:

- **`Chan.new(proto)` returns the two endpoints.** Hand one to each role. They are linked: what one side sends, the other receives.
- **`send`/`recv` must match the protocol's next step.** Calling `Chan.send` when the protocol says "receive next" is a type error.
- **`Chan.close` only type-checks at the end of the protocol.** If there are still steps left, closing is rejected — you can't hang up mid-conversation.
- **The endpoint is linear.** Each rebinding consumes the previous one, so you can't accidentally reuse a stale (pre-advance) handle. (Linearity here is the same generic `let`-binding tracker every other linear value uses, not session-specific accounting — see [The guarantees, in one place](#the-guarantees-in-one-place) for where "forgetting to close" actually does and doesn't get caught.)

---

## A worked example: request–reply

Here is the `Echo` protocol fully implemented. Each role's side is a function that takes its endpoint as `Chan(Role, Echo)` and threads it through `send` → `recv` → `close`:

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

Notice what you *can't* write here. If `client` tried to `Chan.recv` before `Chan.send`, the projected type for Alice's endpoint says "send next," so the receive is a type error. If `server` forgot to `Chan.close`, the linear endpoint would be left unconsumed — also an error. The protocol is enforced structurally, not by discipline. (`Chan.new(Echo)` takes the protocol as a bare name, and returns Alice's and Bob's dual endpoints to hand to the two functions.)

**A caveat this shape hides: `client` and `server` are each individually well-typed, but calling them as two ordinary, uninterrupted function calls from one `main` — in *either* order — is not runnable.** `client` starts with a `send`; `server` starts with a `recv`. Because `Chan.recv` never suspends (there is no scheduler backing a channel — see the Runtime note below), calling `server(bob)` before `client(alice)` has sent anything crashes at `server`'s first `recv`, and calling `client(alice)` before `server(bob)` has sent its reply crashes at `client`'s `recv` of the echo — on *both* backends. The two-function form here documents *what each role's own view of the protocol looks like* (useful on its own, and directly usable if each side runs as its own actor or is driven by an external scheduler); it is not, by itself, a call sequence you can drop into one `main`. The example immediately below shows the form that actually runs: the two sides' *steps* interleaved by hand into a single control flow, every `send` before its matching `recv`.

> **Runtime note.** A channel is backed by two directional queues (one per direction), on **both** backends. Session *safety* — correct order, no use-after-close — is checked entirely at compile time; the runtime does not re-verify it. `Chan.recv` does **not** block or suspend on *either* backend: if the matching value hasn't been sent yet, `recv` fails immediately with a runtime error (interpreted) or aborts (compiled) — there is no scheduler backing channels the way there is for actor mailboxes. So every runnable program, on **both** backends, must interleave the two sides in a single control flow so that each `send` runs before its matching `recv`:
>
> ```march
> fn main() do
>   let (alice, bob) = Chan.new(Echo)
>   let alice = Chan.send(alice, "hello")     -- Alice sends first
>   let (msg, bob) = Chan.recv(bob)           -- Bob receives
>   let bob = Chan.send(bob, "echo: " ++ msg) -- Bob replies
>   let (reply, alice) = Chan.recv(alice)     -- Alice receives the echo
>   Chan.close(bob)
>   Chan.close(alice)
>   println(reply)   -- echo: hello
> end
> ```
>
> The function-structured `client`/`server` form above is exactly this shape split into two functions called in the right order from `main` — it does not run the two sides concurrently on separate green threads. See the [operational reference](core-march.md) §4.11.1–§4.11.3 for the queue representation and §4.11.6 (finding F6) for why recv-before-send is a scope boundary, not a bug: session types here are a linear protocol-conformance checker over a same-thread mailbox, not a concurrent scheduler.

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

`Chan.choose(ch, :label)` advances the channel into the chosen branch; `Chan.offer(ch)` returns `(picked_label, advanced_channel)`. An invalid label passed to `choose` (one the protocol didn't declare) is rejected at typecheck time. Handling the picked label is an ordinary `match` on the returned `Atom`, so ordinary `match` rules apply — including that a missing arm is only a warning (see [The guarantees, in one place](#the-guarantees-in-one-place)), not the hard error you might expect from "the compiler enforces the protocol."

---

## The guarantees, in one place

If a program using session-typed channels compiles, then:

- **No protocol violations.** Every `send`/`recv` matches the protocol's next step, on both sides, by construction (duality is checked when the protocol is declared).
- **No use-after-close.** The channel is linear; an endpoint cannot be used after `Chan.close`, and `close` only type-checks once the protocol is complete.

These properties are the same ones you'd otherwise chase with runtime assertions and integration tests — promoted to compile-time checks that hold for *all* executions, not just the ones your tests happened to hit.

**Two things that sound like guarantees but are not, verified live and filed as open findings** (`specs/todos.md`; see the [operational reference](core-march.md) §4.11.6 for the full write-up):

- **Dropped channels are not actually caught.** Linearity here rides the same generic `let`-binding tracker every other linear value uses, not session-specific accounting — a program that never calls `Chan.close` on an endpoint that has already reached the end of the protocol typechecks and runs cleanly (F7). The discipline holds for `let`-bound continuations threaded through in the same scope; it does not hold universally.
- **An `offer` that doesn't handle every label is a warning, not an error.** `match`'s exhaustiveness check (the same one that governs every other `match` in March) only warns on a missing case — `--check` still exits 0. If your build treats warnings as informational only, an unhandled label compiles.

---

## Session types and actors

Session types and [actors]({{ site.baseurl }}/docs/actors/) are **complementary** mechanisms, not competitors. They solve different shapes of problem:

| | Actors (mailboxes) | Session-typed channels |
|---|---|---|
| **Shape** | identity + state + a mailbox; many senders, one receiver | a two-party conversation over one linear channel |
| **Typing** | each `on Msg(...)` handler is typed, but message *order* is unconstrained — any actor can `send` any message at any time | the *sequence* of sends/receives is typed; order is enforced |
| **Multiplicity** | one mailbox, fan-in from anywhere | exactly two endpoints, point-to-point |
| **Lifetime** | long-lived process; mailbox always open | the channel *ends*, and `close` is checked once the protocol is complete — though (see above) nothing forces you to ever get there |
| **Best for** | stateful services, supervision, fan-in event handling | strict request/reply or multi-step handshakes where ordering correctness matters |

The mental model: **an actor's mailbox guarantees each message is well-typed; a session channel additionally guarantees the sends and receives that do happen arrive in the agreed order.** Reach for an actor when you have a stateful entity that many parties talk to (a counter, a connection, a supervised worker). Reach for a session channel when two parties run a fixed protocol and you want the compiler to prove they follow it — a login handshake, a request/reply exchange, a negotiation with branches.

**The two do not layer as freely as they might first appear.** An actor's mailbox is backed by the scheduler — `receive()` genuinely suspends the actor's green thread until a message arrives, so two actors can `send`/`receive` in whatever order and the scheduler sorts it out. A session channel has no such backing: `Chan.recv` never suspends (see the Runtime note above), so a session conducted between two actor handlers still needs its `send`s and `recv`s to land in the right order relative to each other — the channel does not gain scheduler-backed blocking just because its endpoints happen to live inside actors. An actor handler *can* open a session channel to conduct a typed sub-conversation with another actor, but only if the two handlers' message-driven control flow already guarantees each `send` happens before its matching `recv` is attempted.

---

## See also

- [Actors]({{ site.baseurl }}/docs/actors/) — mailboxes, `spawn`/`send`, and the scheduler these channels run on.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/) — the linearity discipline that makes "use exactly once, then close" checkable.
- [Choosing a concurrency primitive]({{ site.baseurl }}/docs/actors/#choosing-a-concurrency-primitive) — where session channels fit among the other concurrency tools.
