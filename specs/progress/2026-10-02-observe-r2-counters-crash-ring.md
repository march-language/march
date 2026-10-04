# Observe R2: per-actor counters, scheduler utilisation, crash ring, TOP

**Date:** 2026-10-02
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R2.
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).
**Builds on:** [`2026-10-02-observe-r1-snapshot-verbs.md`](2026-10-02-observe-r1-snapshot-verbs.md).

## What exists now

- **Per-actor counters** at the end of `march_proc` (no existing field moves),
  each with one writer, bumped with a relaxed load and store
  (`march_proc_bump`, no atomic read-modify-write):
  - `slices`: dispatches, at the dispatch site in `sched_loop`.
  - `last_run_ms`: the dispatching scheduler's coarse clock (`now_ms`,
    refreshed every 1024 dispatches and on the idle path; never a clock read
    per dispatch). Rows report `idle_ms` since then.
  - `msgs_in`: user messages a receive delivered. Counted in the receive-side
    pops (`mbox_recv_user`, the actor loop's `march_sched_recv_actor_ex`), not
    in `mbox_pop_user` itself, which is also DROP_OLD's eviction run on the
    SENDER's thread (that would count a dropped message as received and give
    the counter a second writer).
  - `msgs_out`: in `march_sched_send` on the success path, on the sending proc
    read once before any BLOCK park (the proc pointer stays valid across the
    park; only `tl_sched` may change). So Actor.call requests and replies count.
  - `held`: messages an `Actor.call` has taken off its mailbox while waiting
    (set by `call_held_push`, cleared by `call_held_restore`). Requeued
    messages are subtracted from `msgs_in` so each delivery counts once.
- **Scheduler idle time** (C12): `idle_ns` and `started_ns` on
  `march_scheduler`, timed only on the idle path (two clock reads around the
  1 ms sleep it already takes). `SCHED [window_ms]` (default 200, max 5000)
  samples, sleeps on the observe thread outside any critical section,
  samples again, and reports per-scheduler and overall `utilisation` plus
  `lifetime_utilisation`. `SNAPSHOT`'s sched section is lifetime-only, so it
  never sleeps. `march_scheduler` is now 64-byte aligned (it was 33 760 bytes,
  so neighbours shared a cache line).
- **Crash ring**: the last 256 crashes under a leaf mutex taken only on a
  crash. Entries: seq, pid, type, kind (`crash`, `draining` for a hot-reload
  hard-deadline kill, `panic` for an unsupervised panic just before exit),
  code epoch, supervisor, restart number (the slot's crash streak, read after
  the supervisor is notified), wall-clock time, and the message, kept for R4's
  debug tier. `draining` is passed to the death path as a parameter: a
  thread-local set around the call would leak, since the death path runs
  cleanup closures that can switch green threads.
- **Verbs**: `CRASHES [n]` (no message, C7); `TOP mbox|crashes|slices|msgs_in|msgs_out <n> [window_ms]`,
  where the counters rank by their change over two walks `window_ms` apart.
  Rows gain `slices`, `msgs_in`, `msgs_out`, `idle_ms`, `held`, `crashes`,
  `child_crashes`, `spawned_by`. `ACTORS mbox`, `TOP mbox` and `MEM` count held
  messages as waiting work. `SNAPSHOT` gains a `crashes` section.
- **`spawned_by`**: the pid of the actor that spawned it (one lock-free
  `find_meta` at spawn, stored before the pid is published; -1 from creation).
  `TREE` nests an unsupervised actor under a live spawner, each node saying
  `link: supervised | spawned`; `ACTOR` lists what an actor spawned.

## A/B (rule 3)

Linux arm64 container (`march-amdr-repro`), same compiler, runtime swapped;
`bench/actors/*.march --opt 2`, interleaved. Gate: 1 scheduler within 1%,
8 schedulers within the base arm's half-IQR.

| Commit | Against | fanin_flood 1 sched (n=200) | 8 sched (n=200) | call_storm 8 | spawn_churn |
|---|---|---|---|---|---|
| R2.1 as first written | main | **+1.98% FAIL**, repeat **+1.66% FAIL** (A/A +0.77%) | +0.27% | +0.89% | -0.11% |
| R2.1 reworked + R2.2 | main | +0.52% | +0.19% | | |
| R2.2b padding | R2.2 | +0.02% | -0.56% | +0.26% | +3.13% (8, n=40, IQR 8%) |
| R2.3 crash ring | R2.2b | +0.84% | +0.76% | | -1.16% (1, n=60, faster), +1.44% (8) |
| R2.4 spawned_by | R2.3 | +0.79% (n=100) | | | -0.08% (1, n=200), -2.23% (8) |

**Cumulative (2026-10-03).** Paired two-binary runs first read R2 against
main at +1.7% to +2.1% at one scheduler. A better-controlled run replaced them:
every version at once, in a fresh random order each round (no fixed
predecessor), 300 rounds, with an A/A copy of the base and bootstrap 95%
intervals on the median difference (`fanin_flood`, one scheduler, Linux):

| Arm | Against the pre-R2 base (302cd96) |
|---|---|
| A/A (copy of the base) | -0.04% [-0.27, +0.19] |
| R2.1 + R2.2 | +0.23% [+0.01, +0.48] |
| + R2.2b padding | +0.35% [+0.12, +0.62] |
| + R2.3 crash ring | +0.86% [+0.64, +1.11] |
| + R2.4 spawned_by (R2 as written) | +0.92% [+0.73, +1.16] |
| main after #766 (R2 + 7 other commits) | +1.23% [+1.00, +1.48] |
| + review fixes | +1.54% [+1.33, +1.87] |

