---
layout: docs
title: Actors
nav_order: 9
permalink: /docs/actors/
---

# Actors

March's concurrency model is built on **actors** and **tasks**. Actors are isolated processes that communicate exclusively through message passing: no shared mutable state. Tasks are lightweight one-off computations that run concurrently and return a value. Both run whether you use the interpreter or compile to a native binary.

Most of what's on this page (spawning, sending, receiving, checking liveness, killing, and request-reply built on plain `send`) behaves identically either way. Only a few newer conveniences diverge on the compiled backend: **capability-based messaging** (`get_cap`/`send_checked`), **reading a supervised actor's state from outside** (`get_actor_field`/`pid_of_int`), and **`Actor.call`'s return value**. Those are the compiled-backend gaps; each is called out where it matters below, and all three are collected in one place in the [Builtins Reference](#builtins-reference) table. Where a gap affects a pattern you need compiled, the portable alternative is given right there (for synchronous calls, see [Request-Reply That Works Compiled](#request-reply-that-works-compiled)).

---

## Defining an Actor

An actor declaration has three parts:
- `state { ... }`: the state record type
- `init { ... }`: the initial state value
- `on Msg(...) do ... end`: message handlers, each returning the new state

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

Inside a handler, `state` refers to the current state record. Each handler must return the new state (same type as `state`); the compiler checks that `init` produces the declared state record and that every handler body returns that same type.

---

## Spawning Actors

`spawn` creates a new actor and returns its process identifier (`Pid`):

```march
fn main() do
  let counter = spawn(Counter)
  -- counter : Pid
end
```

`spawn(Name)` requires a **literal actor name** written directly; a computed actor expression (from an `if`, `match`, or function call) is rejected at compile time, because March resolves which actor to spawn statically from its name.

---

## Sending Messages

`send` delivers a message to an actor asynchronously:

```march
send(counter, Increment(10))
send(counter, Increment(5))
send(counter, Reset())
```

The message is the constructor applied to its arguments. The actor handles it according to its `on` clause.

**Message names share one flat global constructor namespace.** A handler `on Msg(…)` registers `Msg` as an ordinary constructor; there is no per-actor message namespace. So a message name that collides with a constructor another type (including a stdlib type) already declares is ambiguous: writing `send(counter, Ping(…))` when the stdlib also declares a `Ping` constructor is rejected (`Constructor \`Ping\` is defined by multiple types … Use a qualified form to disambiguate`). Pick message names unlikely to collide (e.g. `Increment`, `Poke`), or qualify.

`send` returns `Some(())` if the actor is alive, or `None` if the actor is dead (interpreted; the compiled backend currently returns `Some` even for a dead pid, a known divergence):

```march
match send(counter, Increment(1)) do
  Some(_) -> println("message delivered")
  None    -> println("actor is dead")
end
```

---

## Receiving Messages Inside a Handler

`receive()` blocks until the next message arrives in the actor's mailbox. Use it when a handler needs to wait for a sub-message before continuing:

Every message you `send` (including the follow-up a handler `receive()`s) must be a
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

**Blocking semantics:** If the mailbox is empty when `receive()` is called, the actor parks and resumes automatically once a message is delivered. `run_until_idle()` returns as soon as all actors are either idle or waiting: no deadlock.

**Once-per-handler limitation:** only the *first* `receive()` in a handler body is safe to block on: if a handler calls `receive()` twice and the second one blocks (empty mailbox), the message the first `receive()` already popped is lost. A handler needing multiple messages should recurse, with each `receive()` the first operation in its own handler body. The example above `receive()`s exactly once, on an already-queued message, so it doesn't trip this limitation.

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

After `kill`, `is_alive(counter)` returns `false` and further `send`s return `None` (interpreted; see the dead-`send` note above).

## Monitoring Actor Death

