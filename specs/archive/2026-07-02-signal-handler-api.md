# Signal-Handler API (`Signal.watch`) — Design

**Date:** 2026-07-02
**Status:** Spec — not yet implemented
**Motivating consumer:** graceful drain in Bastion apps. `Bastion.Health.start_drain()` already
exists (flips `/health` to `503 {"status":"draining"}` so load balancers stop routing), but no
March code can run on SIGTERM to call it — forgepm's ops spec explicitly parks graceful drain as
"blocked on march-stdlib signal handling" (`forgepm/specs/operations.md` §1/§6).

---

## 1. Current state (surveyed 2026-07-02)

Both execution modes already handle SIGTERM/SIGINT **internally**; neither exposes a hook:

- **Compiled:** `march_http_server_listen` installs `signal(SIGTERM|SIGINT, http_signal_handler)`
  which sets `_Atomic int g_http_shutdown` (`runtime/march_http.c:1702-1806`); both accept loops
  poll it about once per second and exit (`march_http.c:1854-1864` threaded pool,
  `march_http_evloop.c:544` evloop — each already wakes on a ≥1s timeout, which matters in §4).
  SIGPIPE is ignored. The `--test` harness installs crash handlers for fatal signals
  (`march_runtime.c:808-821`), and the scheduler owns a `sigaltstack` with a documented ASAN
  interplay (commit `7f1d1a32` — MARCH_SANITIZE must keep ASAN's sigaltstack).
- **Interpreted:** `run_module` installs OCaml `Sys.set_signal` handlers for SIGTERM/SIGINT that
  set `shutdown_requested := true`, consumed by the `app` lifecycle to run `on_stop`
  (`lib/eval/eval.ml:8679-8682`).
- **User-facing:** nothing. `Process.kill` *sends* SIGTERM to child processes; no API receives.

So the design problem is not "add signal handling" — it's **exposing a user hook that composes
with the two internal mechanisms without breaking their shutdown behavior**.

## 2. Surface API

New stdlib module `stdlib/signal.march`, new capability **`IO.Signal`** (child of `IO` in the
existing hierarchy, so `needs IO` subsumes it — same as every other `IO.*`):

```march
mod Signal do
  -- Portable subset only. Fatal/synchronous signals (SEGV, BUS, ILL, FPE) are
  -- deliberately NOT exposed: they belong to the runtime/ASAN/test harness.
  type Sig = Term | Int | Hup | Usr1 | Usr2

  doc "Register `handler` to run when `sig` is delivered. Replaces any previous
  watcher for that signal (last-write-wins, like Sys.set_signal). The handler
  runs on a scheduler green thread shortly after delivery (≤ ~1s; see §4), never
  in signal context. Registering a watcher for Term or Int SUPPRESSES the
  runtime's default shutdown for that signal — shutdown becomes the handler's
  job (see §3 for the second-delivery escape hatch)."
  fn watch(sig : Sig, handler : () -> ()) : ()

  doc "Remove the watcher for `sig`, restoring the runtime default."
  fn unwatch(sig : Sig) : ()
end
```

**Handler invocation convention:** the runtime invokes `handler(())` with a unit argument —
callers must pass `fn _ -> body` (1-arg discard). This matches how every other runtime callback
is invoked today (`Bastion.Health.check` probes, `task_spawn`), and the `fn -> ...` /
`fn () -> ...` forms fail typecheck with a confusing "expected `() -> ()` but got `()`" (the
known task_spawn gotcha — see forgepm commit "Phase 6A" for the latest independent rediscovery).
The spec for the doc comment MUST state this explicitly. (A follow-up niceness — unifying
zero-arg lambdas with unit-arg invocation in the typechecker — is out of scope here but would
retire this whole gotcha class; noted in §8.)

## 3. Semantics

1. **Deferred dispatch, never in signal context.** The C handler (and the OCaml `Signal_handle`)
   only sets a pending flag. March handler code — which allocates, touches RC, may do IO — runs
   later on a scheduler thread. No async-signal-safety obligations leak to users.
2. **Coalescing:** deliveries between drains coalesce; the handler runs once per drain, not once
   per delivery. (Pending is a flag, not a queue — documented.)
3. **Term/Int default interplay:**
   - No watcher registered → today's behavior, unchanged (HTTP loops shut down; interpreter's
     `shutdown_requested` drives `on_stop`).
   - Watcher registered → the default is suppressed for that signal; the handler is responsible
     for eventual shutdown (the drain pattern: `start_drain(); sleep(grace); Process.exit(0)`).
   - **Second delivery of the same signal while a watcher is registered forces the default**
     (sets `g_http_shutdown` / `shutdown_requested` unconditionally). This is the standard
     double-Ctrl-C escape hatch and bounds the "handler never exits" footgun.
4. **Hup/Usr1/Usr2:** no default behavior to suppress; watcher or no-op.
5. **One watcher per signal, process-wide.** Fan-out belongs in user code.
6. **WASM target:** `watch`/`unwatch` are accepted and do nothing (documented), matching the
   wasm runtime's other no-op IO stubs.
7. **Windows:** out of scope (no current target).

## 4. Implementation plan (by pipeline layer)

