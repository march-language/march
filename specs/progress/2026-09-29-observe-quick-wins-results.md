# Observe quick wins: results

**Date:** 2026-09-29
**Plan:** [plans/2026-09-29-observe-quick-wins-plan.md](../plans/2026-09-29-observe-quick-wins-plan.md)
**Prototype code:** branch `proto/observe-quick-wins` (not merged), tip `d4c79f33b`.
**Box:** the shared arm64 development Mac. Other sessions' test suites ran
throughout: load average 12–59 outside the gated benchmark pairs. QW2 pairs ran
only at load < 10 (the runner waits); QW1, QW3 and QW4 ran at load 12–48 and their
timings carry that caveat.

| # | Verdict | One line |
|---|---|---|
| QW1 | PASS | The existing APIs find a planted slow consumer; they cannot say what kind of actor it is, whether the node is CPU-bound, or whether anything crashed. |
| QW2 | PASS (at this box's resolution) | No counter site shows a measurable cost; one of three full-patch runs crossed the 1% line and did not reproduce. |
| QW3 | 2–5 s band | A shell on today's hot deploy works: 2.9 s median round trip, 2.6 s of it compile; patches are 53–89 KB. |
| QW4 | PASS | A foreign pthread walked 20 000 actors under 1 M spawn/kill churn: 200/200 replies, p99 4.6 ms; Linux ASAN clean on a reduced workload. |

Three pre-existing bugs surfaced (§Bugs found). One was fixed on `main` the next day; the other two are filed as todos.

## QW1 recon-lite: PASS

- Reports naming `slow_consumer` first: **3/3**. Mailbox depth across the three
  reports, 1.5 s apart: 19 552 → 18 884 → 18 218 (draining at ~445 msg/s; the
  consumer sleeps 2 ms per message, so ~500/s is the ceiling).
- Operator questions:
  1. Which actor is the bottleneck? **Yes**, but only because the demo registered
     names. An unnamed actor is a bare pid index.
  2. Growing or shrinking? **Yes, by hand**: diff two reports. No rate is reported.
  3. What type of actor? **No**: nothing maps a pid to its actor type.
  4. CPU-bound? **No**: there is no utilisation figure.
  5. Anything crashed? **No**: there is no crash data.
  Every "no" is a field the big plan already builds (R1 `type`, R2 windowed `TOP`,
  R2 idle time, R2 crash ring). No over-build found.
- Compiler friction while writing 60 lines:
  - A module that only *receives* `Cap(Actor.Introspect)` must declare
    `needs Actor.Introspect` (both modules hit it).
  - `Actor.top_by_mailbox` could not be used: its return type does not unify with
    `pid_to_int`. This turned out to be a real bug (§Bugs found, 1).
  - An actor named `Fast` collides with a stdlib constructor (`Level.Fast`);
    renamed to `FastSink`.
  - There is no reverse lookup from pid to registered names; the report scans
    `Actor.registered` × `Actor.whereis`.

## QW2 counter cost: PASS at this box's resolution

`bench/actors/fanin_flood.march`, `--opt 2`, same-box interleaved A/B, base =
the runtime before the patch (a copy passed through `MARCH_RUNTIME_DIR`).

| run | scheds | n | base med | patched med | delta | base ±half-IQR | verdict |
|---|---|---|---|---|---|---|---|
| A/A control | 1 | 40 | 54.5 ms | 54.2 ms | −0.49% | 8.45% | PASS |
| A/A control | 8 | 40 | 103.1 ms | 101.4 ms | −1.57% | 5.39% | PASS |
| registered A/B | 1 | 40 | 52.6 ms | 52.4 ms | −0.52% | 3.27% | PASS |
| registered A/B | 8 | 40 | 96.2 ms | 99.9 ms | +3.83% | 6.15% | PASS |
| higher-power A/B | 1 | 200 | 52.8 ms | 53.4 ms | +1.31% | 3.00% | FAIL |
| higher-power A/B | 8 | 200 | 99.5 ms | 104.4 ms | +4.95% | 6.11% | PASS |
| only dispatch bump | 1 / 8 | 200 | 52.5 / 105.0 | 52.6 / 104.9 | +0.15% / −0.15% | 1.61 / 6.65% | PASS |
| only receive bump | 1 / 8 | 200 | 52.3 / 102.3 | 52.3 / 99.6 | +0.00% / −2.61% | 2.25 / 6.29% | PASS |
| only send bump | 1 / 8 | 200 | 53.6 / 105.5 | 53.7 / 105.4 | +0.26% / −0.04% | 3.60 / 6.53% | PASS |
| full patch, repeat | 1 | 200 | 55.2 ms | 55.6 ms | +0.73% | 3.46% | PASS |
| full patch, repeat | 8 | 200 | 105.5 ms | 105.6 ms | +0.11% | 6.35% | PASS |
| call_storm (sanity) | 1 / 8 | 10 | 247.6 / 263.2 | 248.0 / 259.9 | +0.16% / −1.24% | 0.81 / 1.32% | PASS |
| spawn_churn (sanity) | 1 / 8 | 10 | 190.1 / 335.6 | 191.1 / 333.8 | +0.54% / −0.53% | 3.06 / 4.63% | PASS |

- **Non-vacuity:** with `MARCH_OBS_SPIKE_DUMP=1` the patched binary printed
  `obs-spike: idle_ns=1132660000 reaped_msgs_out=400000` (exactly the delivered
  count); the base binary printed nothing. Each single-site variant counted only
  its own site.
- **Reading it.** The registered verdict (n=40) is PASS. The first n=200 run
  failed the 1% line at one scheduler (+1.31%) and showed +4.95% at eight; the
  repeat gave +0.73% and +0.11%. No single site costs more than 0.26%. The base
  arm's own median drifted 52.3–55.2 ms between runs (±2.5%). The honest
  conclusion: the counters' cost is below what this box can resolve, which is
  roughly ±1.5% at one scheduler and ±5% at eight.
- **Consequence:** R2 stays as designed. The 1% gate sits at this box's noise
  floor, so the big plan's apparatus rule 3 now says: n ≥ 200, repeat a failing
  run once before bisecting, and treat the instruction-level argument as primary.

## QW3 shell round trip: 2–5 s band

A node built with `--hot-reload Hook`; each input rewrote one line of `Hook.run`,
built a `--compile-so` patch, deployed it with `test/hcr_deploy.exe` over the local
reload socket, then touched a trigger file the node polls. Load average 36–48.

| # | input | output (verbatim) | rendering | compile_s | deploy_s | run_s | total_s | so_bytes |
|---|---|---|---|---|---|---|---|---|
| 1 | `Scheduler.live_procs()` | `2` | useful | 2.61 | 0.24 | 0.07 | 2.92 | 53 480 |
| 2 | `Actor.top_by_mailbox(intro, 3)` | `[({ creation: 4309141808, local_pid: 1, node_id: "\000" }, 0)]` | **wrong** (bug 1) | 2.74 | 0.34 | 0.10 | 3.17 | 89 192 |
| 3 | `Actor.whereis(intro, "counter")` | `Some(Pid(0))` | useful | 2.59 | 0.29 | 0.11 | 2.99 | 70 296 |
| 4 | `List.map(Actor.list(intro), fn p -> mailbox_size(p))` | `[0]` | useful | 2.65 | 0.26 | 0.07 | 2.97 | 54 488 |
| 5 | `(1, "two", Some(3.5), [4, 5])` | `(1, two, Some(3.5), [4, 5])` | strings unquoted | 2.57 | 0.25 | 0.07 | 2.89 | 54 552 |
| 6 | `Scheduler.live_procs()` (repeat) | `2` | useful | 2.59 | 0.07 | 0.09 | 2.75 | 53 480 |
| 7 | `println("side effect")` | node printed `side effect`; result `0` | unit renders `0` (bug 3) | 2.59 | 0.23 | 0.06 | 2.88 | 53 784 |

- **Median total, inputs 1–6: 2.95 s**, of which compile is ~2.6 s, deploy
  0.07–0.34 s, trigger-to-output under 0.11 s. A repeat input is not faster:
  every input recompiles the whole program.
- **Patch size is not the problem.** A whole-program `--compile-so` patch for this
  app is 53–89 KB. The fragment-emission item (R5.5) is worth doing for compile
  time, not bytes.
- **Input 7 was accepted, and that is correct for this prototype, not a gate bug.**
  `Hook.run` takes the root `Cap(IO)`, so its manifest line reads `caps=IO` before
  and after, and root IO already covers `IO.Console`. The consequence for the real
  shell: a fragment's entry point must take **only narrowed capabilities** as
  parameters, never `Cap(IO)`, or the capability check is vacuous. Added to R6.
- **Deploy noise:** each `hcr_deploy` printed "12175 function(s) are new and
  require a server restart" (the whole stdlib), and "function signature changed"
  although `Hook.run`'s `sig_hash` was identical in both manifests. Neither blocked
  anything; both would drown a user-facing shell's output.
- **Rendering:** `to_string` leaves strings unquoted inside containers on both
  backends, and renders `()` as `0` compiled only. A shell needs a debug renderer
  that quotes strings. R5.7 stays mandatory.

## QW4 foreign-thread walk: PASS

- **RED:** before the patch, `MARCH_OBSERVE_SOCKET` created no socket.
- **GREEN:** `PING` → `PONG`; one `ACTORS` walk of 20 001 actors took 3 801 µs.
- **Under churn** (20 000 idle actors, a task doing 1 000 000 spawn+send+kill; 300 000
  finished before 200 polls could overlap it): 200 replies, **0 errors**,
  took_us **p50 3 429, p99 4 579, max 5 763**, count 20 000–20 003. The program
  finished its churn and exited normally.
- **Linux ASAN (Docker, arm64, glibc):**
  - The full workload aborts with ASAN out-of-memory (`ReserveShadowMemoryRange
    failed`) **with or without the spike active**, also with
    `detect_stack_use_after_return=0`: 20 000 actors plus 1 M spawns exceed ASAN's
    mappings. Before aborting, 100 polls answered with p50 7.9 ms, p99 9.5 ms.
  - Reduced workload (2 000 actors, 50 000 churn), same code paths: control and
    spike-active runs both report **0 ASAN errors**; 562 polls during churn, all
    answered.
  - Both runs, and a run on the **unpatched** runtime, report the same
    LeakSanitizer leak: 1.2 MB in 50 000 × 24-byte objects allocated in
    `march_send` (bug 2).
- **Consequence:** the big plan's C16 ("a foreign thread can read procs this way")
  is confirmed. R0/R1 keep their architecture.

## Bugs found

1. **`Actor.top_by_mailbox` / `Actor.over_mailbox` return a type-confused pid.**
   Their annotation `List((Pid, Int))` resolves the bare `Pid` to
   `GlobalPid.Pid = { node_id, local_pid, creation }` (`stdlib/global_pid.march:11`),
   not the builtin `Pid(a)`. Compiled code then reads an actor pointer as that
   record (QW3 input 2). **Already fixed on `main`** by PR #709 (`c0ebe7c8d`,
   2026-09-30), found independently by a stdlib type-error sweep; the annotation
   is now `List((Pid(a), Int))`. No todo filed.
