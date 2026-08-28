---
layout: docs
title: Session Types
nav_order: 10.7
permalink: /docs/session-types/
---

> Part of the March Language Reference; see [specs/lang/index.md](https://github.com/march-language/march/blob/main/specs/lang/index.md).

# Session Types

A protocol is an agreement about *who sends what, and in what order*. Two programs that disagree (one sends before the other is ready, or a channel is used after it's closed) deadlock or corrupt data at runtime, usually under load, usually in production.

March's **session types** turn those agreements into types the compiler checks. You declare a `protocol`, the compiler derives each side's obligations, and any program that breaks the protocol **fails to compile**. Sending in the wrong order, using a channel after it's closed, forgetting to close a finished channel, and leaving a branch a peer might choose unhandled are all type errors, not surprises; see [The guarantees, in one place](#the-guarantees-in-one-place) for the precise, verified story, including the two narrower gaps that remain.

These are *binary* session types: a protocol describes exactly two roles talking over one channel. (For data-parallel fan-out across a whole collection, see [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/); for actor mailboxes, see [Actors]({{ site.baseurl }}/docs/actors/), and the [section below](#session-types-and-actors) on how the two relate.)

**What matches exactly between interpreted and compiled, and what does NOT.** The **binary channel plane** (`Chan.*`, not `MPST.*`) with `Int`/`Bool`/`String` payloads, correctly interleaved, produces identical observable output on both backends, mechanically pinned by the golden conformance corpus (`specs/lang/golden/g38`–`g39`, verified `MATCH` interpreted-vs-compiled; see the [operational reference](https://github.com/march-language/march/blob/main/specs/lang/core-march.md) §4.11.5). **`MPST.*` send/recv/close round-trips run correctly on both backends, confirmed again 2026-07-24** (transcript in `specs/todos/`): a 3-role and a 4-role protocol, each with `Int`/`Bool`/`String` payloads, both compile and run, printing output identical to the interpreter, exit 0; the segfault this section used to describe (finding F3) no longer shows up. What truly remains unimplemented is **multiparty `choose`/`offer`** (`MPST.choose`/`MPST.offer` do not exist as typed operations yet; calling them is a compile error, not a crash), and MPST still has no *golden* conformance witness (`specs/lang/golden/`), only the ad hoc transcript cited above, so a send/recv/close-only MPST program is verified-correct but not yet mechanically pinned the way the binary plane is. See the [typing reference](https://github.com/march-language/march/blob/main/specs/lang/core-march-types.md) §2.7.4 for the projection/consistency infrastructure MPST protocols go through.

For the typing side (protocol declaration, projection, duality, per-operation channel-state typing) see the [typing reference](https://github.com/march-language/march/blob/main/specs/lang/core-march-types.md) §2.7; for the runtime model (the crossed-queue representation, why `recv` never suspends, and the no-scheduler deadlock boundary) see the [operational reference](https://github.com/march-language/march/blob/main/specs/lang/core-march.md) §4.11.

---

## The idea

Without session types, a channel is just a pipe: there is no protection against reading when you should write, or closing while the other side is still talking. With them, the channel is given a **linear type that advances at every operation**. After you `send`, the type states "now receive"; after you `receive`, it states "now send" or "now close." The compiler reads that type and rejects code that does the wrong thing next.

Two classes of bug become compile errors:

- **Wrong-order / wrong-direction communication.** `Chan.send` on a channel with a protocol that states "receive next" doesn't type-check.
- **Use-after-close.** The channel is *linear*: you cannot keep using an endpoint after `Chan.close`, or use the same continuation twice.

A third class is also caught: **an unhandled `offer` branch.** `match`ing the label an `offer` returns is checked against the protocol's own closed branch set, not the open-ended `Atom` universe an ordinary `match` assumes; see [The guarantees, in one place](#the-guarantees-in-one-place) below for the precise shape of what's checked.

The result is a static guarantee: if your program compiles, the two sides agree on the conversation, the channel is never used after close, and every branch a peer might pick on an `offer` is handled somewhere. (A channel reaching the end of its protocol and then being dropped without `Chan.close` **is** also mechanically caught; see [The guarantees, in one place](#the-guarantees-in-one-place) for the precise, narrower shape of what's checked, the exact scope of the offered-branch guarantee, and the two caveats that remain out of scope.)

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

A channel endpoint's type is written `Chan(Role, Protocol)`; for example `Chan(Alice, Echo)` is Alice's end of the `Echo` protocol. That annotation is what lets the compiler project the protocol onto the role and check each operation; a bare `Chan` has no role and can't be checked.

| Operation | Type transition | Returns |
|-----------|-----------------|---------|
| `Chan.new(Proto)` | creates two **dual** endpoints (protocol named bare, not as a string) | `(Chan, Chan)`, one per role |
| `Chan.send(ch, v)` | `send T, then S` ⟶ `S` | the advanced `Chan` |
| `Chan.recv(ch)` | `recv T, then S` ⟶ `S` | `(value, advanced Chan)` |
| `Chan.choose(ch, :label)` | `choose {…}` ⟶ the chosen branch | the advanced `Chan` |
| `Chan.offer(ch)` | `offer {…}` ⟶ the picked branch | `(label, advanced Chan)` |
| `Chan.close(ch)` | requires the protocol be **complete** (`end`) | `()` |

`Chan.new(Proto)` returns its pair in **alphabetically sorted role name** order, not declaration order: for `Echo`'s `Alice -> Bob : String`, that's `(Alice's endpoint, Bob's endpoint)` because `"Alice" < "Bob"`, which happens to match declaration order in every example in this document. Don't rely on that coincidence: name your destructuring variables after the roles (`let (alice, bob) = Chan.new(Echo)`), not their position, and for a protocol with roles that don't happen to sort alphabetically the same as they're declared, check the sorted order before assuming which tuple slot is which. `Chan.new` is also **binary-only**: a protocol declaring more than two roles is rejected (`` Chan.new: protocol `Proto` has N roles but Chan.new needs exactly 2. Use MPST.new for multi-party protocols. ``) rather than silently handing back the first two roles' endpoints as a (non-dual!) pair; use `MPST.new(Proto)` for a 3+-role protocol, which returns an N-tuple, one endpoint per role, in the same alphabetically-sorted order.

A few rules the type checker enforces, so they never reach runtime:

- **`Chan.new(proto)` returns the two endpoints.** Hand one to each role. They are linked: what one side sends, the other receives.
- **`send`/`recv` must match the protocol's next step.** Calling `Chan.send` when the protocol states "receive next" is a type error.
- **`Chan.close` only type-checks at the end of the protocol.** If there are still steps left, closing is rejected: you can't hang up mid-conversation.
- **The endpoint is linear.** Each rebinding consumes the previous one, so you can't accidentally reuse a stale (pre-advance) handle, including a channel parameter (its re-use is tracked as affine). A `let`-bound channel that reaches the end of the protocol and is then dropped without `Chan.close` is also rejected. See [The guarantees, in one place](#the-guarantees-in-one-place) for the precise shape of what this check does and doesn't cover.

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

Notice what you *can't* write here. If `client` tried to `Chan.recv` before `Chan.send`, the projected type for Alice's endpoint states "send next," so the receive is a type error. If `server` forgot to `Chan.close`, the linear endpoint would be left unconsumed, also an error. The protocol is enforced through the type system, not by discipline. (`Chan.new(Echo)` takes the protocol as a bare name, and returns Alice's and Bob's dual endpoints to hand to the two functions.)

**A caveat this shape hides: `client` and `server` are each individually well-typed, but calling them as two ordinary, uninterrupted function calls from one `main`, in *either* order, is not runnable.** `client` starts with a `send`; `server` starts with a `recv`. Because `Chan.recv` never suspends (there is no scheduler backing a channel; see the Runtime note below), calling `server(bob)` before `client(alice)` has sent anything crashes at `server`'s first `recv`, and calling `client(alice)` before `server(bob)` has sent its reply crashes at `client`'s `recv` of the echo, on *both* backends. The two-function form here documents *what each role's own view of the protocol looks like* (useful on its own, and directly usable if each side runs as its own actor or is driven by an external scheduler); it is not, by itself, a call sequence you can drop into one `main`. The example immediately below shows the form that actually runs: the two sides' *steps* interleaved by hand into a single control flow, every `send` before its matching `recv`.

> **Runtime note.** A channel is backed by two directional queues (one per direction), on **both** backends. Session *safety* (correct order, no use-after-close) is checked entirely at compile time; the runtime does not re-verify it. `Chan.recv` does **not** block or suspend on *either* backend: if the matching value hasn't been sent yet, `recv` fails immediately with a runtime error (interpreted) or aborts (compiled); there is no scheduler backing channels the way there is for actor mailboxes. So every runnable program, on **both** backends, must interleave the two sides in a single control flow so that each `send` runs before its matching `recv`:
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
> The function-structured `client`/`server` form above is exactly this shape split into two functions called in the right order from `main`; it does not run the two sides concurrently on separate green threads. See the [operational reference](https://github.com/march-language/march/blob/main/specs/lang/core-march.md) §4.11.1–§4.11.3 for the queue representation and §4.11.6 (finding F6) for why recv-before-send is a scope boundary, not a bug: session types here are a linear protocol-conformance checker over a same-thread mailbox, not a concurrent scheduler.

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

`Chan.choose(ch, :label)` advances the channel into the chosen branch; `Chan.offer(ch)` returns `(picked_label, advanced_channel)`. An invalid label passed to `choose` (one the protocol didn't declare) is rejected at typecheck time.

Handling the picked label is a `match` on the returned `Atom`, but it is checked against the protocol's own **closed** branch set, not the open-ended `Atom` universe an ordinary `match` assumes. Covering every branch the protocol declares is silent, exactly like an ordinary exhaustive `match`. Omitting one, with no catch-all arm, is a **hard error** naming the missing label(s):

```
This `match` doesn't handle every branch the peer can choose — missing: :err.
The protocol's `offer` branches are: :ok, :err.
```

A `when`-guarded arm does not count as "handling" its label for this check (a guard can be false at runtime, so the label isn't unconditionally covered), and a guarded catch-all (`_ when ... -> ...`) does not count as a catch-all either.

There is a second rule, independent of `match` exhaustiveness: **if the `offer`'s branches continue the protocol differently** (e.g. `:ok` continues with `Server -> Client : Bool` but `:err` continues with `Server -> Client : Int`; different payload types after the branch), the channel `Chan.offer` returns cannot be driven with `Chan.send`/`Chan.recv`/`Chan.close` until it has been refined by matching on the paired label:

```march
let (lbl, ch) = Chan.offer(ch)
Chan.recv(ch)          -- REJECTED: differing branches, label not yet matched
```

```
Chan.recv: this channel came from `Chan.offer`, and the protocol's branches
continue differently, so I don't know which one the peer chose.
Match on the label first — `match lbl do :ok -> ... :err -> ... end` —
and use the channel inside each arm.
```

Matching on `lbl` first, and driving the channel from *inside* each arm, resolves it: each arm sees the channel typed at that specific branch's own continuation, not a guessed-at approximation. (When every branch continues *identically*, this restriction never fires: there's only one continuation to guess, so there's no ambiguity to resolve.) Rebinding the label variable's name (`let lbl = :ok` after destructuring it from `Chan.offer`) does not bypass this: the compiler retires the stale linkage the moment the name is rebound, so the channel stays correctly flagged as needing a match on the *current* value in scope.

---

## Repetition: `loop`

A protocol can repeat a sequence of steps indefinitely with `loop do … end`:

```march
protocol Stream do
  loop do
    Producer -> Consumer : Int
    Consumer -> Producer : Bool
  end
end
```

`loop` projects to the true recursive type `Rec X. S[X]`, a **µ-type**, the standard session-type encoding of "repeat this shape without end." Concretely: the loop body is projected with a fresh back-reference as its own continuation, so the LAST step inside the body loops back to the FIRST, not forward to whatever follows the `loop` block. This is why a channel governed by a `loop` can run the body any number of times (zero included, since `Chan.recv`/`Chan.send` just keep advancing around the same cycle): each iteration textually re-derives the same local type, so the code that drives one iteration can be repeated (by ordinary recursion or a loop construct in the surrounding March code) to drive as many as the two sides agree on at runtime.

Two consequences follow directly from "the body loops back to itself, never forward":

- **A `loop` must be the protocol's last step.** Because the loop's own continuation IS its own back-reference, there is no way for control to "fall out" of a `loop` block into subsequent steps: a step written after a `loop` at the same nesting level can never run, and the compiler rejects the protocol at its declaration site: `` Protocol `<name>`: the steps after this `loop` can never run — a `loop` block repeats forever, so it must be the last step. `` This is an intentional rule, not a limitation to work around: if a protocol needs a bounded, then-something-else shape, model the "then something else" as its own step *inside* an exit condition the two sides negotiate with `choose`/`offer` (loop vs. finish), rather than as trailing steps outside the `loop`.
- **A looping channel never reaches `end`, so it is never closed.** `Chan.close` requires the protocol be complete; a `Rec X. S[X]` type has no terminal state to reach. A channel with a protocol that is entirely a `loop` (or ends in one) is, by construction, never closed by `Chan.close`; that's expected, not an oversight, and is the same "abandoning a channel mid-protocol" shape as the F7 residual gap noted below, not a new hole this feature introduces.

### Exiting a loop: `stop`

The two consequences above mean a `loop` with no way out can only be *abandoned*, never *closed*: every `send`/`recv` inside it type-checks, but there is no sequence of operations that reaches `end`. `stop` (2026-07-27) is the way out: written as a step inside a `loop` body (directly, or nested inside a `choose` branch that is itself inside the loop), it exits the loop instead of repeating it:

```march
protocol Stream do
  loop do
    Prod -> Cons : Int
    choose by Cons:
      more -> Cons -> Prod : Bool
      done -> Cons -> Prod : Bool
              stop
    end
  end
end
```

`stop` projects to `SEnd` for **every** role, unconditionally: it discards both the loop's own back-reference (the continuation `stop` would otherwise inherit) and any steps written after it in the same list, the same way `loop` itself discards whatever follows it. Concretely, `Stream` above projects `Cons`'s side to `Rec X. Recv(Int, Choose{more: Send(Bool, X), done: Send(Bool, End)})`: the `more` branch loops back to the binder, the `done` branch reaches `End`. Because `stop` reaches a true terminal state, a channel that takes the `done` branch can be `Chan.close`d on both ends, something no `loop`-only protocol can do. This is exactly the literature shape `Rec X. choose { more: S;X, done: end }`.

Two rules keep `stop` from silently meaning something it doesn't:

- **`stop` outside any `loop` is an error.** It serves no purpose there: the protocol already ends wherever its step list ends, so a `stop` at top level (or inside a `choose` that is not itself nested in a `loop`) would be a no-op, and the compiler rejects it rather than accept a step with no effect: `` Protocol `<name>`: `stop` outside of a `loop` has no effect — the protocol already ends here if you just write nothing. ``
- **Steps written after `stop` in the same list are unreachable**, for the same reason steps after a `loop` are: `` Protocol `<name>`: the steps after `stop` can never run — `stop` exits the loop immediately, so it must be the last step. ``

A `loop` with no `stop` anywhere in it is not an error: it is a legitimate "repeat without end, abandon when done" protocol, same as before this feature. But it is worth knowing the tradeoff: without `stop`, that channel can never be closed, only dropped.

Duality needs no special handling for `stop`: `dual_session_ty` already maps `SEnd` to `SEnd`, so a `stop` branch on one role's projection is automatically dual to the matching `SEnd` on the other's.

---

## The guarantees, in one place

If a program using session-typed channels compiles, then:

- **No protocol violations.** Every `send`/`recv` matches the protocol's next step, on both sides, by construction (duality is checked when the protocol is declared).
- **No use-after-close.** The channel is linear; an endpoint cannot be used after `Chan.close`, and `close` only type-checks once the protocol is complete.
- **A `let`-bound endpoint that reaches the end of the protocol must be closed.** Dropping it unclosed at that point is rejected, and re-using a channel *parameter* (not just a `let`-bound continuation) is also caught. (This closed two formerly-open gaps, historically labeled F7; see below for the one shape that's still intentionally out of scope.)
- **Every offered case is handled.** A `match` on an `offer`'s label is checked against the protocol's own closed branch set: an omitted branch with no catch-all is a compile error, not a warning (see [Choice](#choice-choose-and-offer) above). An arm naming a label the protocol does *not* offer (a typo like `:okk`) is reported too, as a warning: the arm is dead code, not a soundness problem.
- **An `offer` with diverging branches cannot be driven unrefined.** When an `offer`'s branch continuations are not all identical, the channel it returns cannot be used at all until a `match` on the paired label refines it: every `Chan.*` operation on it is rejected, *and*, since 2026-07-27, so is unifying it with any other channel type. That second part matters: the mark identifying the pending channel is a compiler-side table keyed on the channel's identity, so before that fix a `Chan(Role, Proto)` type annotation, an `if`/`match` join with another channel, a record field, or an annotated function parameter at a call site would each mint a *fresh, unmarked* channel at the same state and launder the check away (compiled, that read one branch's `String` payload as the other's `Int`). All four routes are now rejected at the unification itself. An annotated *lambda* or nested-`fn` parameter was a fifth route that evaded even that, by never reaching a channel-to-channel unification at all; it was closed on 2026-07-27 by making lambda parameter annotations enforced (see the scope note below).

  **The precise scope of that guarantee.** Exactly two things are mechanically enforced, and they are both compiler-side checks rather than properties of the session type: (1) every `Chan.*` operation applied to the pending channel is rejected, by comparing the channel's *identity* against a table the compiler marks at the `offer`; (2) every unification of that marked channel with another channel type is rejected. Everything the language currently does with a channel (annotating it, joining it in an `if`/`match`, storing it in a record field, passing it to a function or lambda) routes through one of those two, so every laundering shape known today is covered. That is a statement about routes that have been *tried*, not a proof: the enforcement is a checked invariant, not a structural impossibility, and it has been broken in practice more than once. Most recently (2026-07-27) an annotated *lambda* or nested-`fn` parameter reached neither check, because lambda parameter annotations were never reconciled with the lambda's arrow type, so the argument unified with a bare type variable and no `TChan`/`TChan` unification took place at all. That is now fixed at its source (an annotated parameter is unified with the expected type, like every other annotation), but the shape of the failure is the point: a future construct that binds a channel without either operating on it or unifying it would reopen the hole silently. Making "awaiting refinement" a session *state*, so it persists by construction, is the durable form of this fix and is logged in `specs/todos/`. Witnesses: `specs/lang/types/reject/t95` (no `match` at all), `t97` (shadowed label), `t98`/`t99`/`t100` (annotation, `if`-join, top-level function parameter), `t102`/`t103` (lambda and nested-`fn` parameter); accept twins `t43` and `t104`.

These properties are the same ones you'd otherwise chase with runtime assertions and integration tests, promoted to compile-time checks that hold for *all* executions, not just the ones your tests happened to hit.

**Two gaps remain, both intentionally out of scope of the fixes above** (logged in `specs/todos/`; see the [operational reference](https://github.com/march-language/march/blob/main/specs/lang/core-march.md) §4.11.6 for the full write-up):

- **F7 residual: mid-protocol channel abandonment.** The must-close check only fires once an endpoint has reached the *end* of its protocol. Abandoning a channel *mid*-protocol (creating it and never touching one side again, before either endpoint reaches `end`) still typechecks and runs cleanly.
- **F6: no scheduler.** `Chan.recv` never suspends; a program with two sides driven in the "wrong" order relative to each other deadlocks at runtime (not statically), on both backends. That's the same territory as the mid-protocol-abandonment gap above, not something a `match`/closedness check can catch; see the [operational reference](https://github.com/march-language/march/blob/main/specs/lang/core-march.md) §4.11.6 and the Runtime note above.

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
side of the session *before* handing the peer endpoint over, so mailbox causality
(messages are processed after they are sent) guarantees the responder's `recv` finds its
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

## See also

- [Actors]({{ site.baseurl }}/docs/actors/): mailboxes, `spawn`/`send`, and the scheduler these channels run on.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): the linearity discipline that makes "use exactly once, then close" checkable.
- [Choosing a concurrency primitive]({{ site.baseurl }}/docs/actors/#choosing-a-concurrency-primitive): where session channels fit among the other concurrency tools.
