`[P2]` Runtime `Diagnostics` crash-observer facility (2026-10-14)

**Filed and landed:** 2026-10-14. Follow-ups:
`specs/todos/2026-10-14-diagnostics-backtrace-followups.md`.

An error-reporting integration (a Sentry SDK, say) could not observe an
unhandled panic in an arbitrary actor: the runtime owns the failure, the
supervisor's restart and the process exit. `stdlib/diagnostics.march` is now
the vendor-neutral contract:

```march
type CrashKind = Panic | ActorCrashed | TaskFailed
type CrashReport = { kind, message, location : Option(SourceLocation),
                     backtrace : List(StackFrame), process : ProcessInfo,
                     context : List((String, DiagnosticValue)) }
fn observe_crashes(observer : CrashReport -> Unit) : ObserverHandle
fn unobserve(handle : ObserverHandle) : Unit
fn with_context(values, thunk : () -> a) : a
fn current_context() : List((String, DiagnosticValue))
```

## Semantics as built

- **Where.** Compiled, the report is built and dispatched inside
  `march_panic` (`runtime/march_runtime.c`, "Diagnostics: crash observers"),
  on the failing green thread with its stack intact, before the existing
  test-trap / supervised crash-trap / exit decision. Interpreted, at the two
  boundaries a panic reaches (the actor loop's handler exception, before
  `crash_actor`; the top level in `bin/main.ml`, before the error is printed),
  through `Eval.diag_report_crash`.
- **What counts.** A panic nothing *handles*. `march_panic_handled` is set by
  the test runner and `__try_call` / `__try_call_val`, not by `try_finally`,
  which only intercepts and re-raises; its re-raise sets `march_panic_reraise`
  so the panic is reported once, where it was raised, with the context of the
  `with_context` scopes it was raised in. (Before this split, dispatching only
  when no catcher was active would have reported every panic under
  `with_context` or `Logger.with_scope` after its cleanup popped the context
  and its stack had unwound.) The interpreter gets the same answer by
  snapshotting the context when an error is raised (`Eval_prim.eval_error`,
  only while an observer is registered).
- **Kind.** `ActorCrashed` when the proc has a crash trap (a supervised
  actor), else `Panic` (including an unsupervised actor, whose panic exits the
  process compiled). `TaskFailed` is reserved: a compiled task panic exits the
  process and reports `Panic`.
- **Isolation.** Observers are a snapshot taken under the registry lock, each
  holding its own reference, called in registration order. An observer's
  panic lands on the proc's `diag_jmp` (with `march_test_in_test` cleared for
  the dispatch, so it never unwinds into a `try_finally` around the original
  panic) and abandons that observer only; a panic inside the observer's own
  `try_finally` is caught there first. No report is dispatched while one is
  being dispatched on that proc. Removing an observer during a dispatch frees
  nothing the dispatch holds; it is still called that once.
- **Time budget.** Inline, so a documented contract (hand the report off, do
  not block), not a preemptive deadline.
- **Context.** Per green thread on the proc (`march_proc.diag_ctx`, a
  thread-local fallback off the scheduler), released at the proc reap
  (`march_diag_proc_exit`) if something skipped `with_context`'s cleanup.
- **Backtraces.** Compiled: `backtrace()` (the CFI unwinder; nothing paid
  without a crash) plus `dladdr`, skipping the panic machinery and runtime
  symbols, ending at `march_main` (`main`) or a green-thread entry. Names
  resolve on macOS; on Linux only in an `--export-dynamic` (hot-reload)
  build, since exporting every executable symbol would let a user function
  interpose a libc one. No file/line yet, so `location` is `None`.
  Interpreted: the frame stack re-paired so each frame names the function the
  line is in, cut at the actor handler's entry, prelude panic wrappers
  dropped; `location` is the panic line.
- **Unchanged.** Supervision, restart counts, exit codes and stderr. The
  compiled stderr backtrace is still empty (see follow-ups).

Also fixed on the way: the interpreter's `__try_call` left a handled panic's
frames on the March stack, so they showed up in every later printed
backtrace; it now restores the stack to its mark on entry.

## Tests

`test/native/diagnostics_crash_observers.march`, one `.expected` for the
compiled and the interpreted run (`test/dune`): report fields, inner-first
context, registration order, a panicking observer and one panicking inside
its own `with_context`, removal mid-dispatch and twice, a handled panic
unreported, context restored after return and panic, the supervisor restart,
and the final unhandled panic still exiting 1. `scripts/triage.sh --deep`:
interp and compiled match under every optional-pass switch; ASAN+UBSan
clean. Perturbation check: dropping the `march_panic_handled` test makes the
fixture fail (three extra reports).
