---
layout: docs
title: Actors
nav_order: 9
permalink: /docs/actors/
---

> Part of the March Language Reference — see [specs/lang/index.md](index.md).

# Actors

March's concurrency model is built on **actors** and **tasks**. Actors are isolated processes that communicate exclusively through message passing — no shared mutable state. Tasks are lightweight one-off computations that run concurrently and return a value.

**Compiled-actor status:** the core actor message plane runs both in the tree-walking interpreter and in ahead-of-time-compiled (native) binaries. In the compiled runtime, both actors and tasks run on an M:N green-thread scheduler (`runtime/march_scheduler.c`) — multiple OS threads, each running many lightweight green threads, with work-stealing across threads. Actor declarations lower to TIR (`lib/tir/lower_actor.ml`) and emit LLVM IR that calls the public C API (`march_spawn`/`march_send`/`march_kill`/`march_is_alive`, `runtime/march_runtime.c`); each actor runs as its own green thread. Actors park cooperatively when their mailbox is empty; tasks park when awaiting a result.

**What is byte-identical interpreted vs compiled, and what is NOT.** The **live-message plane** — `spawn` / `send` (to a live actor) / `receive` / `run_until_idle` / `is_alive` / `kill` — produces identical observable output on both backends for a program whose output does not depend on scheduler interleaving; this is mechanically pinned by the golden conformance corpus (`specs/lang/golden/g35`–`g37`, verified `MATCH` interpreted-vs-compiled — see the [operational reference](core-march.md) §4.10.5). The **`Actor.call` plane** is also backend-identical as of 2026-07-13: both backends tag-route the zero-arg sentinel positionally to the handler at its ctor index, and both enforce `timeout_ms` (compiled via a deadline-bounded yield-poll in `march_actor_call`, `runtime/march_runtime.c`; `timeout_ms <= 0` means wait forever) — pinned by `test/native/actor_counter` and `test/native/actor_call_timeout`. The two formerly-diverging planes are also backend-identical now (their historical findings are closed in the `specs/todos.md` ledger):

- **Capabilities / dead-`send`** (`get_cap`, `send_checked`, `revoke_cap`, `is_cap_valid`, plain `send` to a *dead* pid): byte-identical as of 2026-07-18 — compiled `get_cap` builds the real epoch cap (niche `None` for a dead/unknown pid), `send_checked`/`revoke_cap` return the same `:ok`/`:error` atoms as the interpreter, and `send` to a dead pid returns `None` on both backends. Pinned by `test/native/cap_epoch_plane`. See [`core-march.md`](core-march.md) §4.10.6.
- **Supervision / external state inspection**: `get_actor_field`/`pid_of_int` and the full compiled supervision plane (spawn-time child `init`, crash isolation, all three restart strategies) work compiled as of 2026-07-08 (`examples/supervision_strategies.march` runs clean). See [`core-march.md`](core-march.md) §4.10.7.

The rest of this tutorial marks each interp-only surface where it appears. For the typing side (actor declaration, `spawn`/`Pid` typing, message-payload typing) see the [typing reference](core-march-types.md) §2.6; for the scheduler and lowering internals, see the implementation reference (`specs/impl/index.md`).

---

## Defining an Actor

An actor declaration has three parts:
- `state { ... }` — the state record type
- `init { ... }` — the initial state value
- `on Msg(...) do ... end` — message handlers, each returning the new state

```march
actor Counter do
  state { value : Int }
  init  { value: 0 }

  on Increment(n : Int) do
    { state with value: state.value + n }
  end

  on Decrement(n : Int) do
    { state with value: state.value - n }
  end

  on Reset() do
    { state with value: 0 }
  end
end
```

Inside a handler, `state` refers to the current state record. Each handler must return the new state (same type as `state`). The typechecker enforces exactly this: the `init` block must produce the declared state record, and every handler body is checked to *return* the state type — see the [typing reference](core-march-types.md) §2.6.1 for the precise checks the actor declaration performs (state-record construction, duplicate-handler rejection, message-constructor registration, `init`/handler conformance).

---

## Spawning Actors

`spawn` creates a new actor and returns its process identifier (`Pid`):

```march
fn main() do
  let counter = spawn(Counter)
  -- counter : Pid
end
```