1. **`stdlib/signal.march`** — `Sig` type, `watch`/`unwatch` mapping `Sig` to the C signal
   number (`Term=15, Int=2, Hup=1, Usr1=10/30, Usr2=12/31` — map in C, not March, to dodge the
   Darwin/Linux USR numbering difference: pass a stable enum code 0–4, translate in the runtime).
   `needs IO.Signal`.
2. **Typecheck** — builtin bindings `signal_watch : Int -> (() -> ()) -> ()`,
   `signal_unwatch : Int -> ()`; `IO.Signal` added to the capability table under the `IO`
   hierarchy (mirrors how `IO.NetListen` etc. are wired).
3. **Runtime (compiled), `runtime/march_runtime.c`:**
   - Global table: `void *g_signal_handlers[5]` (RC-inc'd closures; RC-dec the old one on
     replace/unwatch), `_Atomic int g_signal_pending[5]`, `_Atomic int g_signal_seen[5]` (for
     the second-delivery rule).
   - One `sigaction` dispatcher for watched signals; it only stores flags (`sig_atomic_t`
     discipline). Installed lazily on first `watch` per signal; `unwatch` restores the previous
     disposition (`SIG_DFL`, or `http_signal_handler` if the HTTP server had installed it —
     capture the old action from `sigaction`'s `oldact`).
   - **Drain point:** `march_signal_drain(void)` — checks pending flags, and for each set flag
     spawns the registered closure as a green thread via the existing `march_spawn` machinery,
     then clears the flag. Called from (a) the scheduler loop each iteration
     (`march_sched_run`), (b) the threaded-pool accept loop's ≥1s poll timeout
     (`march_http.c:1864`), and (c) the evloop's 1s `kevent/epoll` timeout
     (`march_http_evloop.c:547`). All three already wake at ≥1s cadence, so worst-case dispatch
     latency is ~1s with **no self-pipe needed in v1** (self-pipe wakeup is a v2 latency
     optimization, noted in §8).
   - **Interplay change in `march_http.c`:** `http_signal_handler` routes through the unified
     dispatcher; it sets `g_http_shutdown` only when no watcher is registered for that signal
     OR on second delivery (§3.3).
   - **ASAN/test-harness constraint:** only TERM/INT/HUP/USR1/USR2 are ever touched — never the
     fatal signals the `--test` harness (`march_runtime.c:808`) and ASAN own, and no
     `SA_ONSTACK`, so the scheduler/ASAN `sigaltstack` arrangement (`7f1d1a32`) is untouched.
4. **Codegen, `lib/tir/llvm_emit.ml`** — extern decls + builtin-name mapping
   (`signal_watch -> march_signal_watch`, `signal_unwatch -> march_signal_unwatch`); borrow
   annotation: the closure argument is **owned** (the runtime holds it beyond the call — same
   annotation class as `task_spawn`).
5. **Interpreter, `lib/eval/eval.ml`** — handler table + pending flags in refs; `run_module`'s
   existing `handle_signal` extended: if a user watcher exists for the signal, set that pending
   flag instead of `shutdown_requested` (second delivery sets both). Drain from the scheduler
   tick (same place the actor run-queue is pumped) by `apply handler [VUnit]`. Parity with
   compiled semantics is a test obligation, not an accident.
6. **Purity/borrow tables** — `signal_watch`/`signal_unwatch` are effectful (`purity.ml`), the
   closure is owned (`borrow.ml`), matching `task_spawn`'s entries.

## 5. Testing

- **Eval tests (`test/test_eval.ml`):** register a `Usr1` watcher that mutates a ref, deliver
  via OCaml `Unix.kill (Unix.getpid ()) Sys.sigusr1`, pump the scheduler, assert the handler ran
  exactly once (and twice-delivered-before-drain coalesces to one run).
- **Native fixture (`test/native/signal_watch.march` + `.expected`):** program registers a
  `Usr1` watcher that prints, sends itself the signal (`Process.kill` on own pid — check it can
  target self; else raise(3) via a tiny builtin for the test), sleeps a beat, prints done.
  Asserts ordering and single dispatch, compiled.
- **Term-suppression test (native):** watcher for `Term` that prints and exits 0 explicitly;
  harness sends SIGTERM; asserts the handler output appears (default shutdown suppressed) —
  plus a second-delivery test asserting the escape hatch kills the process.
- **Regression guard:** existing HTTP shutdown tests must still pass with no watcher registered
  (behavioral default unchanged).

## 6. Downstream (non-normative)

Bastion gains the drain pattern forgepm needs, either as documentation or a helper:

```march
Signal.watch(Signal.Sig.Term, fn _ ->
  Bastion.Health.start_drain()
  -- grace period for LBs to observe 503 draining, then stop
  sleep_ms(grace)
  Process.exit(0)
)
```

forgepm's `specs/operations.md` §6 item 1 unblocks when this lands.

## 7. Explicitly out of scope

- Fatal/synchronous signals (SEGV/BUS/ILL/FPE) — runtime/ASAN/test-harness territory.
- Signal *masks*, per-thread signals, `sigwait`-style synchronous reception.
- Windows.
- Queued (non-coalescing) delivery semantics.

## 8. Follow-ups noted, not specced

- Self-pipe wakeup to cut the ~1s worst-case dispatch latency.
- Typechecker unification of zero-arg lambdas with unit-arg callback invocation, retiring the
  `fn _ ->` gotcha across `task_spawn`/`Health.check`/this API in one move.
