---
layout: page
title: Actors
nav_order: 9
---

# Actors

March's concurrency model is built on actors: isolated processes that communicate exclusively through message passing. Actors share no mutable state — isolation is enforced by the type system.

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

`send` returns `Some(())` if the actor is alive, or `None` if the actor is dead (has been killed or crashed):

```march
match send(counter, Increment(1)) do
  Some(_) -> println("message delivered")
  None    -> println("actor is dead")
end
```

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

## A Complete Actor Example

This is adapted from [examples/actors.march](../examples/actors.march):

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

    -- Kill the logger
    kill(logger)
    println("logger alive: " ++ bool_to_string(is_alive(logger)))

    -- Messages to dead actors return None
    match send(logger, Log("dropped")) do
      None    -> println("message dropped — actor is dead")
      Some(_) -> ()
    end

    -- Counter is unaffected
    send(counter, Ping("after kill"))
  end

end
```

---

## Handlers with Side Effects

Handlers can perform I/O before returning the new state:

```march
actor Database do
  state { entries : List(String) }
  init  { entries = [] }

  on Insert(key : String) do
    println("[DB] inserting: " ++ key)
    let new_entries = Cons(key, state.entries)
    { state with entries = new_entries }
  end

  on Count() do
    let n = List.length(state.entries)
    println("[DB] count: " ++ int_to_string(n))
    state    -- return state unchanged when side-effect only
  end
end
```

---

## Request-Reply Pattern

Actors don't have built-in synchronous calls. The standard pattern for request-reply is to pass a reply-to `Pid` in the message:

```march
actor Store do
  state { data : Map(String, Int) }
  init  { data = Map.new() }

  on Put(key : String, val : Int) do
    { state with data = Map.put(state.data, key, val) }
  end

  on Get(key : String, reply_to : Pid) do
    let result = Map.get(state.data, key)
    send(reply_to, result)
    state
  end
end

actor Client do
  state { self_pid : Int }
  init  { self_pid = 0 }

  on Start(store : Pid) do
    send(store, Put("count", 42))
    send(store, Get("count", self()))
    state
  end

  on Some(v : Int) do
    println("got value: " ++ int_to_string(v))
    state
  end

  on None() do
    println("key not found")
    state
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

## Running Until Idle

In programs with actors, `run_until_idle()` processes all pending messages before continuing. Useful in scripts and tests:

```march
fn main() do
  let counter = spawn(Counter)
  send(counter, Increment(1))
  send(counter, Increment(2))
  send(counter, Increment(3))
  run_until_idle()
  -- All messages have been processed here
  send(counter, Ping("done"))
  run_until_idle()
end
```

---

## Multiple Actors Communicating

Actors can hold references to other actors as part of their state:

```march
actor Worker do
  state { boss : Pid, id : Int }
  init  { boss = pid_of_int(0), id = 0 }

  on SetUp(boss_pid : Pid, worker_id : Int) do
    { state with boss = boss_pid, id = worker_id }
  end

  on DoWork(task : String) do
    let result = process(task)
    send(state.boss, Done(state.id, result))
    state
  end
end

actor Boss do
  state { workers : List(Pid), done_count : Int }
  init  { workers = [], done_count = 0 }

  on AddWorker(w : Pid) do
    { state with workers = Cons(w, state.workers) }
  end

  on Done(worker_id : Int, result : String) do
    println("worker " ++ int_to_string(worker_id) ++ " done: " ++ result)
    { state with done_count = state.done_count + 1 }
  end
end
```

---

## Actor Identity: self()

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
| `spawn(Actor)` | `-> Pid` | Start a new actor |
| `send(pid, msg)` | `-> Option(())` | Send a message (None if actor is dead) |
| `kill(pid)` | `-> ()` | Stop an actor |
| `is_alive(pid)` | `-> Bool` | Check if actor is running |
| `self()` | `-> Pid` | Current actor's Pid |
| `run_until_idle()` | `-> ()` | Process all pending messages |
| `pid_of_int(n)` | `-> Pid` | Convert Int to Pid |

---

## Next Steps

- [Supervision](supervision.md) — fault-tolerant hierarchies with automatic restart
- [Linear Types](linear-types.md) — how linear types interact with message passing
