# Job & Workflow Orchestration System

> Broad plan — to be refined once Bastion and Depot are further along.

## Vision

A unified job processing and workflow orchestration library built on Bastion, combining the best ideas from Oban (Postgres-backed job queues), Temporal (durable execution), Airflow (DAG scheduling), and Sidekiq (simple worker model). Not a standalone service — a library that Bastion apps pull in, the way Oban is just a dependency in an Elixir app.

Working name: **Forge.Jobs** (or `march_jobs` as a Forge package).

---

## Why Build on Bastion + Depot

March's actor system gives us isolated, supervised workers for free. Depot gives us Postgres for durable state without an external broker. Bastion gives us HTTP routes for a dashboard. Islands give us real-time UI. The whole stack is already there — we just need the orchestration layer on top.

Key leverage points:

- **Actors as workers** — each job runs in its own actor with supervision, crash isolation, and mailbox-based communication. No need to build a process model.
- **Depot as the queue** — jobs live in a Postgres table. No Redis, no RabbitMQ. Depot transactions give us exactly-once semantics. LISTEN/NOTIFY gives us immediate dispatch without polling.
- **Bastion routes for dashboard** — mount a `/jobs` or `/admin/jobs` route group for monitoring, retries, and workflow visualization.
- **Islands for live updates** — job progress, workflow DAG visualization, and log streaming via Islands live components.

---

## Three Layers

### Layer 1: Job Queue (Oban/Sidekiq)

The foundation. Simple, reliable background job processing.

**Scope:** ~0.2–0.3× Bastion effort (small library, well-understood problem)

**Core concepts:**
- Jobs are records in a Depot table with queue name, args (JSON), state, scheduled_at, attempted_at, retry count
- Workers are actor pools — one pool per named queue, configurable concurrency per queue
- Job lifecycle: `available → executing → completed | retracted | discarded | cancelled`
- Retry with exponential backoff + configurable max attempts
- Scheduled jobs (run at a specific time) and recurring jobs (cron expressions)
- LISTEN/NOTIFY for immediate dispatch — no polling delay
- Unique jobs (deduplicate by key within a time window)
- Job priority within queues
- Pruning: auto-delete completed jobs after configurable retention

**What a worker looks like (sketch):**
```march
mod EmailWorker do
  fn perform(job) do
    let to = Job.arg(job, "to")
    let subject = Job.arg(job, "subject")
    Mailer.send(to, subject, Job.arg(job, "body"))
  end
end
```

**What enqueueing looks like:**
```march
Jobs.enqueue(EmailWorker, %{to: "user@example.com", subject: "Welcome", body: "..."})
Jobs.enqueue(EmailWorker, %{...}, schedule_in: Duration.minutes(5))
Jobs.enqueue(EmailWorker, %{...}, queue: "critical", priority: 0)
```

**Prerequisites from Bastion/Depot:**
- Depot: connection pooling, transactions, migrations, LISTEN/NOTIFY
- Bastion: actor supervision trees stable, graceful shutdown (drain queues)

---

### Layer 2: Durable Execution (Temporal)

The hard part. Long-running, fault-tolerant workflows with replay.

**Scope:** ~1.5–2.5× Bastion effort (novel, complex, needs careful design)

**Core concepts:**
- Workflows are deterministic functions whose execution is persisted as an append-only event log in Depot
- Activities are the non-deterministic side-effecting steps (API calls, DB writes, sending email)
- On crash/restart, the workflow replays from its event log — deterministic code re-executes, activities are skipped (their results are already in the log)
- Timers: `Workflow.sleep(Duration.hours(24))` persists a timer event — on replay it resolves immediately if the time has passed
- Signals: external events can be sent to a running workflow via its mailbox
- Saga/compensation: if step N fails, run compensating actions for steps 1..N-1
- Child workflows: a workflow can spawn sub-workflows

**What a workflow looks like (sketch):**
```march
mod OrderWorkflow do
  fn run(ctx, order_id) do
    let order = Workflow.activity(ctx, "validate", fn () -> Orders.validate(order_id))
    let payment = Workflow.activity(ctx, "charge", fn () -> Payments.charge(order.total))
    Workflow.sleep(ctx, Duration.minutes(30))  -- wait for fraud check
    let ship = Workflow.activity(ctx, "ship", fn () -> Shipping.create_label(order))
    Workflow.activity(ctx, "notify", fn () -> Mailer.send_shipped(order, ship.tracking))
  end
end
```

**Key design questions (to resolve later):**
- How to enforce determinism in workflow code — compiler support? Runtime checks?
- Event log storage format — one table or sharded by workflow type?
- Replay performance — can we snapshot/checkpoint to avoid full replay?
- How do workflow actors interact with the scheduler actor pool?
- Version management — what happens when workflow code changes mid-execution?