2. **A discarded `send` result leaks 24 bytes per send (compiled).**
   `march_send` returns a heap `Some(())` (`march_alloc(16 + 8)`); a `send(...)`
   used as a statement never frees it. Reproduced on the unpatched runtime. Filed:
   [`todos/2026-09-29-discarded-send-result-leaks.md`](../todos/2026-09-29-discarded-send-result-leaks.md).
3. **Compiled `to_string(())` prints `0`; the interpreter prints `()`.** Filed:
   [`todos/2026-09-29-compiled-unit-to-string-prints-zero.md`](../todos/2026-09-29-compiled-unit-to-string-prints-zero.md).

## Deviations from the plan

- Task 0's "today's mtime" check was wrong: dune restores binaries from its shared
  cache with the cached artifact's mtime. `dune build` exiting 0 is the check.
- QW1 and QW3 modules gained `needs Actor.Introspect`, and QW1's actors were
  renamed (see QW1 friction); QW1 computes its top-5 itself instead of calling
  `top_by_mailbox`.
- QW2 added three n=200 runs and a per-site bisect beyond the registered n=40
  A/B; the registered verdict is reported unchanged beside them.
- QW4 raised churn from 300 000 to 1 000 000 (the plan's own contingency); the
  ASAN run used a reduced workload plus a control run, because the full one
  exhausts ASAN's memory with or without the spike.

## Changes made to the big plan

- Apparatus rule 3: n ≥ 200, repeat a failing run once before bisecting, the
  instruction-level argument is primary; this box resolves ~±1.5% at one scheduler.
- C16: marked "confirmed by QW4".
- R3: notes that `top_by_mailbox`'s pid type was fixed by #709, which `Recon` relies on.
- R5.1: replaced "measure first" with the measured numbers.
- R5.7: adds "quote strings; render `()`" to the renderer's requirements.
- R6.1: a fragment's entry takes only the narrowed caps from `$MARCH_SHELL_POLICY`
  as parameters, never `Cap(IO)`.
