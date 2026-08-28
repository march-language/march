---
layout: docs
title: Supervision Trees
nav_order: 10
permalink: /docs/supervision/
---

# Supervision Trees

Supervision trees are how March programs achieve fault tolerance. When an actor crashes, its supervisor automatically restarts it according to a configurable policy.

---

## The Idea

Most languages push you toward *defensive* error handling: wrap anything that might go
wrong in a try/catch, check every return value, anticipate every failure mode up front.
It works, but it's a lot of code, and it's easy to miss a case.

Supervision trees are built on a different instinct, sometimes called **"let it
crash"** (the idea comes from Erlang/OTP, which March's actor model draws from). It
sounds backwards at first: isn't crashing bad? The insight is that most failures are
**transient**: a stale cache entry, a flaky connection, one bad message that corrupted a
bit of local state. For that kind of bug, the cheapest reliable fix isn't to carefully
detect and repair the corruption; it's to throw the whole thing away and start over
with fresh state. So instead of handling every error everywhere, you structure your
system so that:

1. Worker actors do their job, and simply crash on unexpected errors instead of trying to handle them
2. Supervisor actors watch workers and restart them with clean state when they crash
3. Supervisors can themselves be supervised

The result is a tree of processes where failures are isolated to the one thing that
broke, and recovery is automatic: you write the "happy path" logic once, and the
supervisor handles the "something went wrong" case for you, uniformly, every time.

---

## Declaring a Supervisor

Any actor can supervise children by adding a `supervise` block:

```march
actor AppSupervisor do
  state { counter : Int, logger : Int }
  init  { counter: 0, logger: 0 }

  supervise do
    strategy one_for_one
    max_restarts 5 within 30
    Counter counter
    Logger  logger
  end
end
```

The `supervise` block:
- `strategy`: restart policy (see below)
- `max_restarts N within S`: if more than N restarts occur in S seconds, the supervisor itself crashes (escalates to its own supervisor)
- Each line `ActorName field_name`: a child to supervise, with `field_name` being the state field that stores its current `Pid`

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

When a child crashes, it and all children **started after it** are restarted. Children started before it are left as they were.

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

(Originally adapted from `examples/supervision_basic.march`, since removed
as a redundant example; this inline copy is now the canonical source and is
verified directly against the compiler.)