**Prerequisites from Bastion/Depot:**
- Everything from Layer 1
- Depot: robust transaction support, large row handling (event logs can get big)
- Actor system: persistent actor mailboxes (receive signals across restarts)
- Possibly: serialization framework for activity results

---

### Layer 3: DAG Scheduling + Dashboard (Airflow)

Scheduled, dependency-aware pipelines with a web UI for visibility.

**Scope:** ~0.4–0.6× Bastion effort (UI is the bulk of the work)

**Core concepts:**
- DAGs are declared as March data structures — nodes are jobs or workflows, edges are dependencies
- A scheduler actor evaluates DAGs on a cron schedule, resolving dependencies and enqueueing ready tasks
- Backfill: re-run a DAG for historical date ranges
- Dashboard routes mounted in Bastion:
  - DAG list with status overview
  - DAG detail: visual graph (nodes + edges), run history, per-task logs
  - Job queue overview: queue depths, throughput, failure rates
  - Workflow detail: event timeline, current state, signal controls
  - Manual triggers: re-run, cancel, retry from failed step

**What a DAG looks like (sketch):**
```march
mod DailyETL do
  fn dag() do
    Dag.new("daily_etl", schedule: "0 2 * * *")
    |> Dag.task("extract", ExtractWorker, %{source: "api"})
    |> Dag.task("transform", TransformWorker, %{}, depends_on: ["extract"])
    |> Dag.task("load_warehouse", LoadWorker, %{dest: "warehouse"}, depends_on: ["transform"])
    |> Dag.task("load_cache", CacheWorker, %{}, depends_on: ["transform"])
    |> Dag.task("notify", SlackWorker, %{}, depends_on: ["load_warehouse", "load_cache"])
  end
end
```

**Prerequisites from Bastion/Depot:**
- Layers 1 and 2 working
- Islands: stable enough for real-time DAG visualization
- Templates: for dashboard HTML
- Bastion: authentication middleware (dashboard should be admin-only)

---

## Phasing

Rough order of implementation, acknowledging that Bastion and Depot need to mature first.

| Phase | What | Depends on | Rough effort |
|-------|------|------------|-------------|
| 0 | **Depot prerequisites** — connection pool, migrations, transactions, LISTEN/NOTIFY | Depot core | Part of Depot roadmap |
| 1 | **Layer 1 core** — job table, enqueue, worker pools, execute, retry, scheduled | Phase 0 | 2–3 weeks |
| 2 | **Layer 1 polish** — recurring/cron jobs, unique jobs, pruning, telemetry hooks | Phase 1 | 1–2 weeks |
| 3 | **Layer 2 prototype** — event log, activity execution, basic replay | Phase 1 | 3–5 weeks |
| 4 | **Layer 2 full** — timers, signals, sagas, child workflows, versioning | Phase 3 | 4–6 weeks |
| 5 | **Layer 3 scheduler** — DAG declaration, dependency resolution, cron dispatch | Phase 1 | 2–3 weeks |
| 6 | **Layer 3 dashboard** — Bastion routes, Islands UI, job/workflow monitoring | Phases 2, 4, 5 + Islands stable | 3–4 weeks |

Total: roughly 15–23 weeks of focused work, but most of it can't start until Depot and Bastion's actor system are solid.

---

## Open Questions

- **Naming**: Forge.Jobs? March.Queue? Something else entirely?
- **Multi-node**: Initially single-node (one app instance). Multi-node coordination (leader election, work stealing across instances) is a later concern — Depot/Postgres advisory locks can handle basic coordination.
- **Observability**: Hook into the structured logging / telemetry system (see `specs/bastion/logging-observability.md`). OpenTelemetry spans per job/workflow?
- **Testing**: How do users test workflows? Mock activity execution? Time travel for timer-based workflows?
- **Quotas/rate limiting**: Per-queue rate limits? Global concurrency caps? Probably Layer 1 Phase 2.
- **Dead letter queue**: What happens to permanently failed jobs? Archive table? Callback hook?
- **Workflow determinism enforcement**: Can the type system help here? Linear types to prevent side effects in workflow replay code?

---

## Relationship to Existing Specs

- `specs/bastion/depot-integration.md` — Depot is the persistence backbone for all three layers
- `specs/bastion/channels.md` — Channels/PubSub could be used for real-time job status broadcasts
- `specs/bastion/islands-devtools.md` — DevTools could gain a jobs/workflows panel
- `specs/bastion/logging-observability.md` — Job/workflow telemetry feeds into this
- `specs/bastion/configuration.md` — Queue configuration, retry policies, cron schedules