`monitor(watcher, target)` delivers a control-plane `Down(ref, target_pid, reason)`
message to `watcher` when `target` terminates. The local reasons are `Normal`,
`Killed`, and `Crash(message)`. Match the three fields in a handler rather than
treating a monitor as a count of dead actors:

```march
actor Watcher do
  state { seen : Int }
  init  { seen: 0 }

  on CheckDown() do
    match receive() do
      Down(_, target, Normal) ->
        println("stopped " ++ to_string(target))
        state
      Down(_, target, Killed) ->
        println("killed " ++ to_string(target))
        state
      Down(_, _, Crash(error)) ->
        println("crashed " ++ error)
        state
      _ ->
        println("unexpected monitor message")
        state
    end
  end
end
```

Monitor `Down` messages are control-plane delivery: they bypass the target
watcher's mailbox limit, so a full bounded mailbox cannot lose the death
notification. Local monitoring has the same payload and reason vocabulary on
the interpreted and compiled backends; the distributed monitor protocol uses
the same `Down(ref, target_pid, reason)` shape (and additionally has `NodeDown`).

### Why there are no links

March's fault model is **monitors plus supervisors**, not BEAM's links and exit
signals. A monitor is one-directional and observational: the watcher receives
`Down(ref, pid, reason)` where the reason is `Normal`, `Killed`, or `Crash(msg)`, and
determines for itself what to do. Failure propagates *downward* through supervision
trees, never sideways between actor peers.

This is the same choice Akka made in dropping links for DeathWatch plus
supervision strategies. A reason-carrying `Down` gives a watcher everything a
link's exit signal would have told it, without the bidirectional coupling, and
without needing a `trap_exit` escape hatch to make that coupling survivable.

One asymmetric edge remains: `task_spawn_link` links a plain task to an actor,
and if the task's thunk raises, the linked actor is crashed: a task-to-actor
propagation path, not an actor-to-actor one. It is a narrower primitive than a
BEAM link (a task cannot itself be linked to or crashed by anything), so it
doesn't reopen the sideways-coupling problem this section argues against.

---

## Named Actors

A Pid is not stable. When a supervisor restarts a crashed child, the replacement gets a
*new* Pid, and everyone still holding the old one is talking to a corpse. The named
registry hands out a stable string name instead:

```march
mod Main do
  needs IO.Console

  actor Counter do
    state { n : Int }
    init  { n: 0 }
    on Bump() do { n: state.n + 1 } end
  end

  fn main(_c : Cap(IO.Console)) do
    let pid = spawn(Counter)
    println("registered: " ++ bool_to_string(Actor.register(pid, "counter")))
    println("names: " ++ int_to_string(List.length(Actor.registered())))

    -- Resolve the name once, then reuse the Pid for the whole burst.
    match Actor.whereis("counter") do
      None -> println("counter is unavailable right now — retry")
      Some(here) ->
        let _ = send(here, Bump())
        let _ = send(here, Bump())
        println("sent")
    end

    println("unregistered: " ++ bool_to_string(Actor.unregister("counter")))
  end
end
```

| Function | Returns | Description |
|----------|---------|-------------|
| `Actor.register(pid, name)` | `Bool` | Bind `name` to `pid`. `false` if `pid` is already dead, or if `name` is currently held by a *live* actor. |
| `Actor.unregister(name)` | `Bool` | Release the name. `false` if it was not registered. |
| `Actor.whereis(name)` | `Option(Pid)` | The actor currently holding `name`. |
| `Actor.registered()` | `List(String)` | Every name currently bound; order unspecified. |

A name is released automatically when its actor dies, so a name never resolves to a dead
Pid and you do not have to unregister from a crash path.

`whereis` returns an `Option` because a name can be *momentarily* unresolvable. While a
supervised child is being respawned (in particular while it waits out its restart backoff)
the old actor is gone and its replacement does not exist yet. `None` there is the accurate
signal that the service is mid-restart, not that the name was never registered; retry
rather than treating it as a permanent error.

