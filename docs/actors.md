---
layout: docs
title: Actors
nav_order: 9
---

# Actors

March's concurrency model is built on **actors** and **tasks**. Actors are isolated processes that communicate exclusively through message passing — no shared mutable state. Tasks are lightweight one-off computations that run concurrently and return a value.

In the compiled runtime, both actors and tasks run on an M:N green-thread scheduler (multiple OS threads, each running many lightweight green threads). Actors park cooperatively when their mailbox is empty; tasks park when awaiting a result.

---

## Defining an Actor

An actor declaration has three parts:
- `state { ... }` — the state record type
- `init { ... }` — the initial state value
- `on Msg(...) do ... end` — message handlers, each returning the new state

```march
actor Counter do
  state { value : Int }
  init  { value = 0 }

  on Increment(n : Int) do
    { state with value = state.value + n }
  end

  on Decrement(n : Int) do
    { state with value = state.value - n }
  end

  on Reset() do
    { state with value = 0 }
  end
end
```

Inside a handler, `state` refers to the current state record. Each handler must return the new state (same type as `state`).

---

## Spawning Actors

`spawn` creates a new actor and returns its process identifier (`Pid`):

```march
fn main() do
  let counter = spawn(Counter)
  -- counter : Pid
end
```

---

## Sending Messages

`send` delivers a message to an actor asynchronously:

```march
send(counter, Increment(10))
send(counter, Increment(5))
send(counter, Reset())
```

The message is the constructor applied to its arguments. The actor handles it according to its `on` clause.

`send` returns `Some(())` if the actor is alive, or `None` if the actor is dead:

```march
match send(counter, Increment(1)) do
  Some(_) -> println("message delivered")
  None    -> println("actor is dead")
end
```

---

## Receiving Messages Inside a Handler

`receive()` blocks until the next message arrives in the actor's mailbox. Use it when a handler needs to wait for a sub-message before continuing:

```march
actor Dispatcher do
  state { got : Int }
  init  { got = 0 }

  on Dispatch() do
    -- wait for the follow-up message
    let follow = receive()
    match follow do
      Followup(n) -> { got = n }
    end
  end
end

fn main() do
  let pid = spawn(Dispatcher)
  send(pid, Dispatch())
  send(pid, Followup(99))
  run_until_idle()
end
```

**Blocking semantics:** If the mailbox is empty when `receive()` is called, the actor parks (interpreter: re-queues the triggering message; compiled: green thread parks). It resumes automatically once a message is delivered. `run_until_idle()` returns as soon as all actors are either idle or waiting — no deadlock.

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

After `kill`, `is_alive(counter)` returns `false` and further `send`s return `None`.

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
      :error -> println("actor dead or cap stale")
    end
end
```

Use capabilities when you hold a reference across an actor restart boundary and need to know whether the message was delivered to the *current* incarnation of the actor. Under a supervisor, a restarted actor gets a fresh epoch, invalidating caps from before the restart.

---

## Synchronous Request-Reply via `Actor.call`

The `Actor` module provides a synchronous call pattern:

```march
actor Store do
  state { count : Int }
  init  { count = 0 }

  on Inc() do
    { count = state.count + 1 }
  end

  on Call(ref, Get()) do
    Actor.reply(ref, state.count)
    state
  end
end

fn main() do
  let pid = spawn(Store)
  send(pid, Inc())
  send(pid, Inc())
  run_until_idle()
  match Actor.call(pid, Get(), 5000) do
    Ok(n)  -> println("count = " ++ int_to_string(n))
    Err(e) -> println("error: " ++ e)
  end
