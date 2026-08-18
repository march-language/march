# `try_call_capture_ownership_codegen` case 9 (`Signal.watch`) flakes in CI's `trmc-suite` — NOT reproduced locally

**Status: open. This file is a precise negative result, not a fix.** No change to
the test or to the signal runtime was made, because nothing was demonstrated.

## The symptom

`test/test_codegen.ml:10586`
(`test_signal_watch_capturing_handler_repeated_delivery_compiled`, group
`try_call_capture_ownership_codegen`, case 9) intermittently fails the
whole-suite `trmc-suite` CI job
(`.github/workflows/ci.yml`, `MARCH_TRMC=1 ./scripts/run-tests.sh`), on
ubuntu-24.04. Observed on three unrelated PRs — #282 (Vault typing), #298
(parser keyword), #300 (supervisor ABI field) — none of which touch signals,
closures, or the scheduler.

Assertion text:

> a capturing Signal.watch handler delivered 3 times must not be freed after the
> first delivery (long-lived, unbounded-repeat call site)

The predicate is
`ir_contains out "done" && ir_contains out "EXIT:0" && not (ir_contains out "RC underflow")`,
evaluated 25 times per test run. It is a bare `Alcotest.check bool`, so the CI
log records only "expected true, got false" — **which of the three clauses
failed is not recoverable from the CI output**. Adding that detail to the
failure message is the cheapest next step for anyone picking this up (see
"Suggested next step").

## What was tried, and what it showed (macOS 26 / arm64, this repo at 46dfca6b)

Everything below ran with `MARCH_TRMC=1` and a freshly staged runtime
(`dune build --root . @bin/warm-cache`).

| Experiment | Result |
| --- | --- |
| Parent agent: isolated `run_codegen.exe test try_call_capture_ownership_codegen 9`, 10x on the PR branch and 10x on pristine main | 0/10 failures both |
| Standalone extraction of the test's exact `.march` source, compiled and looped | **0/400** |
| Same binary, sweeping `MARCH_NUM_SCHEDULERS` ∈ {1,2,3,4,8}, 150 runs each | **0/750** |
| Amplified variant raising `Signal.Usr2` **2000** times instead of 3 (to force genuinely overlapping `march_signal_drain` windows across scheduler threads), same sweep, 40 runs each | **0/200** |
| Whole `run_codegen.exe -e` suite under `MARCH_TRMC=1` (the CI shape, minus the OS) | case 9 `[OK]` |

**Verdict: not reproducible on macOS/arm64, in isolation or under whole-suite
load.** The untested variable that remains is the OS: every observed failure is
on ubuntu-24.04, and several mechanisms below are Linux-specific in their
timing.

## Ownership analysis (read, not guessed) — no defect found

The RC contract on this path is balanced, and the reasoning is worth recording
so the next person does not redo it:

- `march_signal_drain` (`runtime/march_runtime.c`) does `march_incrc(clo)` then
  `apply(clo, 0)`. The `incrc` exists to balance the `$clo` drop that
  `insert_apply_fn_clo_drop` (`lib/tir/perceus.ml`) puts in a **capturing**
  closure's apply function. Emitted IR for this exact program confirms both
  halves are present:
  `$lam26999$apply` loads `handler` from `$clo+24` into a local **before**
  `march_decrc_local($clo)`, so freeing `$clo` cannot dangle the handler
  pointer, and `march_decrc` frees non-recursively anyway.
- On a scheduler thread `march_sched_in_scheduler()` is true, so
  `march_incrc_local`/`march_decrc_local` take the **atomic** path — concurrent
  drains on two scheduler threads are RC-safe.
- Two scheduler threads *can* be inside `apply(clo, 0)` simultaneously (delivery
  N+1 sets `g_signal_pending` again while delivery N's handler is still
  running); the `atomic_exchange` only serialises the flag, not the call. That
  is by design and is RC-safe per the point above.
- `sched->current` is set to `NULL` immediately after each `swapcontext` returns
  (`runtime/march_scheduler.c:1381`), so the handler's `march_preempt_request`
  prologue calling `march_yield_from_compiled` from the scheduler's own loop
  stack degrades to a no-op in `march_sched_yield`'s
  `if (!tl_sched || !tl_sched->current) return;` guard. Not a stack-corruption
  hazard. (It *does* silently consume a preemption request meant for a real
  green thread — harmless, but noted.)