> **Interpreter-only, as written.** Restart itself (`one_for_one` etc.) is correct on
> both backends, but this example reaches a supervised child from *outside* the tree with
> `get_actor_field(sup, …)` + `pid_of_int(…)`, and that pair **crashes in a compiled
> binary** (compiled builds also skip a child's `init` at `spawn(Sup)`). Run it under the
> interpreter (`march run` / `run_until_idle()`); see
> [Actors → App Entry Point]({{ site.baseurl }}/docs/actors/) for the same caveat in the
> Builtins table.

```march
mod BasicSupervision do
  needs IO.Console

  actor Counter do
    state { count : Int }
    init  { count: 0 }

    on Inc() do
      let n = state.count + 1
      println("[Counter] count -> " ++ int_to_string(n))
      { count: n }
    end
  end

  actor Logger do
    state { entries : Int }
    init  { entries: 0 }

    on Log(msg : String) do
      let n = state.entries + 1
      println("[Logger] #" ++ int_to_string(n) ++ ": " ++ msg)
      { entries: n }
    end
  end

  actor AppSupervisor do
    state { counter : Int, logger : Int }
    init  { counter: 0, logger: 0 }

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

## Restart Backoff

A child's **first** crash restarts immediately (zero added delay), the same
synchronous, zero-delay behavior as before backoff existed, so a single
crash-and-recover cycle is unaffected. Only a **repeat** crash of the same
child slot (its `crash_streak` exceeds 1) is delayed: the delay is
`25ms << min(streak - 1, 7)`: 50, 100, 200, 400, 800, 1600, then capped at
3200ms pre-jitter (the shift itself saturates at 7, so 3200ms is the true
upper limit, not 5000ms), with ±25% jitter on top (observed max ~4000ms) to
de-synchronize a crash storm's retries. The streak resets to
0 once the child completes a full `max_restarts ... within N` window without
crashing again; a healed child goes back to immediate-restart behavior on
its next isolated crash.

For the batch strategies (`one_for_all`/`rest_for_one`), a pending delayed
restart absorbs any further crashes among covered children that arrive
before it fires, instead of scheduling a second overlapping restart; the
restart's child range widens (never narrows) to cover every sibling that
crashed during the pending window.

Set `MARCH_SUP_TRACE=1` to print each restart decision to stderr:
`march: supervisor backoff child=<idx> streak=<n> delay_ms=<ms>`, plus a
` (batch restart already pending, skipped)` suffix when a crash was absorbed
into an already-pending batch restart instead of scheduling its own.

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
  init  { web_sup: 0, db_sup: 0 }

  supervise do
    strategy one_for_one
    max_restarts 2 within 30
    WebSupervisor web_sup
    DbSupervisor  db_sup
  end
end

actor WebSupervisor do
  state { router : Int, cache : Int }
  init  { router: 0, cache: 0 }

  supervise do
    strategy one_for_all
    max_restarts 5 within 60
    Router router
    Cache  cache
  end
end

actor DbSupervisor do
  state { pool : Int }
  init  { pool: 0 }

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

The `app` declaration is a shorthand for defining the **top-level** supervisor of a
long-running application:

```march
mod MyService do
  actor Worker do
    state { n : Int }
    init  { n: 0 }
    on Tick() do { state with n: state.n + 1 } end
  end

  app MyService do
    Supervisor.spec(:one_for_one, [worker(Worker)])
  end
end
```

This is the value-level counterpart of the [`supervise` block](#declaring-a-supervisor)
used everywhere else on this page: the `app` body evaluates to a `Supervisor.Spec`, where
`Supervisor.spec(:one_for_one, [worker(Worker), …])` states the same thing as
`supervise do strategy one_for_one; Worker … end` inside an actor. The differences are
scope and spelling: `app` defines the *single application root* (not an inner actor's
children), and the strategy is passed as the atom `:one_for_one` rather than the bare
`one_for_one` keyword the block DSL uses. Use `supervise` to give an actor children; use
`app` for the application's root supervisor. See
[Actors → App Entry Point]({{ site.baseurl }}/docs/actors/) for the same note from the
actor side.

---

## Strategies for Supervision Design

**Start with `one_for_one`**: it's the most common and most isolated strategy.

**Use `one_for_all` when children share state**: for example, a group of actors that all read from a shared config loaded at startup. If one crashes, the shared state might be stale and all should reload.

**Use `rest_for_one` for pipelines**: if actor B depends on actor A having started first, use `rest_for_one` so a crash in A also restarts B.

**Keep supervisors thin**: a supervisor's job is supervision, not business logic. Don't add handlers to a supervisor actor beyond what's needed to manage children.

**Budget restarts conservatively**: `max_restarts 3 within 5` is aggressive; `max_restarts 10 within 60` is more lenient. Match the budget to how often legitimate transient failures are expected.

---

## Capstone: a crash-tolerant job processor

Let's build something real by layering the pieces one at a time: each step adds exactly one capability, and you can stop at whichever level your problem needs.

### Step 1: one worker

Start with a single actor that processes jobs. On a bad job it just crashes; we'll make that survivable in the next step.

```march
mod JobProcessorV1 do
  needs IO.Console

  actor Worker do
    state { done : Int }
    init  { done: 0 }

    on Process(job : Int) do
      -- pretend-work; a real handler might crash on a malformed job
      println("[Worker] processed job " ++ int_to_string(job))
      { done: state.done + 1 }
    end
  end

  fn main() do
    let w = spawn(Worker)
    send(w, Process(1))
    send(w, Process(2))
    run_until_idle()
  end

end
```

That's the whole job processor, but if `Process` crashes at any point, the worker is gone and every later job is dropped.

### Step 2: put it under a supervisor (crash recovery)

Wrap the worker in a `one_for_one` supervisor. Now a crash is *recovered from*: the supervisor restarts the worker (with fresh state) instead of losing it.

> **Interpreter-only, as written**: like the [Full Supervision Example](#a-full-supervision-example) above, this reads the child PID back out with `get_actor_field` + `pid_of_int`, which crash in a compiled binary. Run it under the interpreter.

```march
mod JobProcessorV2 do
  needs IO.Console

  actor Worker do
    state { done : Int }
    init  { done: 0 }

    on Process(job : Int) do
      println("[Worker] processed job " ++ int_to_string(job))
      { done: state.done + 1 }
    end
  end

  actor JobSupervisor do
    state { worker : Int }
    init  { worker: 0 }

    supervise do
      strategy one_for_one
      max_restarts 5 within 30
      Worker worker
    end
  end

  fn main() do
    let sup = spawn(JobSupervisor)
    let w_int = match get_actor_field(sup, "worker") do
                  None    -> -1
                  Some(n) -> n
                end
    let w = pid_of_int(w_int)
    send(w, Process(1))
    run_until_idle()

    -- A crash is now survivable: kill the worker and the supervisor restarts it.
    kill(w)
    let w2_int = match get_actor_field(sup, "worker") do
                   None    -> -1
                   Some(n) -> n
                 end
    println("worker restarted, alive: "
            ++ bool_to_string(is_alive(pid_of_int(w2_int))))
    run_until_idle()
  end

end
```

`one_for_one` is the right strategy here: one worker, independent of anything else, restarted on its own. See [Restart Strategies](#restart-strategies) for when to escalate to `one_for_all` or `rest_for_one`.

### Step 3: fan out to N workers

One worker is a bottleneck. Spawn a pool and spread jobs across it. Each worker is the
same supervised actor; we just spawn several and round-robin work to them. This step
and the next borrow tools from other pages; you don't need to have read them first,
just see how they slot into the same "add exactly the resilience you need" pattern.

The data-parallel shortcut for "run this over a whole list across the pool" is
[`List.pmap`]({{ site.baseurl }}/docs/parallel-collections/): it applies a function to
every element using the same actor scheduler underneath, and gives back results in the
original order, as if you'd called `List.map`:

```march
-- Dispatch a batch of jobs across N workers, in parallel.
fn dispatch_all(jobs : List(Int)) do
  -- Each job runs concurrently; results come back in the original order.
  List.pmap(jobs, fn job -> handle_job(job))
end
```

Under a supervisor you'd list several `Worker` children (`Worker w1`, `Worker w2`, …, each its own state field) so a crash in one doesn't disturb the others; that's exactly what `one_for_one` gives a pool.

### Step 4: add backpressure so a fast producer can't flood the pool

**Backpressure** just means: the slow stage sets the pace, instead of letting a fast
stage pile up work faster than it can be handled. The missing piece here: if jobs arrive
faster than the pool drains them, an unbounded queue grows until memory runs out. Put a
[`Flow`]({{ site.baseurl }}/docs/flow/) pipeline in front so the *consumer* (the pool)
sets the pace; the producer only runs as far ahead as there's capacity:

```march
fn process_stream(jobs : List(Int)) do
  Flow.from_list(jobs)
    |> Flow.map(fn job -> handle_job(job))   -- the slow stage
    |> Flow.with_concurrency(4)              -- 4 worker actors, bounded demand
    |> Flow.collect
end
```

If you'd rather bound concurrency on a plain list without a pipeline, [`List.pmap_n(jobs, handle_job, 4)`]({{ site.baseurl }}/docs/parallel-collections/) caps in-flight work the same way. Either way, the chain is now complete: **one worker → supervised (persists through crashes) → a pool (throughput) → backpressured (bounded memory under load).** That progression (start simple, add exactly the resilience you need) is the heart of how March systems are built.

> **What runs where.** The plain actor/supervisor programs (Steps 1–2) execute in the interpreter via `run_until_idle()`. The `Flow` / `pmap` stages (Steps 3–4) produce identical *results* in the interpreter but only parallelise when **compiled**; see [Parallel Collections → Interpreter vs. compiled]({{ site.baseurl }}/docs/parallel-collections/) and [Flow & Backpressure]({{ site.baseurl }}/docs/flow/).

---

## Next Steps

- [Actors]({{ site.baseurl }}/docs/actors/): the actor model basics and the concurrency decision guide.
- [Parallel Collections]({{ site.baseurl }}/docs/parallel-collections/): `pmap` / `pmap_n` for fanning work across a pool.
- [Flow & Backpressure]({{ site.baseurl }}/docs/flow/): bounded streaming so a fast producer can't flood your workers.
- [Clustering & RPC]({{ site.baseurl }}/docs/clustering/): take a supervised app from one node to a cluster.
- [Linear Types]({{ site.baseurl }}/docs/linear-types/): how linear types support safe actor messaging.
