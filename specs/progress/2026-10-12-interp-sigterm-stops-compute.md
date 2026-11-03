# Interpreter: SIGTERM and Ctrl+C could not stop a program busy computing

**Date:** 2026-10-12. Found by the interpreter-vs-compiled differential sweep
(group V): its 30 s per-program `SIGTERM` timeout left interpreted benchmarks
(`bench/array_sort.march`, `rrb_bench`, `hash_map_bench`, …) running for 12+
minutes, while every compiled binary died on the same signal.

## What was wrong

`Eval.run_module` installs a SIGTERM/SIGINT handler for graceful shutdown.
With no `Signal.watch` watcher it only set `shutdown_requested`, and only two
loops ever read that flag: the actor scheduler drain (`run_scheduler`) and the
HTTP event loop. A `main` doing ordinary computation never looked at it, so
the signal was swallowed: `timeout`, `kill` and Ctrl+C (any number of times)
had no effect. Compiled code takes the default action and exits 143/130.

## The fix

- `lib/eval/eval_prim.ml`: `shutdown_consumers`, a count of running loops that
  poll the flag, and `with_shutdown_consumer`.
- `lib/eval/eval.ml`: `run_scheduler` and an app's whole lifecycle (`app`
  entry point: spawn, `on_start`, drain, graceful shutdown, `on_stop`) run as
  consumers; `lib/eval/eval_builtins.ml`: so does the HTTP event loop.
- `handle_os_signal`, unwatched Term/Int: with no consumer running, or on a
  second delivery, exit `128 + signo` (143 / 130). Otherwise set the flag as
  before, so servers and apps still shut down gracefully on the first signal.
  Watched signals are unchanged.

## Tests

`test/test_codegen.ml`, group `interp_signal`: runs an interpreted infinite
loop, sends SIGTERM once `main` has printed, and requires exit status 143.
RED with the exit disabled (the process ignored the signal until the test's
SIGHUP fallback reaped it), GREEN with it.