TRMC itself is not implicated by any of this. `trmc-suite` is simply the job
that runs the whole suite; nothing in `lib/tir/trmc.ml` touches this call site,
and the test's own compile is a **separate `bin/main.exe` process**, so
`run_codegen.exe`'s in-process TRMC fresh-name counter (the run-order hazard from
`specs/progress/`'s snapshot-determinism work) cannot leak into it either.

## What DID reproduce: the sibling signal-dispatch race, and its actual root cause

`specs/todos/2026-07-23-ci-infra-2026-07-23.md` tracks a **quarantined** native
golden, `test/native/signal_term_suppress`, with the same program shape
(`Signal.watch` + `Signal.raise` + `println` from both the main green thread and
the drain). It reproduces here at the documented rate:

- **45/1200 (3.8%) and 49/1500 (3.3%)** mismatches against
  `test/native/signal_term_suppress.expected`.
- Two distinct shapes, matching that todo's characterisation:
  - **Tearing (majority)** — e.g. `before term\nsurvived termterm handler\n\n`.
    Byte count is **identical** to the expected output; the newline that should
    follow `survived term` is emitted *after* the interleaved handler line.
  - **Reordering (minority)** — e.g.
    `before term\nterm handler\nsurvived term\n`, all newlines intact. This is
    legitimate nondeterminism in *when* the drain fires and is not fixable by
    atomic writes.
- **Zero crashes, zero nonzero exits, and zero lost or truncated bytes in 2700
  runs.**

**New root cause for the tearing half** (the 2026-07-23 todo did not have this,
and it explains why that todo's attempted fix measured no effect): `println` on
this path is **not** the runtime's `march_println`. `stdlib/prelude.march:243`
defines

```march
fn println(x) do
  print(show(x))
  print("\n")
end
```

— two separate `march_print` calls, i.e. **two `write(2)` syscalls**. The
runtime's `march_println` goes to real trouble to emit payload+newline in one
`writev(2)` precisely so a line is atomic against concurrent green threads
(see its comment), but the generic `println` never reaches it: the emitted IR
for these programs calls `@println$String`, the stdlib function. The
2026-07-23 todo's "retry-on-short-write in `march_print`/`march_println`" fix
was therefore patching atomicity at a layer the tearing does not come from,
which is consistent with its measured no-op result.

Related, and separately worth fixing: `march_print`
(`runtime/march_runtime.c:1031`) **discards `write()`'s return value**
entirely, and `march_println` discards `writev()`'s. A short write or an
`EINTR` on a signal-heavy path loses or truncates output silently. Not observed
here (2700 runs, no byte ever lost) but it is the one mechanism that would
delete the `done` token this test asserts on, and SIGUSR1 preemption pressure is
exactly what makes it likelier under a loaded whole-suite CI run than in
isolation.

**Neither of those is fixed here.** Both touch a hot stdlib/runtime print path
shared by every March program, and both deserve their own change with their own
before/after measurement (the tearing one has a ready-made red/green: the 3.3%
mismatch rate above).

## Suggested next step, in order of cost

1. **Make the failure legible before chasing it.** Split the single
   `Alcotest.check bool` in
   `test_signal_watch_capturing_handler_repeated_delivery_compiled` into three
   checks (or fold the captured `run_out` into the failure message) so the next
   CI red says *which* clause failed and what the binary actually printed. Right
   now the log cannot distinguish "crashed", "printed nothing", and "printed a
   truncated `done`" — and those point at three different bugs.
2. Only then decide between the candidates: lost/short `write` in `march_print`
   (would show as a truncated or missing `done`, exit 0) versus a genuine crash
   (would show as a nonzero `EXIT:`).
3. Do **not** weaken the `done`/`EXIT:0` predicate until (1) has produced a
   labelled failure. Its absence may well be the real symptom of a real bug, and
   relaxing it would delete the evidence rather than the flake.

## Do not redo

- Reproducing on macOS/arm64. 1350+ runs of the exact program across every
  scheduler count, plus a 2000-delivery amplification, plus the whole suite under
  `MARCH_TRMC=1`. It does not fail here.
- Auditing the drain's refcount contract. It balances; the reasoning is above.
- Blaming TRMC's fresh-name counter. The test compiles in a separate process.