Names survive supervisor restarts, on **both** backends: the crashing child's names are
brought forward and re-established on its replacement, so a holder outside the supervision
tree keeps reaching whichever incarnation is current without at any point learning the new Pid.
**Hold names, not Pids, across a restart boundary.** This includes a live sibling killed by
a `one_for_all` / `rest_for_one` batch restart, not only the child that actually crashed.
If a *different* live actor claims the name during the restart window, the carried-forward
registration is dropped for that name rather than stolen back. Unsupervised actors are
unaffected; their names are simply dropped on death.

On a hot path, resolve a name **once and cache the Pid** instead of calling `whereis` per
message. Concurrent lookups of the *same* name all bump the refcount on the one stored
value, and that contention, not the registry's table lock, is what bounds same-name
resolution; `send` itself takes no registry lock. Re-resolve when a send fails or a monitor
fires, not on every message.

---

## Capability-Based Messaging

For supervision-safe message delivery, use capabilities (`Cap`). A capability encodes the actor's identity and current *epoch*: it becomes stale (and is rejected) if the actor restarts:

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

> **Interpreter-only, today.** Capability validation (`get_cap`, `send_checked`) only works
> correctly under the interpreter; in a compiled binary `send_checked` doesn't validate the
> epoch at all and returns a value that matches neither `:ok` nor `:error` (hence the `_`
> catch-all above). `revoke_cap` and `is_cap_valid` aren't callable yet on either backend.
> If you need behavior that's reliable compiled, use plain `send`/`is_alive` instead.

---

## Request-Reply That Works Compiled

`Actor.call` (below) now works correctly on both backends; its return value bug was
fixed 2026-07-22. This lower-level pattern (pass a reply address and get the answer back
as an ordinary message) is still worth knowing: it's built entirely from `send`, which
behaves identically interpreted and compiled, and it's the right choice when a handler
needs to reply to more than one caller or reply asynchronously outside the call/timeout
protocol.

The requester includes its own `Pid` (from `self()`) in the message; the handler replies
with a plain `send` to that address:

```march
on Ask(question : String, reply_to) do
  send(reply_to, Answer(compute_answer(question)))
  state
end
```

