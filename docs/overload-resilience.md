---
layout: docs
title: Overload & Resilience
nav_order: 10.9
permalink: /docs/overload-resilience/
---

# Building Actor Systems That Survive Overload

A system's behavior at 10× its expected load is a design property, not luck. An actor
system with unbounded queues and eager restarts fails the same way everywhere: queues
grow until memory runs out, latency climbs toward infinity while throughput stays flat,
and the process dies with a full mailbox instead of shedding the work it could not do.

March gives you four tools to make overload *degrade* instead of *collapse*: bounded
mailboxes, backpressure, load-shedding counters, and backoff-governed supervision. This
guide is the practical tour of using them together. The API reference for each piece
lives in [Actors]({{ site.baseurl }}/docs/actors/) and
[Supervision Trees]({{ site.baseurl }}/docs/supervision/).

---

## Step 1: Bound every mailbox that strangers can send to

An actor drains its mailbox one message at a time, so its throughput is capped at one
core. Any producer faster than that grows an unbounded mailbox indefinitely. The first
decision for every actor that receives external traffic (an ingress actor, a worker fed
by a socket loop, anything a burst can reach) is its capacity and overflow policy:

```march
let pid = spawn(IngestWorker)
Actor.set_queue_limit(pid, 1024, 3)   -- cap at 1024, block_sender
```

Choosing a policy is choosing *who absorbs the overload*:

- **`3` (`block_sender`)** makes backpressure **transitive**: a full mailbox parks the
  sending green thread until the consumer drains below the low-water mark, so pressure
  propagates backward until it reaches the real source, usually a socket read loop,
  which then naturally stops reading and lets TCP push back on the client. No message is
  lost. Use this on internal pipelines where every message matters, and always when the
  actor answers `Actor.call` (a dropped call request cannot be told apart from a lost
  reply).
- **`1` (`drop_new`)** sheds the *newest* work. Right for load shedding at the edge:
  when you are already behind, the kindest thing to do to the system as a whole is
  refuse fresh work fast. The producer keeps running; the dropped count is observable.
- **`2` (`drop_old`)** sheds the *oldest* work. Right for last-value-wins streams:
  sensor readings, status updates, anything where a stale message is worth less than a
  fresh one.
- **`0`, unbounded** (the default) is fine for actors only your own code can reach at
  bounded rates. It is the wrong default for anything a herd can find.

The policies and their exact semantics (including how the interpreter treats
`block_sender`) are specified in the
[Mailbox Limits reference]({{ site.baseurl }}/docs/actors/#mailbox-limits-and-backpressure).

## Step 2: Watch the counters, shed before you fall over

Load-shedding decisions need inputs. The `Scheduler` module exposes the runtime's own
counters:

```march
let depth   = Scheduler.runq_depth()          -- cross-thread run-queue backlog
let live    = Scheduler.live_procs()          -- green threads alive right now
let dropped = Scheduler.dropped_messages()    -- shed by drop policies, cumulative
let queued  = mailbox_size(pid)               -- one actor's current queue depth
```

`mailbox_size` needs a `Pid`, which a monitoring loop rarely has on hand. For an actor
registered under a name, `Actor.whereis(name)` supplies one, and keeps supplying one
across supervisor restarts, where a cached `Pid` would have gone stale:

```march
match Actor.whereis("ingest") do
  Some(pid) -> check_depth(mailbox_size(pid))
  None      -> ()                 -- not registered, or mid-restart
end
```

Resolve once and cache the `Pid` on a hot path, re-resolving on `None`; repeated lookups
of the same name contend on the stored value's reference count. There is still no way to
*enumerate* live actors, so this works for actors you can name in advance, not for
discovering an unknown hot one; see
[`specs/todos/2026-08-12-per-actor-introspection-and-alarms.md`](https://github.com/march-language/march/blob/main/specs/todos/2026-08-12-per-actor-introspection-and-alarms.md).

A practical shedding pattern is checking a worker's depth at the *dispatch point*:
whatever hands work to the worker declines in microseconds when the worker is behind,
instead of enqueueing onto a backlog that has already lost:

```march
fn submit(worker, job) do
  if mailbox_size(worker) > 500 do
    Rejected                        -- shed fast: answer "busy" now
  else
    send(worker, Work(job))
    Accepted
  end
end
```

Rejecting in microseconds is what keeps the latency of *accepted* work flat while load
exceeds capacity. A monitoring loop that samples `Scheduler.dropped_messages()` over
time tells you how often you are actually shedding; a steadily climbing count is your
signal to scale out, long before anything crashes.

## Step 3: Give callers deadlines they can trust

`Actor.call(pid, Req, timeout_ms)` is deadline-honest under load: the caller **parks**
until the reply or the deadline (it does not spin, so a thousand waiting callers cost
the scheduler no effort), and replies are correlation-checked: a reply that arrives after
its call already timed out is discarded, never delivered as the answer to a later call.
That means the timeout you write is a real end-to-end bound you can build retry and
fallback logic on:

```march
match Actor.call(pid, FetchReq, 200) do
  Ok(v)  -> v
  Err(_) -> cached_fallback()     -- shed to the degraded path, don't wait
end
```

Under overload, prefer short timeouts plus an explicit fallback over long timeouts that
make every caller inherit the slowest actor's backlog.

## Step 4: Let supervision heal without burning the node

Crash-restart is self-healing only if restarting is cheaper than crashing. A child that
crashes instantly on a poisoned message or a dead dependency would otherwise respawn at
full CPU speed until its budget trips. March's supervisors apply **exponential backoff
with jitter** to repeat crashes automatically: the first crash restarts immediately
(fast recovery for one-off failures), and consecutive crashes back off: 50ms, 100ms,
200ms … capped at 3200ms pre-jitter, ±25% jitter so a herd of crashing children doesn't
restart in lockstep. The streak resets once a child stays up through a full budget window.

You don't configure any of this (you get it by having a supervisor at all), but you
should *size the restart budget* for your failure model: `max_restarts` within `window`
is the point where restarting stops being self-healing and escalates to the parent.
During a real downstream outage, backoff means the supervision tree idles between
attempts instead of consuming the CPU your still-healthy actors need to serve degraded
traffic.

Watch it work with `MARCH_SUP_TRACE=1`, which logs each backoff decision to stderr. The
strategies, budgets, and escalation rules are in the
[Supervision reference]({{ site.baseurl }}/docs/supervision/).

## Putting it together

A resilient shape for a service that must survive a thundering herd:

1. **Edge actor**: `drop_new` with a modest cap, plus an explicit busy-reply above a
   depth threshold; sheds excess load in microseconds.
2. **Internal pipeline**: `block_sender` everywhere: no loss inside the system;
   pressure propagates back to the edge, which is the only place that drops.
3. **Callers**: short `Actor.call` deadlines with fallbacks; accepted work stays fast.
4. **Supervision over every worker**: crashes heal with backoff; poisoned input costs a
   bounded restart rate, not the node.
5. **A metrics loop** sampling `Scheduler` counters, so "we are shedding" is a
   dashboard fact, not a post-mortem discovery.

For *streaming* workloads (a fast producer feeding a slow consumer through
transformation stages), reach for [Flow]({{ site.baseurl }}/docs/flow/) instead of
hand-built actor pipelines: its demand protocol is the same backpressure idea packaged
as a pipeline API. For spreading load across a cluster, continue to
[Clustering & RPC]({{ site.baseurl }}/docs/clustering/).
