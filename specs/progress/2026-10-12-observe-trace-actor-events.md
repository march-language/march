# Observe: trace actor events (Sent, Received, Spawned, Exited, Dropped)

**Date:** 2026-10-12
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), the deferred part of R8.
**Design:** [`2026-09-23-per-actor-introspection-design.md`](../2026-09-23-per-actor-introspection-design.md) section 5.1/5.2, stage C1.
**Builds on:** [`2026-10-11-observe-r8-tracing.md`](2026-10-11-observe-r8-tracing.md).
**Still open:** [`todos/2026-10-11-observe-trace-actor-events.md`](../todos/2026-10-11-observe-trace-actor-events.md) (arity, `Recon` wrappers, TUI panel, interpreter, payload C2).

## What shipped

A trace session may now also record **actor events** for a small set of named
actors, under the same mandatory `Count`/`Rate` limit, lifetime and idle timers
and 4-session cap as R8's boundary-call sessions.

- `TRACE_START` takes `events:<kinds>` (`sent,received,spawned,exited,dropped`)
  and `pids:<p,..>` (1..8). `fn:` becomes optional, so a session may watch
  calls, actor events, or both. The reply echoes `events` and `pids`.
- `TRACE_DRAIN` returns actor events as
  `{kind, pid, peer, msg_tag, reason, epoch, at_ns}`. In a session that asked
  for actor events its boundary-call events also say `"kind":"call"`; in a
  calls-only session the JSON is byte-for-byte R8's.
- `stdlib/trace.march`: `Trace.start(c, names, limit)` is unchanged (it is
  `start_with(c, calls(names), limit)`). New: `type EventKind`, `Options`,
  `ActorEvent`, `Trace.calls/actors/with_calls/start_with/format_actor`,
  `Batch.actor_events`, errors `PidsRequired` and `UnknownPid`.
- `forge observe --trace-start FNS --events KINDS --pids P,..` (`-` as FNS for
  no functions); early client-side refusals for the same mistakes.
- `docs/observe.md`: the JSON, the event table, the caps, what is not seen.

## Event semantics

| Kind | `pid` | `peer` | `msg_tag` | `reason` |
|---|---|---|---|---|
| `sent` | sender (`-1`: `main`, a task, a timer) | receiver | yes | - |
| `received` | receiver | - | yes | - |
| `spawned` | parent (an actor) | child | - | - |
| `exited` | the actor | - | - | `normal` / `killed` / `crash` |
| `dropped` | the recipient that did not get it | sender | yes | `dead` / `draining` / `full` / `evicted` |

`Sent` is recorded when a message is handed to the mailbox layer
(`march_sched_send`), so it covers `send`, `Actor.call`'s request and a timer
firing, and a refusal follows as a `Dropped`. `Received` is recorded in the
actor loop just before the handler is dispatched (not for epoch markers,
migrate messages or inspection requests). `Exited` fires at the top of
`do_actor_death_kind`, so it precedes the cleanups and `Down` messages, and
covers normal, `stop` (drain), `kill` and crash deaths. `Dropped` has four
sources: `march_send` to a dead actor (two spots) or a draining one, a
`DROP_NEW` mailbox refusing, a `DROP_OLD` mailbox evicting (the tag is the
evicted message's).

## Decision: an actor-event session without a pid filter is refused

There is no "all actors" form. `pids_required` if `events:` has no `pids:`,
`bad_args` for more than 8 pids or `pids:` without `events:`, `unknown_pid` for
a pid that is not a live actor at start.

Why: the count/rate limit bounds what the *ring* holds, not what the
*producers* pay. A node-wide stream makes every send on the node run the hook's
slow part (a clock read, atomic operations on counters shared by every
scheduler thread), and under a message storm a `Rate(n, s)` session spends that
on every message past its budget. With a filter the hook can decide with one
load of a per-proc word (`trace_mask`) it already holds a cache line for, and
only the named actors ever reach the shared counters. The cost of watching is
therefore proportional to the traffic of what you named, which is what an
operator wants anyway. It also caps what one debug-tier holder can make the
node do.

## Design: where the cost is

- `g_introspect_armed` (`march_scheduler.c`, alone on a 128-byte line): bit `i`
  set while session `i` records actor events. Written only by session
  start/stop/finish.
- `march_proc.trace_mask`: bit `i` set on the proc of every actor in session
  `i`'s pid list. It fills the 4-byte hole after `mbox_wait_mode` (on the line
  the send path locks), so no field moves for it. (`actor_pid1`, the pid
  index + 1, is the one new 8-byte field, **last** in the struct: 360 -> 368
  bytes. Placed earlier it shifted the layout and cost +11%; see below.)
- Hooks and what each costs **disarmed**:

| Hook | Where | Disarmed cost |
|---|---|---|
| Sent, Dropped(full/evicted) | `march_sched_send` | one relaxed load of `g_introspect_armed`, one never-taken branch (the loads in the DROP arms are on slow paths already) |
| Dropped(dead/draining) | `march_send` early returns | the same load, on paths that are already returning "dead" |
| Received | `actor_green_thread`, before dispatch | one relaxed load of `self->trace_mask`, one never-taken branch |
| Spawned | `march_spawn_common` | one relaxed load + branch (spawn is far heavier than that) |
| Exited | `do_actor_death_kind` | one relaxed load + branch |