The caller (itself an actor, or the top-level process) handles the `Answer(...)` reply
in its own `on` clause (this is the same reply-address idea as [`self()`](#actor-identity-self)).
`Actor.call` (below) covers the common single-request/single-reply case on both backends;
reach for this pattern instead when you need more flexibility than a one-shot call.

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

This program prints `count = 1` on both backends. `Actor.call(pid, sentinel,
timeout_ms)` reads the tag from the zero-arg `sentinel`, builds an augmented message
(same tag, with the caller in field 0), and routes it to the handler at that tag.
That handler receives the caller as its first argument and must call
`Actor.reply(reply_to, result)` to unblock the caller. `Actor.call` returns
`Ok(result)`, or `Err(reason)` if no reply arrives before `timeout_ms` (a value
`<= 0` means wait indefinitely).

Two consequences of the tag-selects-the-handler rule:

- **The call handler must be declared FIRST** in the actor, so it sits at tag 0: the
  sentinel `GetReq` has tag 0, and that is the handler the call routes to.
- **The sentinel must have a name distinct from the handler** (`GetReq` vs `GetCount`)
  to avoid a constructor-name clash.

There is no `Call` wrapper constructor, and the call handler takes exactly one argument
(the reply channel).

> **Timeout and correlation semantics (compiled).** `timeout_ms` is enforced via a
> deadline-bounded park; the caller's green thread parks on the scheduler rather than
> busy-polling, and wakes either on reply delivery or at the deadline. Every reply is
> wrapped with the correlation id issued for that specific call; a reply that arrives
> after its call has already timed out (or that belongs to some earlier call) is detected
> by its stale correlation id and dropped instead of being passed back as the answer to
> an unrelated later call. `timeout_ms <= 0` waits indefinitely.

`Actor.cast(pid, msg)` is fire-and-forget: equivalent to `send` but goes through the `Actor` module.

---

## A Complete Actor Example

```march
mod ActorDemo do
  needs IO.Console

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
stdlib constructor in the flat global namespace; see the note under *Sending Messages*.
It prints `logger alive: false`, `message dropped — actor is dead`, then
`[Counter] poke from main, value = 15` and `[Counter] poke from after kill, value = 15`;
the same on both backends, since it only uses plain `send`/`kill`/`is_alive`.)

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
stdlib `Http.Request` constructor in the flat global namespace; see the note under *Sending
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

Tasks run on the same green-thread pool as actors, spread automatically across OS threads. Spawning 250,000+ tasks is routine.

See the [Task module docs](/docs/stdlib/Task.html) for the full API including `Task.race`, `Task.any`, `Task.scope`, and `Task.all_settled`.

To run a transformation over a whole collection in parallel without wiring up tasks by hand, use the data-parallel `List` operations (`pmap`, `pmap_n`, `pfilter`, `preduce`); see [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/).

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

In long-running applications, the scheduler runs automatically; you do not call `run_until_idle()`. It exists for scripts and tests, where you want a deterministic point at which every actor mailbox has been drained.

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

One gotcha: a bare `Pid` annotation with no type parameter can resolve against an unrelated
`GlobalPid.Pid` record type that happens to share the same bare name, rather than the actor
`Pid(a)` that `spawn`/`self()` actually produce. Leaving `caller` and reply payloads
unannotated, as in the example above, sidesteps this.

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

**How this relates to the `supervise` block.** These are two spellings of the same idea.
The `supervise do strategy one_for_one … Child field end` block you put *inside an
ordinary actor* (see [Supervision Trees]({{ site.baseurl }}/docs/supervision/)) declares
that actor's supervised children with a small DSL. An `app` body instead evaluates to a
`Supervisor.Spec` **value**: `Supervisor.spec(:one_for_one, [worker(Worker), …])` is the
value-level counterpart of that block, and it defines the application's single top-level
supervisor. Note the two surfaces spell the strategy differently: a bare `one_for_one` in
the `supervise` block versus the atom `:one_for_one` passed to `Supervisor.spec`. Reach
for `supervise` to give an actor children; reach for `app` to declare the root of a
long-running application. See [Supervision Trees]({{ site.baseurl }}/docs/supervision/)
for the full tutorial.

> **Reading a supervised child's state is interpreter-only, today.** Restart itself
> (`one_for_one` etc.) is correct on both backends. But the only way to reach a supervised
> child from outside (`get_actor_field(sup, …)` + `pid_of_int(…)`) crashes in a compiled
> binary, which also skips running a child's `init` at `spawn(Sup)`. Supervised-actor
> programs run correctly under the interpreter; treat compiled supervision as
> not-yet-observable from outside the tree.

---

## Choosing a concurrency primitive

March gives you several concurrency tools, and they all run on the **same green-thread scheduler**; the choice is about *shape of problem*, not about performance tiers. One mental model to keep them straight:

> **Actors** = identity + state + mailbox. **Tasks** = structured fork/join. **Flow** = bounded streaming. **`pmap`** = data-parallel collections. **Session channels** = a typed two-party conversation.

Pick by what you need:

| If you need… | Reach for | Why |
|---|---|---|
| A long-lived stateful entity many parties talk to (counter, connection, cache) | **actor** (`spawn` / `send`) | Identity + private state + a mailbox; persists across messages and restarts |
| To fan out independent work and collect *all* the results | **`Task.async`** + **`Task.await_many`** | Structured fork/join; you await every task |
| The *first* result and want to cancel the losers | **`Task.race`** / **`Task.any`** | Returns as soon as one finishes (`any` = first success; `race` = first to settle) |
| Fork tasks that are guaranteed to be cleaned up when the block exits | **`Task.scope`** | Structured concurrency: no task outlives its scope |
| To transform a whole list across cores, identical result to `map` | **`List.pmap`** / **`pmap_n`** | Data-parallel; `pmap_n` bounds concurrency for expensive items |
| A multi-stage stream where one stage can fall behind a fast producer | **`Flow`** | Backpressure: the consumer's demand caps how far the producer runs ahead |
| A strict two-party protocol with a message *order* the compiler should enforce | **session channels** (`Chan.*`) | Linear, typed conversation; wrong-order/use-after-close are compile errors |
| Raw, un-managed green-thread spawn (you handle joining yourself) | **`task_spawn`** | The low-level primitive `Task.*` is built on; prefer `Task.*` |

Rules of thumb:

- **Default to `Task.async` / `await_many`** for "do these N things concurrently, give me the answers." It's the simplest structured option.
- **Default to an actor** the moment there's *mutable state with an identity*: something that several callers update over time.
- **Choose `Flow` over an unbounded `Task.async_stream`** when a fast producer could overwhelm a slow downstream stage and pile up in-flight work. See [Flow & Backpressure]({{ site.baseurl }}/docs/flow/).
- **Choose `pmap` over hand-wired tasks** when the input is a list, items are independent, and you want the order-preserving, threshold-managed convenience. See [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/).
- **Choose session channels over a bare actor** when two parties run a fixed protocol and ordering correctness matters. See [Session Types]({{ site.baseurl }}/docs/session-types/).

---

## Mailbox Limits and Backpressure

By default an actor's mailbox is unbounded; a producer that outruns its consumer grows
the mailbox without limit. `Actor.set_queue_limit(pid, limit, policy)` bounds it:

```march
Actor.set_queue_limit(pid, 1000, 3)   -- cap at 1000, block_sender policy
```

`policy` is one of:

| Value | Policy | Behavior when the mailbox is full |
|-------|--------|------------------------------------|
| `0` | unbounded (default) | never rejects |
| `1` | `drop_new` | the incoming message is discarded |
| `2` | `drop_old` | the oldest queued message is evicted to make room |
| `3` | `block_sender` | the sender parks until space frees up (compiled backend only) |

Dropped messages (policies `1`/`2`) are counted in `Scheduler.dropped_messages()`. The
interpreter's single-threaded eager scheduler cannot park a sender without deadlocking, so
it treats policy `3` the same as `0` (unbounded).

Under a drop policy, a dropped `Actor.call` request or its reply is impossible to tell from
a lost reply at the caller; both surface as a timeout `Err` from `Actor.call`. Callers
that rely on `Actor.call` against a bounded actor should prefer the `block_sender` policy
(`3`) instead, so no request or reply is silently dropped at any point.

---

## Scheduler Observability

The `Scheduler` module exposes runtime counters for load-shedding decisions: a
supervisor or ingress actor can poll them to decide when to shed:

```march
if Scheduler.live_procs() > 10000 do
  println("shedding: too many live actors")
else
  dispatch_work()
end
```

| Function | Returns | Description |
|----------|---------|-------------|
| `Scheduler.live_procs()` | `Int` | Green-thread processes currently alive (actors + tasks + main) |
| `Scheduler.total_spawned()` | `Int` | Processes spawned over the whole program lifetime |
| `Scheduler.runq_depth()` | `Int` | Cross-thread global run-queue depth (instantaneous) |
| `Scheduler.dropped_messages()` | `Int` | Messages dropped by bounded-mailbox overflow policies |
| `Scheduler.stat(i)` | `Int` | Raw stat by index (`0`=live procs, `1`=total spawned, `2`=runq depth, `3`=stack-alloc failures, `4`=dropped messages, `5`=stacks recycled, `6`=pending timers; unknown index reads `0`) |

The interpreted backend reports the subset that's meaningful without the C scheduler
(live actor count); everything else reads `0` on both backends rather than erroring.

---

## Builtins Reference

Backends: **both** = works the same interpreted and compiled; **interpreter-only** = correct
under the interpreter, but broken or unreliable compiled today.

| Builtin | Signature | Backends | Description |
|---------|-----------|----------|-------------|
| `spawn(Actor)` | `→ Pid` | both | Start a new actor (literal actor name only) |
| `send(pid, msg)` | `→ Option(())` | both (live actors) | Send a message; `None` if actor is dead **interpreted**; compiled returns `Some` for a dead pid |
| `receive()` | `→ Msg` | both | Pop the next mailbox message (only the first `receive()` per handler may block) |
| `kill(pid)` | `→ ()` | both | Stop an actor |
| `is_alive(pid)` | `→ Bool` | both | Check if actor is running |
| `monitor(watcher, target)` | `→ Int` | both | Deliver `Down(ref, target_pid, reason)` on target exit; local reasons are `Normal`, `Killed`, and `Crash(String)` |
| `self()` | `→ Pid` | both | Current actor's Pid |
| `run_until_idle()` | `→ ()` | both | Drain the scheduler to a fixed point (interpreter / tests) |
| `get_cap(pid)` | `→ Option(Cap(Msg))` | interpreter-only | Obtain an epoch-tagged capability |
| `send_checked(cap, msg)` | `→ :ok \| :error` | interpreter-only | Epoch-validated send; compiled, returns a value that matches neither arm |
| `pid_of_int(n)` | `→ Pid` | interpreter-only | Convert Int to Pid; crashes compiled |
| `get_actor_field(pid, name)` | `→ Option(a)` | interpreter-only | Read an actor's state field from outside; crashes compiled |
| `task_spawn(fn)` | `→ Task(a)` | both | Spawn a green-thread task (use `Task.async` instead) |
| `task_await(t)` | `→ Result(a, String)` | both | Await a task (use `Task.await` instead) |
| `Actor.set_queue_limit(pid, limit, policy)` | `→ ()` | both (policy `3` is compiled-only; interpreted treats it as unbounded) | Bound an actor's mailbox; see [Mailbox Limits and Backpressure](#mailbox-limits-and-backpressure) |
| `Actor.send_after(pid, msg, delay_ms)` | `→ TimerRef` | both | Schedule `msg` for delivery to `pid` after `delay_ms`. Built on the same timer heap that backs `Actor.call`'s timeout and supervisor restart backoff. A pending timer does not keep `run_until_idle()` waiting. |
| `Actor.cancel_timer(ref)` | `→ ()` | both | Cancel a pending `send_after` timer. Safe to call at any time, including after the timer already fired or was already cancelled (both are no-ops). |

---

## Next Steps

The concurrency and distribution docs form a journey: actors are the foundation; each step below builds on them:

- [Supervision Trees]({{ site.baseurl }}/docs/supervision/): fault-tolerant hierarchies with automatic restart, ending in a capstone crash-tolerant job processor.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/): `pmap` / `pmap_n` for data-parallel work on the same scheduler.
- [Flow & Backpressure]({{ site.baseurl }}/docs/flow/): bounded streaming pipelines when a fast producer outruns a slow consumer.
- [Overload & Resilience]({{ site.baseurl }}/docs/overload-resilience/): the practical guide to mailbox limits, load shedding, deadlines, and restart backoff working together.
- [Session Types]({{ site.baseurl }}/docs/session-types/): typed two-party protocols with a message order the compiler enforces.
- [Clustering & RPC]({{ site.baseurl }}/docs/clustering/): take a supervised actor app from one node to a cluster with cross-node calls.
- [Hot Code Reload]({{ site.baseurl }}/docs/hot-code-reload/): deploy new code to a running server without restarting; actors migrate their state on the fly.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): how linear types interact with message passing.
- [Task stdlib]({{ site.baseurl }}/docs/stdlib/Task.html): full Task API reference.