`spawn(Name)` requires a **literal actor name** written directly — a computed
actor expression (from an `if`, `match`, or function call) is rejected at
compile time, because March resolves which actor to spawn statically from its
name. The typing account (including the subtlety that the resulting `Pid`'s type
parameter is a fresh variable, *not* the actor's state type) is in the
[typing reference](core-march-types.md) §2.6.2–§2.6.3; the runtime side (registering
an `actor_inst`, returning a `VPid`) is in [`core-march.md`](core-march.md) §4.10.1.

---

## Sending Messages

`send` delivers a message to an actor asynchronously:

```march
send(counter, Increment(10))
send(counter, Increment(5))
send(counter, Reset())
```

The message is the constructor applied to its arguments. The actor handles it according to its `on` clause.

**Message names share one flat global constructor namespace.** A handler `on Msg(…)`
registers `Msg` as an ordinary constructor — there is no per-actor message namespace,
exactly analogous to the [no-per-module-type-namespace design point](core-march-types.md)
(§2.5). So a message name that collides with a constructor another type (including a
stdlib type) already declares is ambiguous: writing `send(counter, Ping(…))` when the
stdlib also declares a `Ping` constructor is rejected (`Constructor \`Ping\` is defined by
multiple types … Use a qualified form to disambiguate`). Pick message names unlikely to
collide (e.g. `Increment`, `Poke`), or qualify. Two consequences of this design — the
compiled wrong-actor-`send` misroute and the payload-typing rule — are documented in the
[typing reference](core-march-types.md) §2.6.4.

`send` returns `Some(())` if the actor is alive, or `None` if the actor is dead:

```march
match send(counter, Increment(1)) do
  Some(_) -> println("message delivered")
  None    -> println("actor is dead")
end
```

> **Interp-vs-compiled note.** The dead-actor drop (`None`) is the *interpreter's*
> behavior; the compiled backend returns `Some` for a `send` to a dead pid (a filed
> divergence — [`core-march.md`](core-march.md) §4.10.6). A `send` to a *live* actor
> agrees on both backends. See §4.10.2 for the async-enqueue operational rule.

---

## Receiving Messages Inside a Handler

`receive()` blocks until the next message arrives in the actor's mailbox. Use it when a handler needs to wait for a sub-message before continuing:

Every message you `send` — including the follow-up a handler `receive()`s — must be a
**declared handler message**: the `Followup` message below is a valid constructor only
because the actor declares an `on Followup(n)` handler. (A message name with no matching
handler is not a registered constructor and is rejected at compile time.)

```march
actor Dispatcher do
  state { got : Int }
  init  { got: 0 }

  on Dispatch() do
    -- wait for the follow-up message already queued behind this one
    let follow = receive()
    match follow do
      Followup(n) -> { got: n }
      _           -> state
    end
  end

  on Followup(n : Int) do
    { got: n }
  end
end

fn main() do
  let pid = spawn(Dispatcher)
  send(pid, Dispatch())
  send(pid, Followup(99))   -- queued before Dispatch() is dispatched
  run_until_idle()
end
```

**Blocking semantics:** If the mailbox is empty when `receive()` is called, the actor parks (interpreter: re-queues the triggering message and retries the handler on a later pass; compiled: green thread parks). It resumes automatically once a message is delivered. `run_until_idle()` returns as soon as all actors are either idle or waiting — no deadlock. See [`core-march.md`](core-march.md) §4.10.3 for the pop-or-`BlockedOnReceive` rule.

**Once-per-handler limitation:** only the *first* `receive()` in a handler body is safe to block on — if a handler calls `receive()` twice and the second one blocks (empty mailbox), the message the first `receive()` already popped is lost (the scheduler's re-queue only restores the outer triggering message). A handler needing multiple messages should recurse, with each `receive()` the first operation in its own handler body. The example above `receive()`s exactly once, on an already-queued message, so it neither blocks nor trips this limitation. (This is what the golden witness `g36_actor_receive` pins.)

Messages are always delivered in FIFO order, so `receive()` pops the oldest queued message.

---

## Checking if an Actor is Alive

```march
let alive = is_alive(counter)
println("alive: " ++ bool_to_string(alive))
```

---

## Stopping an Actor

```march
kill(counter)
```

After `kill`, `is_alive(counter)` returns `false` and further `send`s return `None`
(interpreted — see the dead-`send` note above). `is_alive` is a pure registry lookup and
is the one lifecycle observation that is **byte-identical interpreted vs compiled** (the
golden witness `g37_actor_lifecycle` pins `spawn → is_alive true → kill → is_alive false`).
The operational rules for `kill`/`is_alive` are in [`core-march.md`](core-march.md) §4.10.6.

---

## Capability-Based Messaging

For supervision-safe message delivery, use capabilities (`Cap`). A capability encodes the actor's identity and current *epoch* — it becomes stale (and is rejected) if the actor restarts:

```march
-- Obtain a capability for a live actor
match get_cap(pid) do
  None      -> println("actor is dead")
  Some(cap) ->
    -- send_checked validates the epoch before delivering
    match send_checked(cap, Increment(1)) do
      :ok    -> println("delivered")
      _      -> println("actor dead or cap stale")   -- :error or, compiled, a garbage atom
    end
end
```

Use capabilities when you hold a reference across an actor restart boundary and need to know whether the message was delivered to the *current* incarnation of the actor. Under a supervisor, a restarted actor gets a fresh epoch, invalidating caps from before the restart.

> **Interpreter-only.** The epoch-`Cap` validation plane described here is the
> **interpreter's** semantics. Compiled, `send_checked` performs *no* epoch validation and
> returns an uninterned garbage atom for every cap — matching neither `:ok` nor `:error`
> (hence the `_` catch-all above rather than a `:error` arm) — and `get_cap` does not gate
> on liveness. The entire capability mechanism is therefore non-functional in compiled
> binaries today; it is a filed open finding ([`core-march.md`](core-march.md) §4.10.6, and
> `specs/todos.md`). Two of the underlying builtins, `revoke_cap` and `is_cap_valid`, are
> additionally not registered in the typechecker, so they are not surface-callable at all.
> Use plain `send`/`is_alive` if you need behavior that agrees on both backends.

---

## Synchronous Request-Reply via `Actor.call`

The `Actor` module provides a synchronous call pattern. You pass a **zero-arg
sentinel constructor** as the call message; its tag selects which handler receives
the call, and the runtime injects the caller (the *reply channel*) as that handler's
**first argument**. The handler answers with `Actor.reply`:

```march
type GetReq = GetReq          -- zero-arg sentinel for the sync call

actor Counter do
  state { count : Int }
  init  { count: 0 }

  -- First handler (tag 0) = the call handler; reply_to is the caller.
  on GetCount(reply_to) do
    Actor.reply(reply_to, state.count)
    state
  end

  on Inc(n : Int) do
    { state with count: state.count + n }
  end
end

fn main() do
  let pid = spawn(Counter)
  Actor.cast(pid, Inc(1))
  run_until_idle()
  match Actor.call(pid, GetReq, 5000) do
    Ok(n)  -> println("count = " ++ int_to_string(n))
    Err(e) -> println("error: " ++ e)
  end
end
```

This program prints `count = 1` interpreted (compiled, it currently prints a wrong value — see
the note below). `Actor.call(pid, sentinel, timeout_ms)`
reads the tag from the zero-arg `sentinel`, builds an augmented message (same tag,
with the caller in field 0), and routes it to the handler at that tag. That handler
receives the caller as its first argument and must call `Actor.reply(reply_to, result)`
to unblock the caller. `Actor.call` returns `Ok(result)`, or `Err(reason)` if no reply
arrives.

Two consequences of the tag-selects-the-handler rule:

- **The call handler must be declared FIRST** in the actor, so it sits at tag 0 — the
  sentinel `GetReq` has tag 0, and that is the handler the call routes to.
- **The sentinel must have a name distinct from the handler** (`GetReq` vs `GetCount`)
  to avoid a constructor-name clash.

There is no `Call` wrapper constructor, and the call handler takes exactly one argument
(the reply channel).

> **Two notes (both resolved 2026-07-13).** (1) `timeout_ms` **is enforced in the
> compiled runtime** via a deadline-bounded yield-poll (`march_actor_call`,
> `runtime/march_runtime.c`); a `call` that never receives a reply returns `Err(...)`
> once the deadline passes, and `timeout_ms <= 0` means wait forever. Known caveat: a
> late reply arriving after the timeout still lands in the caller's mailbox — safe for
> per-call task green threads (the thread exits and sends to dead procs are dropped),
> but a long-lived green thread mixing `Actor.call` and raw `receive` could observe a
> stale reply after a timeout. (2) The **interpreter now dispatches `Actor.call`
> identically to the compiled runtime**: it tag-routes the zero-arg sentinel to the
> handler at the same ctor index and binds the caller as the handler's single argument
> (`lib/eval/eval.ml` `actor_call`). The historical interp-only `on Call(ref, msg)`
> two-argument form is retired. Both behaviors are pinned by the
> `test/native/actor_counter` and `test/native/actor_call_timeout` goldens, which are
> intended to pass on both backends.
>
> **Newly observed compiled-only regression (found verifying this chapter, 2026-07-22):**
> the pinned `test/native/actor_counter` golden itself currently fails compiled — it
> prints `value=11` where `test/native/actor_counter.expected` pins `value=5` (interpreted
> still prints `value=5` correctly). The wrong value is consistently `2n + 1` for the true
> `Int` result `n` (e.g. an actor state of `0` reports as `1`, `5` reports as `11`), which
> looks like the compiled `Actor.call`/`Actor.reply` return path handing back a raw tagged
> fixnum instead of untagging it before use. This is a compiler/runtime bug, not a docs
> issue — filed for follow-up investigation rather than fixed here.

`Actor.cast(pid, msg)` is fire-and-forget — equivalent to `send` but goes through the `Actor` module.

---

## A Complete Actor Example

```march
mod ActorDemo do

  actor Counter do
    state { value : Int }
    init  { value: 0 }

    on Increment(n : Int) do
      { state with value: state.value + n }
    end

    on Poke(label : String) do
      println("[Counter] poke from " ++ label
              ++ ", value = " ++ int_to_string(state.value))
      state
    end
  end

  actor Logger do
    state { count : Int }
    init  { count: 0 }

    on Log(msg : String) do
      let n = state.count + 1
      println("[LOG #" ++ int_to_string(n) ++ "] " ++ msg)
      { state with count: n }
    end
  end

  fn main() do
    let counter = spawn(Counter)
    let logger  = spawn(Logger)

    send(counter, Increment(10))
    send(logger,  Log("counter incremented by 10"))
    send(counter, Increment(5))
    send(counter, Poke("main"))

    kill(logger)
    println("logger alive: " ++ bool_to_string(is_alive(logger)))

    match send(logger, Log("dropped")) do
      None    -> println("message dropped — actor is dead")
      Some(_) -> ()
    end

    send(counter, Poke("after kill"))
    run_until_idle()
  end

end
```

(This example uses the message name `Poke` rather than `Ping`: `Ping` collides with a
stdlib constructor in the flat global namespace — see the note under *Sending Messages*.
Interpreted, it prints `logger alive: false`, `message dropped — actor is dead`, then
`[Counter] poke from main, value = 15` and `[Counter] poke from after kill, value = 15`.
It uses only the live-message + `kill`/`is_alive` plane, so it is byte-identical compiled.)

---

## Actor State with Records

Complex state uses record types. Functional update with `{ state with field: new_value }` is the canonical way to update state:

```march
actor WebServer do
  state {
    request_count : Int,
    error_count   : Int,
    last_path     : String
  }
  init {
    request_count: 0,
    error_count:   0,
    last_path:     ""
  }

  on Req(path : String, status : Int) do
    let rc = state.request_count + 1
    let ec = if status >= 400 do state.error_count + 1 else state.error_count end
    { state with
        request_count: rc,
        error_count:   ec,
        last_path:     path }
  end

  on Stats() do
    println("requests: " ++ int_to_string(state.request_count))
    println("errors: "   ++ int_to_string(state.error_count))
    state
  end
end
```

(This example uses the message name `Req` rather than `Request`: `Request` collides with the
stdlib `Http.Request` constructor in the flat global namespace — see the note under *Sending
Messages*.)

---

## Tasks: Lightweight Concurrent Computations

Tasks are a simpler alternative to actors when you just need to run a function concurrently and collect its result. Use the `Task` module:

```march
-- Spawn a task and await its result
let t = Task.async(fn () -> expensive_computation())
let result = Task.await(t)   -- Ok(value) or Err(reason)

-- Parallel map
let results = Task.async_stream([1, 2, 3], fn n -> n * n)
-- [Ok(1), Ok(4), Ok(9)]

-- Await multiple tasks
let t1 = Task.async(fn () -> fetch_user(1))
let t2 = Task.async(fn () -> fetch_user(2))
let [r1, r2] = Task.await_many([t1, t2])

-- Unwrap directly (panics on error)
let value = Task.await!(t)
```

Tasks run on the same M:N green-thread pool as actors. Spawning 250,000+ tasks is routine; the scheduler distributes them across OS threads automatically.

See the [Task module docs](/docs/stdlib/Task.html) for the full API including `Task.race`, `Task.any`, `Task.scope`, and `Task.all_settled`.

To run a transformation over a whole collection in parallel without wiring up tasks by hand, use the data-parallel `List` operations (`pmap`, `pmap_n`, `pfilter`, `preduce`) — see [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/).

---

## Running Until Idle

In scripts and tests, `run_until_idle()` processes all pending actor messages before continuing:

```march
fn main() do
  let counter = spawn(Counter)
  send(counter, Increment(1))
  send(counter, Increment(2))
  send(counter, Increment(3))
  run_until_idle()
  -- All three messages are processed here
  send(counter, Poke("done"))
  run_until_idle()
end
```

In long-running applications, the scheduler runs automatically — you do not call `run_until_idle()`. `run_until_idle()` drains the scheduler to a fixed point (every mailbox empty); its operational rule is in [`core-march.md`](core-march.md) §4.10.4, and the determinism property it enables — interleaving-free output byte-identical interpreted vs compiled — is §4.10.5.

---

## Actor Identity: `self()`

Inside a handler, `self()` returns the current actor's `Pid`. Useful for passing yourself as a reply address:

```march
on Request(question : String, caller) do
  let answer = compute_answer(question)
  send(caller, Answer(answer, self()))
  state
end
```

(`caller` is left unannotated rather than written `caller : Pid`, and `Answer`'s payload here is
left untyped rather than declared as carrying a `Pid` field. Two current compiler gaps make
explicit `Pid` typing around `self()` unreliable: (1) `self()`'s builtin signature is registered
as plain `Int`, not `Pid(a)` (`lib/typecheck/typecheck.ml` — `("self", Mono t_int)`), so
`self()`'s result fails to unify anywhere a `Pid`-typed field or argument is expected (e.g.
`is_alive(self())`, or a message field explicitly annotated `: Pid`) with a confusing `expected
Pid but got Int`, even though it dynamically **is** a valid Pid; (2) a bare `Pid` annotation (no
type parameter) is separately unreliable because it can resolve against the unrelated
`GlobalPid.Pid` record type sharing the same bare name in the flat global namespace, rather than
the parametric actor `Pid(a)` that `spawn`/`self()` actually produce. Leaving `caller` and the
reply payload unannotated and letting them infer sidesteps both gaps — the pattern used elsewhere
in this chapter, e.g. `on GetCount(reply_to)`. These are compiler typing gaps, not docs issues;
noted here for a follow-up fix.)

---

## App Entry Point

For long-running applications, use `app` instead of (or alongside) `main`:

```march
mod MyService do
  actor Worker do
    state { count : Int }
    init  { count: 0 }
    on Tick() do { state with count: state.count + 1 } end
  end

  app MyService do
    Supervisor.spec(:one_for_one, [worker(Worker)])
  end
end
```

The `app` declaration integrates with the supervision system. See [Supervision](supervision.md) for the tutorial, and [`core-march.md`](core-march.md) §4.10.7 for the operational rules of `one_for_one` restart and epoch invalidation.

> **Supervision observation is interp-only compiled today.** The `one_for_one` restart
> semantics are correct interpreted, but the only surface way to reach a supervised child
> — reading its pid out of the supervisor state via `get_actor_field(sup, …)` +
> `pid_of_int(…)` — **SIGSEGVs compiled** (`examples/supervision_strategies.march` exits
> 139), and the compiled supervisor does not even run its children's `init` at
> `spawn(Sup)`. Both are filed open findings (`specs/todos.md`). Supervised-actor programs
> run correctly under the interpreter; treat compiled supervision as not-yet-observable.

---

## Choosing a concurrency primitive

March gives you several concurrency tools, and they all run on the **same M:N green-thread scheduler** — the choice is about *shape of problem*, not about performance tiers. One mental model to keep them straight:

> **Actors** = identity + state + mailbox. **Tasks** = structured fork/join. **Flow** = bounded streaming. **`pmap`** = data-parallel collections. **Session channels** = a typed two-party conversation.

Pick by what you need:

| If you need… | Reach for | Why |
|---|---|---|
| A long-lived stateful entity many parties talk to (counter, connection, cache) | **actor** (`spawn` / `send`) | Identity + private state + a mailbox; survives across messages and restarts |
| To fan out independent work and collect *all* the results | **`Task.async`** + **`Task.await_many`** | Structured fork/join; you await every task |
| The *first* result and want to cancel the losers | **`Task.race`** / **`Task.any`** | Returns as soon as one finishes (`any` = first success; `race` = first to settle) |
| Fork tasks that are guaranteed to be cleaned up when the block exits | **`Task.scope`** | Structured concurrency — no task outlives its scope |
| To transform a whole list across cores, identical result to `map` | **`List.pmap`** / **`pmap_n`** | Data-parallel; `pmap_n` bounds concurrency for expensive items |
| A multi-stage stream where one stage can fall behind a fast producer | **`Flow`** | Backpressure — the consumer's demand caps how far the producer runs ahead |
| A strict two-party protocol whose message *order* the compiler should enforce | **session channels** (`Chan.*`) | Linear, typed conversation; wrong-order/use-after-close are compile errors |
| Raw, un-managed green-thread spawn (you handle joining yourself) | **`task_spawn`** | The low-level primitive `Task.*` is built on — prefer `Task.*` |

Rules of thumb:

- **Default to `Task.async` / `await_many`** for "do these N things concurrently, give me the answers." It's the simplest structured option.
- **Default to an actor** the moment there's *mutable state with an identity* — something that several callers update over time.
- **Choose `Flow` over an unbounded `Task.async_stream`** when a fast producer could overwhelm a slow downstream stage and pile up in-flight work. See [Flow & Backpressure]({{ site.baseurl }}/docs/flow/).
- **Choose `pmap` over hand-wired tasks** when the input is a list, items are independent, and you want the order-preserving, threshold-managed convenience. See [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/).
- **Choose session channels over a bare actor** when two parties run a fixed protocol and ordering correctness matters. See [Session Types]({{ site.baseurl }}/docs/session-types/).

---

## Builtins Reference

Backends: **both** = byte-identical interpreted vs compiled (the live-message plane);
**interp-only** = correct interpreted, but diverges or crashes compiled (a filed finding).

| Builtin | Signature | Backends | Description |
|---------|-----------|----------|-------------|
| `spawn(Actor)` | `→ Pid` | both | Start a new actor (literal actor name only) |
| `send(pid, msg)` | `→ Option(())` | both (live) | Send a message; `None` if actor is dead **interpreted** — compiled returns `Some` for a dead pid (§4.10.6 finding) |
| `receive()` | `→ Msg` | both | Pop the next mailbox message (only the first `receive()` per handler may block) |
| `kill(pid)` | `→ ()` | both | Stop an actor |
| `is_alive(pid)` | `→ Bool` | both | Check if actor is running (registry lookup, safe compiled) |
| `self()` | `→ Pid` | both | Current actor's Pid |
| `run_until_idle()` | `→ ()` | both | Drain the scheduler to a fixed point (interpreter / tests) |
| `get_cap(pid)` | `→ Option(Cap(Msg))` | interp-only | Obtain an epoch-tagged capability (compiled `get_cap` does not gate on liveness) |
| `send_checked(cap, msg)` | `→ :ok \| :error` | interp-only | Epoch-validated send; **non-functional compiled** — returns a garbage atom for every cap (§4.10.6 finding) |
| `pid_of_int(n)` | `→ Pid` | interp-only | Convert Int to Pid — **SIGSEGVs compiled** (unsafe int→ptr cast, §4.10.7 finding) |
| `get_actor_field(pid, name)` | `→ Option(a)` | interp-only | Read an actor's state field — **crashes compiled** (hard stub returns `None`, then a deref SIGSEGVs, §4.10.7 finding) |
| `task_spawn(fn)` | `→ Task(a)` | both | Spawn a green-thread task (use `Task.async` instead) |
| `task_await(t)` | `→ Result(a, String)` | both | Await a task (use `Task.await` instead) |

---

## Next Steps

The concurrency and distribution docs form a journey — actors are the foundation; each step below builds on them:

- [Supervision Trees]({{ site.baseurl }}/docs/supervision/) — fault-tolerant hierarchies with automatic restart, ending in a capstone crash-tolerant job processor.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/) — `pmap` / `pmap_n` for data-parallel work on the same scheduler.
- [Flow & Backpressure]({{ site.baseurl }}/docs/flow/) — bounded streaming pipelines when a fast producer outruns a slow consumer.
- [Session Types]({{ site.baseurl }}/docs/session-types/) — typed two-party protocols whose message order the compiler enforces.
- [Clustering & RPC]({{ site.baseurl }}/docs/clustering/) — take a supervised actor app from one node to a cluster with cross-node calls.
- [Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/) — deploy new code to a running server without restarting; actors migrate their state on the fly.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/) — how linear types interact with message passing.
- [Task stdlib]({{ site.baseurl }}/docs/stdlib/Task.html) — full Task API reference.