- **Armed**: a hook ANDs the armed word with the masks of the procs it already
  holds and returns when the result is 0 (a bystander send: two loads). Only a
  named actor's event goes on: pids come from `proc->actor_pid1` (so an actor that has not run yet has one,
  and no meta, which can be retired while its proc lives, is dereferenced),
  the tag from the message header word, the epoch from the proc.
- `record_ev` is lock-free and allocation-free, and checks in the order that
  keeps a full/limited session cheap: session state, kind, pid list (rejects a
  stale bit), `Count` already reached, ring full (a counter), *then* the clock,
  deadline, idle, the `Rate` window (a plain load before the `fetch_add`, so a
  storm past budget does not also hammer the window counter) and the slot.
  Whatever happens, the producer never waits, locks or allocates.
- Stale bits (a session ended; its index reused for another filter) are
  harmless: `record_ev` re-checks the session's state and pid list, and the
  receiving actor clears bits that no longer apply to it.

## Message tag

Included. It is the `tag` word of the 16-byte object header (the constructor
tag, globally unique per constructor), read after an `IS_HEAP_PTR` guard like
the receive loop's own checks; an immediate (bare constant, small scalar) has
no tag and reads `null`. Nothing of the message's fields is read. It lets an
operator tell "which kind of message" without seeing "what it said". `Sent` reads
it *before* the enqueue (the receiver may consume the message the moment it is
pushed).

## Security notes

- Debug tier: signed, boot-bound, nonce/expiry, `$MARCH_DEBUG_POLICY`, audited.
  Audit `detail`: `session=N count=.. fns=K events=yes pids=P`; a refusal logs
  the same with the error as `result`.
- Bounded: 8 pids, 5 kinds, `events:` at most 63 chars, `pids:` at most 127;
  no unbounded or oversized list is accepted (`bad_args`).
- Contents: pids, a constructor tag, a reason code, time. No payload, no
  arguments. Payload rendering (C2) stays out and needs its own review.
- An operator holding only the debug tier learns which of the 8 named actors
  talk to which pids and how often. It is the same authority as `STATE`
  (which reads their state), which is why it is the same tier.

## Tests

- `test/native/trace_actor_events.march` (compiled `--hot-reload`, policy file
  as `trace_boundary`): every refusal (events without pids, nine pids, a pid
  that is not an actor, a negative pid, pids without events, nothing to
  watch, limits); a full flow (main sends to `p` -> Sent with pid -1 and peer
  `p`; `p` Received with the same tag; Spawned with the child as peer; `p`'s
  Sent to that child); kind filter; pid filter (another actor's traffic
  records nothing; a counterpart match when `main` sends to a named actor);
  a calls-only session unchanged; `MaxEvents(2)` bounds an event session
  exactly and stays at 2; `Rate(3, 60)`; Exited `killed` / `normal` /
  `crash` (a supervised child that panics); Dropped `dead` (send to a killed
  actor named by the session) and `full` (a `DROP_NEW` mailbox); a fresh
  session after a stop. Asserts counts, pids, kinds only, so it holds at any
  scheduler count (checked at 1, 2, 8).
- `test/observe_debug_check.ml` over `test/native/observe_debug.march` (now
  also messaging a `Beat` actor every 20 ms): every refusal at the verb level
  (`pids_required`, `bad_args` x7, `unknown_pid`, `limit_required`,
  `limit_out_of_range`), `Count(6)` over Sent+Received yields exactly 6 events
  and `done`/`why=count`, the exact key set of an event, `Sent` from `-1` to
  Beat with a tag, `Received` by Beat with no peer and the same tag, a mixed
  session (calls say `kind:"call"`), `Rate(2,1)` over Received for 2.5 s, four
  event sessions then `too_many_sessions`, and the audit detail.
- `forge/test/test_observe_cli.ml`: the client's early refusals.
- RED controls, by file copy, each restored after: hook removed in
  `march_sched_send` (Sent lines go to 0, 6 diffs); `Count` that never marks
  itself done (`done=false why=-`); no kind filter (`total=4` for `total=1`,
  and Exited/Dropped counts shift); unfiltered sessions allowed (both layers:
  `events without pids: STARTED`, and the socket fixture 3 FAILs, one of which
  leaks sessions); no Exited hook (`exited: total=0`); no Received hook; no
  Dropped hook on `march_send` (`dropped: n=0`).
  (`MARCH_SEND_DEAD` after `march_sched_send` is a race and has no
  deterministic fixture.)

## Cost: A/B (see the PR for the final numbers)

Compiled `--opt 2 --hot-reload`, A = `origin/main` 0c50b9a4c built and saved
beforehand, B = this branch, **A2 = a byte copy of A** (the A/A control), run
**interleaved and rotated** (A, B, A2 / A2, B, A ...), CPU time (user + system)
because wall time under this machine's load is mostly the other sessions. The
machine was at load average **44 to 219** (14 cores; other sessions' suites and
benchmarks) throughout, so single runs wobble by several percent; read the
medians against the A2 column, not against zero. Table is the final code.