end
```

`Actor.call(pid, msg, timeout_ms)` sends `Call(ref, msg)` to the actor and waits for `Actor.reply(ref, result)`. Returns `Ok(result)` or `Err(reason)`.

`Actor.cast(pid, msg)` is fire-and-forget — equivalent to `send` but goes through the `Actor` module.

---

## A Complete Actor Example

```march
mod ActorDemo do

  actor Counter do
    state { value : Int }
    init  { value = 0 }

    on Increment(n : Int) do
      { state with value = state.value + n }
    end

    on Ping(label : String) do
      println("[Counter] ping from " ++ label
              ++ ", value = " ++ int_to_string(state.value))
      state
    end
  end

  actor Logger do
    state { count : Int }
    init  { count = 0 }

    on Log(msg : String) do
      let n = state.count + 1
      println("[LOG #" ++ int_to_string(n) ++ "] " ++ msg)
      { state with count = n }
    end
  end

  fn main() do
    let counter = spawn(Counter)
    let logger  = spawn(Logger)

    send(counter, Increment(10))
    send(logger,  Log("counter incremented by 10"))
    send(counter, Increment(5))
    send(counter, Ping("main"))

    kill(logger)
    println("logger alive: " ++ bool_to_string(is_alive(logger)))

    match send(logger, Log("dropped")) do
      None    -> println("message dropped — actor is dead")
      Some(_) -> ()
    end

    send(counter, Ping("after kill"))
    run_until_idle()
  end

end
```

---

## Actor State with Records

Complex state uses record types. Functional update with `{ state with field = new_value }` is the canonical way to update state:

```march
actor WebServer do
  state {
    request_count : Int,
    error_count   : Int,
    last_path     : String
  }
  init {
    request_count = 0,
    error_count   = 0,
    last_path     = ""
  }

  on Request(path : String, status : Int) do
    let rc = state.request_count + 1
    let ec = if status >= 400 do state.error_count + 1 else state.error_count end
    { state with
        request_count = rc,
        error_count   = ec,
        last_path     = path }
  end

  on Stats() do
    println("requests: " ++ int_to_string(state.request_count))
    println("errors: "   ++ int_to_string(state.error_count))
    state
  end
end
```

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

See the [Task module docs](stdlib/Task.html) for the full API including `Task.race`, `Task.any`, `Task.scope`, and `Task.all_settled`.

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
  send(counter, Ping("done"))
  run_until_idle()
end
```

In long-running applications, the scheduler runs automatically — you do not call `run_until_idle()`.

---

## Actor Identity: `self()`

Inside a handler, `self()` returns the current actor's `Pid`. Useful for passing yourself as a reply address:

```march
on Request(question : String, caller : Pid) do
  let answer = compute_answer(question)
  send(caller, Answer(answer, self()))
  state
end
```

---

## App Entry Point

For long-running applications, use `app` instead of (or alongside) `main`:

```march
mod MyService do
  actor Worker do
    state { count : Int }
    init  { count = 0 }
    on Tick() do { state with count = state.count + 1 } end
  end

  app MyService do
    Supervisor.spec(:one_for_one, [worker(Worker)])
  end
end
```

The `app` declaration integrates with the supervision system. See [Supervision](supervision.md) for details.

---

## Builtins Reference

| Builtin | Signature | Description |
|---------|-----------|-------------|
| `spawn(Actor)` | `→ Pid` | Start a new actor |
| `send(pid, msg)` | `→ Option(())` | Send a message (None if actor is dead) |
| `receive()` | `→ Msg` | Block until the next mailbox message arrives |
| `kill(pid)` | `→ ()` | Stop an actor |
| `is_alive(pid)` | `→ Bool` | Check if actor is running |
| `self()` | `→ Pid` | Current actor's Pid |
| `run_until_idle()` | `→ ()` | Process all pending messages (interpreter / tests) |
| `get_cap(pid)` | `→ Option(Cap(Msg))` | Obtain an epoch-tagged capability for an actor |
| `send_checked(cap, msg)` | `→ :ok \| :error` | Epoch-validated send; fails if actor restarted |
| `pid_of_int(n)` | `→ Pid` | Convert Int to Pid |
| `task_spawn(fn)` | `→ Task(a)` | Spawn a green-thread task (use `Task.async` instead) |
| `task_await(t)` | `→ Result(a, String)` | Await a task (use `Task.await` instead) |

---

## Next Steps

- [Supervision](supervision.md) — fault-tolerant hierarchies with automatic restart
- [Linear Types](linear-types.md) — how linear types interact with message passing
- [Task stdlib](stdlib/Task.html) — full Task API reference