So R2 costs about 0.9% at one scheduler, inside the 1% gate, and the review
fixes about 0.3% more (their interval overlaps main's). The strict A/B
alternation read high. The R2.3 step (+0.5%) does not touch the message
path (`fanin_flood` spawns one actor and kills none), so it is code
placement in `march_runtime.c`, not work. A first bisect by removing one
counter at a time (paired runs, so read with the same caution) put the
dispatch pair (`slices`, `last_run_ms`) at about 1%; moving it beside
`reductions`, or keeping it only while the socket runs, did not change the
total, and the gating was not kept.

**R2.1 failed its gate and was reworked, not tuned:** `msgs_out` was a
non-inlined call into the scheduler to read TLS on every `march_send`. But
`march_sched_send` already reads the sending proc for the epoch stamp, so it
now reads it once and bumps on success; `march_send` is back to main's code.
That rework was measured together with R2.2 (idle time touches only the idle
path), which is recorded as such.

## Review fixes (2026-10-03)

An independent review found no memory-safety, deadlock or single-writer
defect, and these, all fixed:
- **`idle_ms` was stale on a busy scheduler.** The coarse clock was refreshed
  every 1024 dispatches, so running actors read up to ~0.7 s idle (measured).
  The preemption daemon now publishes a 1 ms coarse clock (`g_coarse_ms`, its
  own cache line) that the dispatch reads; the per-scheduler clock is only
  the fallback when no daemon runs. Test: four running spinners must read
  under 50 ms in five samples (red without the publish: values to 312 ms).
- **`TREE` allocated memory proportional to the largest pid** (pids are never
  reused): membership is now a binary search over the live pids.
- A scheduler that had not started counted as fully busy in `SCHED`'s
  window average.
- A windowed `TOP` holds its connection thread for the window: the cap is now
  5 s (was 10) and at most two run at once (`busy` otherwise), so they cannot
  take all eight connections.
- Test margins: the sched fixture idles 3 s (was 1.5), the crash fixture
  waits 500 ms between crashes (was 200; restarts back off with jitter).

## Tests

- `test/native/observe_counters.march` (mode `counters`): a ping-pong pair
  after 200 round trips reads exactly `msgs_in = msgs_out = 200` on the
  receiving side and 201/200 on the kicking side; an actor blocked in an
  `Actor.call` with 150 messages behind it shows `held = 150`, `mbox = 0`, is
  ranked first by `ACTORS mbox`, and counted by `MEM`. Red with the actor
  loop's `msgs_in` bump removed.
- `test/native/observe_sched.march` (mode `sched`, 4 schedulers): idle under
  5%, four spinners over 90%, `SNAPSHOT`'s section lifetime-only, window cap.
  Red with idle time not accumulated (idle reads 1.000).
- `test/native/observe_crashes.march` (mode `crashes`): a child panicking three
  times gives three `crash` entries with restart numbers 3, 2, 1 under one
  supervisor and no message; the supervisor's row has `child_crashes = 3`;
  `TOP crashes` ranks it first; `TOP msgs_in 1 300` ranks a self-sending actor
  first; argument errors; the `crashes` section; `maker`'s two spawned actors
  nest under it with link `spawned`. Red with the ring write removed, and with
  the message added to `CRASHES`.
- `test/test_observe.c`: 42 checks (+1: an integral double is written `1.0`;
  the writer used to emit `1`, which a typed client reads as an integer).

ASAN (Linux, Docker): the churn stress (16 churners spawning, registering and
killing actors, socket polled with every verb including `TOP msgs_in` windows,
`SCHED 20`, `CRASHES`) is clean 3/3, ~270 polls each, 0 bad replies. Corpus
sweep (rule 4), rerun 2026-10-03 on the merged branch: 82 actor fixtures, each
with the socket polled every 10 ms through every verb including `CRASHES`, `TOP`
windows and `SCHED 20`; 81 exit 0 with no AddressSanitizer report.
`sched_stress` aborts on ASAN shadow-memory exhaustion, identically with no
socket (control run), as in R1.

## Deviations from the plan

1. **No interpreter parity yet.** The plan adds the four counters to the
   interpreter's `actor_inst` so `Recon` tests run on both backends. Nothing
   reads them until `Recon` exists, so they land with R3, which adds it.
2. **No `stack` attribute in `TOP`**: the runtime has no cheap per-proc stack
   depth (stacks grow by mapping pages); left out rather than estimated.
3. **No backtrace in ring entries and no `Logger` emission.** The compiled
   `Logger` appenders are no-ops
   ([`todos/2026-09-26-compiled-logger-appenders-are-no-ops.md`](../todos/2026-09-26-compiled-logger-appenders-are-no-ops.md)),
   and the plan's stderr fallback was not added either: a supervised crash is
   silent on stderr today (only `MARCH_SUP_TRACE` prints anything), and a new
   line per crash would change the output of every golden that crashes a
   supervised child. The ring is the record; R7's crash dump prints it.
4. **`crashes` alone was not enough.** A restarted child has a new pid, so a
   crash-looping slot's entries all land on dead pids and every live row reads
   0. Rows also carry `child_crashes` (entries whose supervisor is that pid),
   and `TOP crashes` ranks by both.
5. **R2.3 left the R1 golden stale** (it added verbs and a section that R1's
   checker lists); R2.4 brings it up to date.
