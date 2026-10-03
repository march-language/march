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

**Cumulative, R2 against main (2026-10-03, quiet box, A/A -0.04% with
half-IQR 1.06%):** `fanin_flood` at one scheduler is **+1.68% to +2.11%** over
five runs (main vs the merged branch, before and after the review fixes,
with the socket off and on); at eight schedulers it is inside the noise
(-0.66% to +1.25%). Every commit passed against its predecessor; the sum
does not pass the 1% one-scheduler gate. What was tried:
- Bisecting by removing one counter at a time (n = 200 each): `msgs_in`
  -0.17%, `msgs_out` +0.28%, the dispatch pair (`slices`, `last_run_ms`)
  -1.13%. Moving the dispatch pair beside `reductions` (the cache line the
  dispatch already writes) left the total at +1.83%.
- Keeping the dispatch pair only while the observe socket runs: +2.11% with
  the socket off, +1.68% on. So the dispatch pair is not the whole cost, and
  the gating was reverted.
The remaining ~1% is spread over commits that do not touch the message path
(R2.3 +0.84%, R2.4 +0.79% against their predecessors), which reads as code
size and placement in `march_runtime.c`; separating 0.5% effects would need
n of about 400 per variant. Recorded as an open result, not a pass.

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