| Program (what it stresses) | rounds | A median | B median | B vs A median / min | A2 vs A median / min |
|---|---|---|---|---|---|
| `sendstorm`, 1 scheduler (4 producers, 6M sends + 6M receives) | 60 | 651.7 ms | 653.9 ms | +0.34% / +1.41% | -1.14% / +0.55% |
| `bench/actor_ping.march`, 1 scheduler (send + receive per hop, 1M hops) | 40 | 1498 ms | 1508 ms | +0.63% / +3.23% | +0.86% / +1.61% |
| `bench/actors/call_storm.march`, default schedulers | 60 | 151.3 ms | 151.9 ms | +0.38% / +0.96% | -1.39% / -1.02% |
| `sendstorm`, 4 schedulers | 60 | 1637 ms | 1665 ms | +1.76% / -4.79% | +2.62% / +35.1% |
| `sendstorm`, 4 schedulers | 100 (earlier build) | 1533 ms | 1498 ms | -2.28% / +6.27% | +0.25% / +8.33% |

What this resolves and what it does not. With one scheduler the CPU time is the
cost of the send/receive path itself, and B is inside the A2 spread on every
run (earlier runs of the same pairs, B vs A median, with A2 vs A in
brackets: sendstorm -1.51 (-1.47), +1.38 (-0.14), -0.59 (-0.54), -0.94 (-1.62)%;
actor_ping -0.14 (-0.97), +0.21 (+0.34), +0.67 (+0.45)%). That
bounds a real disarmed cost at about +-1%, which is the one load + never-taken
branch. With several schedulers CPU time includes idle schedulers spinning,
which moves with the load on the box: the A/A control alone differs by up to
+-8% in the median there, so a multi-scheduler cost of a few percent cannot be
ruled in or out; no run showed more than the A2 spread **on the final code**.

Two layout traps found on the way, both fixed, both worth knowing:

1. Putting the new `actor_pid1` field in the middle of `march_proc` shifted
   every later field by 8 bytes and the 4-producer `sendstorm` read **+11% and
   +14%** (CPU median, two runs) against an A2 at +1%: a cache-line layout
   effect on a contended mailbox, not instructions. The field is now **last**
   (the observe counters did the same: "last so no existing field moves");
   `trace_mask` uses the 4-byte hole after `mbox_wait_mode`, so no field moves.
   `sizeof(march_proc)` 360 -> 368.
2. `g_introspect_armed` is alone on its own 128-byte line, because a neighbour
   in `.bss` that is written would turn the send path's load into a coherence
   miss.

**Armed**, the same `sendstorm` (6M sends, 1 scheduler), a session recording
`Sent`+`Received` (`Rate(1000, 1)`, so nearly every event is over budget and
counted) or `Sent` (`Rate(100000, 1)`):

| Session | CPU median vs no session | per matched event |
|---|---|---|
| names an actor nobody messages (the hooks run, find no match) | +3% to +7% (min -3%..+3%) | ~2-3 ns per send |
| names the sink; `Sent`+`Received`, `Rate(1000, 1)` | +43% to +61% | ~18-25 ns per event |
| names the sink; `Sent`, `Rate(100000, 1)` | +25% to +38% | ~22 ns per send |

With 4 schedulers and 4 producers hitting the one named sink (shared counters
at their worst) the same sessions cost +23% to +43% (load 116-175 then). So the
armed cost is a **constant per matched event** (a clock read, a handful of
atomic operations, and a ring slot when one is free), independent of how many
events the session has already dropped, and a producer never waits.

Sanitizers (Linux arm64 container `march-amdr-repro`, `--hot-reload`):
- **ASAN** (`MARCH_SANITIZE=1`): `trace_actor_events` output identical to the
  golden at 1, 2, 4 and 8 schedulers; the send storm with each of four
  sessions (none, a bystander, a named sink under a `Rate`, a named sink
  `Sent`-only) at 1 and 4 schedulers completes; the signed socket fixture
  (`observe_debug`) passes all 78 checks with no report from the node. The
  only report is LeakSanitizer at exit: float boxes `Json.parse_number` leaks
  on every `Trace`/`Recon` call that parses a number (known,
  [`todos/2026-10-08-json-parse-number-float-leak.md`](../todos/2026-10-08-json-parse-number-float-leak.md)),
  the test program's un-freed actors, and one 24-byte actor record in the
  storm programs, identical with no session at all; nothing from
  `march_trace.c`.
- **TSAN** (`MARCH_SANITIZE=thread`): the same fixtures and the same
  scheduler counts, output identical, **no ThreadSanitizer report**; the
  socket fixture 78/78 with none from the node.


## Deferred

Arity, `Recon.trace_*`, the TUI panel, interpreter support, payload rendering
(C2) and INHERIT: see the todo. Also not reported: `Dropped` for `Actor.call`
to a dead actor (it never reaches `march_send`), and `Dropped(draining)` has no
fixture (it needs a shutdown in flight).
