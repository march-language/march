---
layout: page
title: Supervision Trees
nav_order: 10
---

# Supervision Trees

Supervision trees are how March programs achieve fault tolerance. When an actor crashes, its supervisor automatically restarts it according to a configurable policy.

---

## The Idea

In Erlang/OTP (which March's actor model draws from), the approach to failures is "let it crash." Instead of defensive error handling everywhere, you structure your system so that:

1. Worker actors do their job and crash on unexpected errors
2. Supervisor actors watch workers and restart them
3. Supervisors can themselves be supervised

The result is a tree of processes where failures are isolated and recovery is automatic.

---

## Declaring a Supervisor

Any actor can supervise children by adding a `supervise` block:

```march
actor AppSupervisor do
  state { counter : Int, logger : Int }
  init  { counter = 0, logger = 0 }

  supervise do
    strategy one_for_one
    max_restarts 5 within 30
    Counter counter
    Logger  logger
  end
end
```

The `supervise` block:
- `strategy` — restart policy (see below)
- `max_restarts N within S` — if more than N restarts occur in S seconds, the supervisor itself crashes (escalates to its own supervisor)
- Each line `ActorName field_name` — a child to supervise, with `field_name` being the state field that stores its current `Pid`

When the supervisor starts (via `spawn(AppSupervisor)`), it automatically spawns all listed children.

---

## Restart Strategies

### `one_for_one`

Only the crashed child is restarted. Other children continue running.

```march
supervise do
  strategy one_for_one
  max_restarts 3 within 60
  Worker1 w1
  Worker2 w2
  Worker3 w3
end
-- If w2 crashes, only w2 is restarted
```

Use `one_for_one` when children are independent.

### `one_for_all`

When any child crashes, **all** children are stopped and restarted.

```march
supervise do
  strategy one_for_all
  max_restarts 2 within 30
  DbConnection db
  CacheConnection cache
  QueryEngine engine
end
-- If db crashes, db + cache + engine are all restarted
```

Use `one_for_all` when children are tightly coupled and must be in sync.

### `rest_for_one`

When a child crashes, it and all children **started after it** are restarted. Children started before it are left alone.

```march
supervise do
  strategy rest_for_one
  max_restarts 5 within 60
  Config    cfg      -- started first, independent
  Database  db       -- depends on nothing
  ApiServer api      -- depends on db
  Logger    log      -- depends on api
end
-- If db crashes, db + api + log restart; cfg is left running
```

Use `rest_for_one` when later children depend on earlier ones.

---

## A Full Supervision Example

Adapted from [examples/supervision_basic.march](../examples/supervision_basic.march):

```march
mod BasicSupervision do

  actor Counter do
    state { count : Int }
    init  { count = 0 }

    on Inc() do
      let n = state.count + 1
      println("[Counter] count -> " ++ int_to_string(n))
      { count = n }
    end
  end

  actor Logger do
    state { entries : Int }
    init  { entries = 0 }

    on Log(msg : String) do
      let n = state.entries + 1
      println("[Logger] #" ++ int_to_string(n) ++ ": " ++ msg)
      { entries = n }
    end
  end

  actor AppSupervisor do
    state { counter : Int, logger : Int }
    init  { counter = 0, logger = 0 }

    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      Counter counter
      Logger  logger
    end
  end

  fn main() do
    -- Spawn supervisor: it auto-starts Counter and Logger
    let sup = spawn(AppSupervisor)

    -- Get child PIDs from supervisor state
    let c1_int = match get_actor_field(sup, "counter") do
                   None    -> -1
                   Some(n) -> n
                 end
    let c1 = pid_of_int(c1_int)

    println("Counter alive: " ++ bool_to_string(is_alive(c1)))

    -- Use the children
    send(c1, Inc())
    send(c1, Inc())
    run_until_idle()

    -- Crash the Counter
    kill(c1)
    println("Counter alive after kill: " ++ bool_to_string(is_alive(c1)))

    -- Supervisor restarts it with a new PID
    let c2_int = match get_actor_field(sup, "counter") do
                   None    -> -1
                   Some(n) -> n
                 end
    let c2 = pid_of_int(c2_int)
    println("New counter PID: " ++ int_to_string(c2_int))
    println("New counter alive: " ++ bool_to_string(is_alive(c2)))

    -- Restarted counter has fresh state (count = 0)
    send(c2, Inc())
    run_until_idle()
  end

end
```

---

## Escalation: Max Restarts Budget

If a child crashes too frequently, the supervisor gives up and crashes itself, escalating the fault to its own supervisor:

```march
supervise do
  strategy one_for_one
  max_restarts 3 within 60  -- 3 restarts in 60 seconds → supervisor crashes
  FlakeyWorker w
end
```

This prevents restart storms from grinding the system to a halt. The escalation propagates up the supervision tree until either a supervisor absorbs it or the top-level supervisor crashes the whole application.

---

## Supervision Strategies Compared

```
Worker crashes:     W1  W2  W3
                    ↑
                  crash

one_for_one:        ↻   ok  ok    (only W1 restarts)
one_for_all:        ↻   ↻   ↻     (all restart)
rest_for_one:       ↻   ↻   ok    (W1 and later restart)
```

---

## Nested Supervision Trees

Supervisors can supervise other supervisors, forming a tree:

```march
actor TopSupervisor do
  state { web_sup : Int, db_sup : Int }
  init  { web_sup = 0, db_sup = 0 }

  supervise do
    strategy one_for_one
    max_restarts 2 within 30
    WebSupervisor web_sup
    DbSupervisor  db_sup
  end
end

actor WebSupervisor do
  state { router : Int, cache : Int }
  init  { router = 0, cache = 0 }

  supervise do
    strategy one_for_all
    max_restarts 5 within 60
    Router router
    Cache  cache
  end
end

actor DbSupervisor do
  state { pool : Int }
  init  { pool = 0 }

  supervise do
    strategy one_for_one
    max_restarts 10 within 60
    ConnectionPool pool
  end
end
```

A crash in the Web tier doesn't affect the DB tier. A crash in the DB tier escalates to TopSupervisor.

---

## App-Level Entry Point

The `app` declaration is a shorthand for defining the top-level supervisor:

```march
mod MyService do
  actor Worker do
    state { n : Int }
    init  { n = 0 }
    on Tick() do { state with n = state.n + 1 } end
  end

  app MyService do
    Supervisor.spec(:one_for_one, [worker(Worker)])
  end
end
```

---

## Strategies for Supervision Design

**Start with `one_for_one`** — it's the most common and most isolated strategy.

**Use `one_for_all` when children share state** — for example, a group of actors that all read from a shared config loaded at startup. If one crashes, the shared state might be stale and all should reload.

**Use `rest_for_one` for pipelines** — if actor B depends on actor A having started first, use `rest_for_one` so a crash in A also restarts B.

**Keep supervisors thin** — a supervisor's job is supervision, not business logic. Don't add handlers to a supervisor actor beyond what's needed to manage children.

**Budget restarts conservatively** — `max_restarts 3 within 5` is aggressive; `max_restarts 10 within 60` is more lenient. Match the budget to how often legitimate transient failures are expected.

---

## Next Steps

- [Actors](actors.md) — the actor model basics
- [Linear Types](linear-types.md) — how linear types support safe actor messaging
