# Distributed deploys, groundwork G1: the hot-reload boundary cost, measured

**Parent:** [../plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md), G1;
[../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), II.7 and II.4.1.
Consumed by `specs/todos/2026-09-22-dd-step05-model-b-spike.md`. Closes
`specs/todos/2026-09-22-dd-g1-boundary-cost-measurement.md` (this file replaces it).

Measured 2026-09-23 on the 14-core Apple-silicon Mac, compiler and runtime built at
origin/main `12c062761` (PR #587). Main has since changed runtime/march_runtime.c
(actor `on_stop`, parameterised `init`, dead-proc reclamation) but not the per-message
`hcr_enter`/`enter`/`leave` path or the compiled call sites measured here.
As G1 says, the prototype code did not land: only the numbers.

## Verdicts, in II.7's terms

1. **`--hot-reload` versus plain on `list_ops`: about 1 %, far below the 10 % threshold,
   so Model B does not have to come first.** On `list_ops_nested`, the variant that puts
   the helpers on the boundary, the medians are 0.094 s versus 0.093 s
   (+1.1 %), inside the run-to-run spread. `list_ops` itself, with nothing on the
   boundary, reads -1.9 %. Hot-reloadable production builds (D8) hold on today's
   dispatch; build steps 6–12 do not wait on the Model B spike.
2. **`enter_unit` versus `enter` on `actor_ping`: not measurable, so the epoch read stays on
   the call path as II.4.1 designs it; no hoist.** `unit0` 1.314 s and `unit1` 1.308 s
   against `hr` 1.313 s (+0.1 % and -0.4 %), while `hr`'s own five runs span
   1.300–1.598 s. The hoisted variant is no faster (`hoist0` 1.313 s, `hoist1`
   1.345 s). On `list_ops_nested` too the unit variants sit within 1 % of `hr`. The hoist
   variants read about 4 % above `hr` there; their compiled sites add one call hop
   (`enter_gen` with a constant, which forwards to `enter`), but a handful of dynamic
   boundary calls per run cannot cost 4 ms, so that is layout or noise, not a cost.

Both verdicts carry the caveat under "Conditions": samples ran at 1-minute load 6.5–7.7,
not the planned 5 or below.

## The numbers

Wall time in seconds per run, median of five, `[min-max]`; the percentage is the
median against `plain` on the same benchmark. Every sample started only when the
1-minute load average was at or below 8 (see "Conditions" for why not 5; the load at
each sample is in the per-sample table there). The plain
variant ran once first per benchmark and was discarded as warm-up. Runs were
interleaved (round 1 ran every variant once, then round 2, ...) so drift within
the session lands on every variant alike.

Variants: `plain` (no `--hot-reload`); `hr` (`--hot-reload <Mod>`, today's
`march_dispatch_enter`); `unit0`/`unit1` (`march_dispatch_enter_unit`: a
`march_sched_current()` TLS read plus a `code_epoch` load on every boundary call,
then `enter_gen`), with the proc epoch 0 and 1; `hoist0`/`hoist1` (the actor loop
reads `self->code_epoch` once per message and passes it to `enter_gen`; compiled
call sites call `enter_gen` with a constant), epoch 0 and 1. Epoch 0 short-circuits
`enter_gen` to plain `enter`, so it measures only the read; epoch 1 also runs the
two-slot ring scan.

| benchmark | plain | hr | unit0 | unit1 | hoist0 | hoist1 |
|---|---:|---:|---:|---:|---:|---:|
| `list_ops` | 0.068<br>[0.067–0.069] | 0.067 (-1.9%)<br>[0.066–0.475] | 0.070 (+2.3%)<br>[0.068–0.341] | 0.070 (+2.2%)<br>[0.068–0.072] | 0.068 (+0.3%)<br>[0.065–0.298] | 0.069 (+0.4%)<br>[0.067–0.302] |
| `list_ops_nested` | 0.093<br>[0.091–0.095] | 0.094 (+1.1%)<br>[0.088–0.361] | 0.095 (+1.8%)<br>[0.090–0.381] | 0.095 (+1.9%)<br>[0.090–0.098] | 0.098 (+5.2%)<br>[0.092–0.312] | 0.097 (+4.7%)<br>[0.094–0.334] |
| `actor_ping` | 3.571<br>[3.361–3.586] | 1.313 (-63.2%)<br>[1.300–1.598] | 1.314 (-63.2%)<br>[1.289–1.516] | 1.308 (-63.4%)<br>[1.272–1.331] | 1.313 (-63.2%)<br>[1.285–1.543] | 1.345 (-62.3%)<br>[1.265–1.633] |

CPU time, median user / system seconds:

| benchmark | plain | hr | unit0 | unit1 | hoist0 | hoist1 |
|---|---:|---:|---:|---:|---:|---:|
| `list_ops` | 0.051 / 0.027 | 0.050 / 0.026 | 0.050 / 0.025 | 0.053 / 0.025 | 0.051 / 0.025 | 0.052 / 0.024 |
| `list_ops_nested` | 0.074 / 0.033 | 0.074 / 0.034 | 0.074 / 0.035 | 0.075 / 0.034 | 0.075 / 0.037 | 0.075 / 0.037 |
| `actor_ping` | 0.816 / 2.298 | 0.608 / 0.955 | 0.611 / 0.958 | 0.608 / 0.941 | 0.608 / 0.947 | 0.621 / 0.982 |

**Anomaly, not part of either verdict: plain `actor_ping` is 2.7× slower than every
`--hot-reload` build** (3.57 s versus 1.31 s), almost all of it system time
(2.30 s versus 0.95 s). It reproduced in three more alternating pairs after the run
(plain 2.74–3.14 s, hot-reload 1.31–1.58 s). An instrumented copy of the benchmark shows
both builds leave `wait_done` after one iteration, so it is not the benchmark's wait loop.
The two builds differ in how the actor loop calls the handler: a hot-reload actor's
dispatch function is called directly with two arguments, a plain actor's through a
closure wrapper. Not investigated further; filed as
`specs/todos/2026-09-23-plain-actor-ping-slower-than-hot-reload.md`. The consequence here
is only that `actor_ping`'s `hr` versus `plain` column is not a boundary cost; G1's first
threshold is defined on `list_ops`, and the second compares `unit` with `hr`, both
hot-reload builds.

## What these benchmarks cannot see

- `bench/list_ops.march` itself measures nothing under `--hot-reload`: every helper
  is an entry-module `pfn` with a bare name, so nothing is on the boundary and the
  emitted code has zero compiled dispatch calls (the one `march_dispatch_enter`
  call in its binary is the runtime's own actor loop, never executed). Its `hr`
  column is the cost of the dispatch table's existence, not of any boundary call.
  `bench/list_ops_nested.march` (helpers in `mod Ops`) is the one that speaks to
  the II.7 threshold, and even there only the three helper-to-`irev` calls go
  through dispatch (self tail calls are loops, per-element work is closure calls):
  seven compiled dispatch sites, a handful of dynamic calls per run. It is a floor
  on the boundary cost, not a typical app's.
- `bench/actor_ping.march`: each of the 1,000,000 messages crosses the actor-loop
  dispatch (runtime `hcr_enter`) and one compiled boundary call (`Game.relay` to
  `Game.step`); the handler's own call is a direct call even under `--hot-reload`.
  Its time is dominated by scheduler and mailbox work (mostly system time, see the
  CPU table), so a per-call cost of tens of nanoseconds is below its run-to-run noise.
  That is the honest reading of "not measurable": not zero, but invisible under
  the message-passing cost it sits inside.
- Nothing here exercises a `.so` patch (`compile_so` call sites, which already use
  `enter_gen` with the per-`.so` epoch global), a reload server, or a second live
  version in the ring; `unit1`/`hoist1` scan a ring with one live slot.

## How it was run

Prototype edits (reverted before commit; the numbers are the deliverable):

- `runtime/march_scheduler.h`: `uint32_t code_epoch` on `march_proc`, set once in
  `sched_spawn_common` from `MARCH_G1_EPOCH` (default 0); nothing else writes it.
- `runtime/march_dispatch.c`: `march_dispatch_enter_unit(id, out)` =
  `enter_gen(id, march_sched_current() ? p->code_epoch : 0, out)`.
- unit: `hcr_enter` (runtime/march_runtime.c) calls `enter_unit`; the non-`.so`
  branch of lib/tir/llvm_emit_call.ml emits `enter_unit` instead of `enter`.
- hoist: `hcr_enter` takes the epoch, which `actor_green_thread` reads from
  `self->code_epoch` once per message; compiled sites emit
  `enter_gen(ID, <MARCH_G1_EPOCH at compile time>, &v)`.

Per variant: apply, `dune build --root . bin/main.exe @warm-cache` (the alias
restages `_build/default/runtime`; a bare `bin/main.exe` build does not), `cmp` the
staged runtime files against the edit, then for each benchmark, from a fresh
directory holding only the `.march` file and with a fresh `HOME` (so no CAS
artifact could be shared between variants):

```
_build/default/bin/main.exe --compile --opt 2 [--hot-reload ListOps|Ops|Game] <bench>.march -o <variant>-<bench>
```

Each binary was checked before timing: `nm` shows `_march_dispatch_enter_unit`
only in prototype builds; `otool -tv` call counts were as expected
(compiled `enter`/`enter_unit`/`enter_gen` sites: list_ops 1 (runtime only),
list_ops_nested 7, actor_ping 2; the hoist `e1` builds show the constant epoch in
`w1` before each call); outputs `333333666666` / `1000000` on every timed run.
Timing: a Python runner (`subprocess.run` under `time.perf_counter`, CPU from
`getrusage(RUSAGE_CHILDREN)`), gate `sysctl -n vm.loadavg` 1-minute value <= 8, polled every 60 s.

## Conditions, and every sample

- **Load.** The task set the gate at a 1-minute load average of 5. A runner holding that
  gate (polling every 3 minutes) waited from 15:53 on 2026-09-22 to 11:07 on 2026-09-23,
  385 polls, and never opened: the lowest reading was 7.96, the usual range 10–30 with
  spikes to 85, from other sessions' builds and suites on this 14-core Mac. The user then
  raised the gate to 8 and had the other Claude sessions pause their builds and suites.
  The run went from 16:34 to 16:39 on 2026-09-23 at load 6.5–7.7. Still running: an editor
  LSP (`dexter`) at about one core, the usual desktop apps, and two compiles that belonged
  to no pausable session had finished before sampling started.
- **First-execution outliers.** The first run of each freshly built binary took 0.30–0.47 s
  on the list benchmarks against about 0.07–0.10 s afterwards (round 1 below; macOS pays a
  one-time cost on a binary's first execution). The warm-up absorbs this only for `plain`,
  so the other variants' maximums include it; medians do not move. Next time, execute every
  binary once before round 1.
- **Interleaving.** Each round runs all six variants back to back, so every comparison is
  within the same few seconds of machine state.

Wall seconds per sample, with the 1-minute load average read when the sample started:

| benchmark | round | load (1 min) | plain | hr | unit0 | unit1 | hoist0 | hoist1 |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| `list_ops` | 0 (warm-up) | 7.65 | 0.354 |  |  |  |  |  |
| `list_ops` | 1 | 7.28–7.65 | 0.069 | 0.475 | 0.341 | 0.068 | 0.298 | 0.302 |
| `list_ops` | 2 | 7.28 | 0.067 | 0.067 | 0.070 | 0.070 | 0.068 | 0.069 |
| `list_ops` | 3 | 7.28 | 0.068 | 0.066 | 0.068 | 0.071 | 0.070 | 0.069 |
| `list_ops` | 4 | 7.28 | 0.068 | 0.067 | 0.073 | 0.072 | 0.065 | 0.068 |
| `list_ops` | 5 | 7.28 | 0.069 | 0.067 | 0.068 | 0.069 | 0.068 | 0.067 |
| `list_ops_nested` | 0 (warm-up) | 7.28 | 0.387 |  |  |  |  |  |
| `list_ops_nested` | 1 | 7.28 | 0.095 | 0.361 | 0.381 | 0.092 | 0.312 | 0.334 |
| `list_ops_nested` | 2 | 6.86 | 0.091 | 0.088 | 0.090 | 0.090 | 0.092 | 0.097 |
| `list_ops_nested` | 3 | 6.86 | 0.093 | 0.099 | 0.096 | 0.095 | 0.099 | 0.102 |
| `list_ops_nested` | 4 | 6.86 | 0.093 | 0.094 | 0.095 | 0.098 | 0.098 | 0.094 |
| `list_ops_nested` | 5 | 6.86 | 0.092 | 0.091 | 0.094 | 0.095 | 0.093 | 0.097 |
| `actor_ping` | 0 (warm-up) | 6.86 | 3.485 |  |  |  |  |  |
| `actor_ping` | 1 | 6.51–7.19 | 3.361 | 1.598 | 1.516 | 1.325 | 1.543 | 1.633 |
| `actor_ping` | 2 | 6.51–6.95 | 3.572 | 1.305 | 1.289 | 1.272 | 1.313 | 1.384 |
| `actor_ping` | 3 | 6.72–6.91 | 3.434 | 1.320 | 1.356 | 1.331 | 1.288 | 1.265 |
| `actor_ping` | 4 | 6.91–7.56 | 3.586 | 1.300 | 1.300 | 1.308 | 1.285 | 1.345 |
| `actor_ping` | 5 | 6.97–7.49 | 3.571 | 1.313 | 1.314 | 1.280 | 1.335 | 1.298 |

