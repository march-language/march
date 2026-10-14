`[P2]` Add a generic runtime `Diagnostics` crash-observer facility

**Filed:** 2026-10-14.

An external error-reporting integration (for example, a Sentry SDK) cannot
reliably observe unhandled panics in arbitrary actors or tasks: the runtime,
not application code, owns the failure, supervision, restart, and termination
boundaries. March has no generic crash-observation contract today.

## API

Add an opt-in `Diagnostics` API, backed by the runtime rather than by any
vendor SDK:

```march
type CrashKind = Panic | ActorCrashed | TaskFailed

type CrashReport = CrashReport(
  kind: CrashKind,
  message: String,
  location: Option(SourceLocation),
  backtrace: List(StackFrame),
  process: ProcessInfo,
  context: List((String, DiagnosticValue))
)

fn observe_crashes(observer: CrashReport -> Unit) : ObserverHandle
fn unobserve(handle: ObserverHandle) : Unit
fn with_context(values: List((String, DiagnosticValue)), thunk: () -> a) : a
```

`with_context` is runtime-local and captures only JSON-safe diagnostic data.
The runtime snapshots it while constructing a `CrashReport`, so an HTTP or job
integration can attach sanitized request/job metadata that survives a panic.
The mechanism must remain vendor-neutral: Sentry-specific event construction,
queueing, retry policy, DSN handling, and network transport belong in an
external package.

## Required semantics

- Build the immutable report at the runtime failure boundary, before the
  existing supervisor/restart/exit decision continues.
- Notify a snapshot of the registered observers in registration order.
- Isolate observer failures and prohibit recursive notification; an observer
  must never change the original failure outcome.
- Observers run inline on the failing green thread, so the time budget is a
  documented contract (no blocking or network I/O; hand the report to a queue
  or actor), not a preemptive deadline. See open question 1.
- Support multiple observers and idempotent handle removal.
- Preserve current actor/task panic and supervision behaviour byte-for-byte
  apart from the optional observation side effect.

## What already exists

- **One compiled panic choke point.** `march_panic`
  (`runtime/march_runtime.c`) either longjmps to a supervised actor's crash
  trap (`march_proc.crash_jmp`), longjmps to the test runner, or records the
  crash and `exit(1)`s. All three branches need the hook.
- **The crash ring** (R2 of the observe plan; `crash_ring_push`) already
  records kind, pid, actor type, code epoch, supervisor and restart count for
  actor crashes and unsupervised panics. It is written *after*
  `march_supervisor_notify` in `do_actor_death_kind`; the observer dispatch
  must sit before that call (the ring itself can stay where it is).
- **Context prior art.** `Logger`'s field stack (`with_field` / `with_scope`,
  `stdlib/logger.march`) is the pattern for `DiagnosticValue` and scoped
  `with_context`. Context must live on the green thread (`march_proc`), not
  in a `_Thread_local`: procs migrate between OS threads.
- **Function-level DWARF.** `--debug-info` already emits one `DISubprogram`
  per March function plus the `!march.provenance` side table
  (`lib/tir/llvm_toplevel.ml`, `lib/tir/provenance.ml`). There are no
  per-statement line tables yet.
- **Interpreter.** `crash_actor` in `lib/eval/eval_runtime.ml` is the
  interpreter's actor failure boundary; it keeps its own frame stack, so its
  backtraces are already available.

## Backtraces: unwind, then symbolize lazily (the Rust approach)

Do **not** instrument every call. The runtime has a `march_frame_push` /
`march_frame_pop` call stack that the compiler never emits, and making it emit
them would cost every call in every program. Instead, do what Rust's
`std::backtrace` does:

1. **Capture by unwinding.** In `march_panic` (and at the actor/task failure
   boundaries), walk the current native stack with `_Unwind_Backtrace` (or
   `backtrace()` from `<execinfo.h>`), using the CFI LLVM already emits
   (`.eh_frame` / compact unwind). Store raw instruction pointers in the
   report. This is cheap, costs nothing when no crash happens, and needs no
   compiler change.
2. **Symbolize lazily, only when an observer is registered.** Map PCs to
   frames in two tiers:
   - **Names (always):** `dladdr` → LLVM symbol name → `!march.provenance` /
     the provenance side table → source function name. Hide runtime and
     `stdlib/` frames unless `MARCH_BACKTRACE=full`, matching
     `march_print_backtrace`.
   - **file:line (with `--debug-info`):** read DWARF in-process with
     `libbacktrace` (BSD; the library GCC and Go use), the C equivalent of
     Rust's `gimli`/`addr2line`. Function-level DWARF gives each frame its
     definition line today; per-call-site lines need `DILocation`s on call
     instructions, a follow-up rather than part of v1.
3. **Green threads.** A walk from inside `march_panic` sees only the failing
   green thread's own stack, which is what the report wants. Check that the
   context-switch entry trampoline ends the unwind cleanly (a missing CFI
   end-of-stack marker makes the unwinder wander) on both macOS arm64 and
   Linux x86-64.
4. **`location`** is the innermost non-runtime frame's file:line when DWARF
   is present, else `None`.

Also switch the existing stderr backtrace on an unsupervised panic to the same
unwinder. It prints nothing for compiled code today because the frame stack
is always empty.

## Open questions (decide before starting)

1. **Time budget.** A synchronous observer cannot be preempted without
   preemption tricks. Proposed: inline, with the budget as a documented
   contract and a debug-mode warning when an observer exceeds it. The
   alternative (dispatch to a separate task with a deadline) breaks
   "report delivered before the restart decision continues".
2. **`TaskFailed`.** In compiled code a panic inside a task is not caught:
   the task wrapper only catches cancellation (`march_proc.task_jmp`), so a
   task panic exits the process and would be reported as `Panic`. Either
   define task failure first (its own change) or reserve `TaskFailed` and
   ship without it.

## Work breakdown and estimate

| Piece | Estimate |
|---|---|
| Runtime observer registry: snapshot, ordering, idempotent removal, removal during dispatch | 1–2 days |
| Safe dispatch: nested crash trap to isolate a panicking observer, per-proc recursion guard, `with_context` stored on `march_proc` | 2–3 days |
| Move dispatch before `march_supervisor_notify`, cover all three `march_panic` branches | 1 day |
| Backtrace capture (unwinder) + `dladdr`/provenance names | 2–3 days |
| `libbacktrace` DWARF file:line under `--debug-info`, macOS + Linux | 3–4 days |
| Interpreter parity (`crash_actor`, panic and task paths) | 2–3 days |
| `Diagnostics` stdlib module, types, builtin wiring (see `compiler-builtin` skill) | 1–2 days |
| Tests (both backends) | 2–3 days |
| Specs, CHANGELOG, `specs/lang` docs | ½ day |

About **2.5–3.5 weeks** in total; about **2 weeks** if the `libbacktrace`
tier is deferred (names-only frames, `location = None`).

## Tests

Panic capture; actor crash and (if in scope) task failure; context nesting and
cleanup, including cleanup on panic; observer reentrancy and an observer that
panics; unregistering during dispatch; ordering across multiple observers;
supervisor restart behaviour unchanged (same restart counts and crash-ring
entries with and without an observer); a backtrace that contains the user
function that panicked, with and without `--debug-info`; no output change for
a program that registers no observer.

## Follow-ups (not v1)

- Per-call-site DWARF line tables (`DILocation` on call instructions) for
  line-accurate frames beyond the function's definition line.
- Inlined-frame reconstruction from DWARF inline info.
- A vendor package (e.g. Sentry) built on this API, outside the compiler repo.
