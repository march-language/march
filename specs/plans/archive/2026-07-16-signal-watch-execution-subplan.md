# Signal.watch (7.2) — execution sub-plan (anchored to trunk `2b5f537e`)

Companion to the design spec `specs/2026-07-02-signal-handler-api.md` (Option:
deferred green-thread dispatch, one watcher per signal, Term/Int default
suppression + second-delivery escape hatch). This re-anchors the spec's
implementation plan to the current trunk and slices it for staged delivery.

## Surface (from the spec, unchanged)
`mod Signal do type Sig = Term | Int | Hup | Usr1 | Usr2 … fn watch(sig, handler : () -> ()) : () / fn unwatch(sig) : () end`, `needs IO.Signal`.
Handler invoked as `handler(())` — but **7.1's zero-arg-lambda fix is now merged**, so `fn -> body` also works (the spec's `fn _ ->` gotcha is retired for the interp/typecheck path; keep the doc note for compiled until verified).

## Trunk anchors (verified 2026-07-16)
| Layer | Anchor |
|---|---|
| stdlib | new `stdlib/signal.march` |
| cap hierarchy | `lib/caps/cap_lattice.ml:25-26` (IO.Clock/IO.Random siblings) → add `("IO.Signal", Some "IO")` |
| cap type-arg registry | `typecheck.ml:~2138` `builtin_types` → add `("IO.Signal", 0)` |
| builtin cap table | `typecheck.ml:1328-1337` (IO.Clock/Random/Spawn rows) → add `signal_watch`/`signal_unwatch` → `IO.Signal` |
| builtin schemes | `typecheck.ml:~1532` (Mono TArrow table) → `signal_watch : Int -> (()->()) -> ()`, `signal_unwatch : Int -> ()` |
| purity | `lib/tir/purity.ml:12` `impure_builtins` (has `task_spawn`) → add both |
| eval builtins | `lib/eval/eval.ml:~3132` (VBuiltin assoc list) → `signal_watch`/`signal_unwatch` impls |
| eval signal install | `eval.ml:9174-9175` `Sys.set_signal … handle_signal` → extend `handle_signal` for user watchers |
| eval drain | `run_scheduler` at `eval.ml:7862` (+ `run_scheduler_hook` :7938) → drain pending flags, `apply handler [VUnit]` |
| codegen | `lib/tir/llvm_emit.ml` — extern decls + `signal_watch->march_signal_watch` mapping; closure arg **owned** (like task_spawn); `lib/tir/borrow.ml` |
| runtime | `runtime/march_runtime.c` — `g_signal_handlers[5]`, `_Atomic g_signal_pending/seen[5]`, one `sigaction` dispatcher (lazy install, no `SA_ONSTACK`), `march_signal_drain()`; `march_signal_watch/unwatch`; interplay w/ `march_http.c` `http_signal_handler` (set `g_http_shutdown` only when no watcher OR 2nd delivery); drain called from `march_sched_run`, `march_http.c:~1864`, `march_http_evloop.c:~547` |

## Staged delivery
**Stage A — interpreter slice (self-contained, testable now):**
stdlib/signal.march + typecheck (schemes + cap + builtin_types + cap_lattice) +
purity + eval (handler table + pending flags + `handle_signal` extension +
drain from `run_scheduler`). Test: `test/test_eval.ml` — register a `Usr1`
watcher mutating a ref, `Unix.kill (getpid()) sigusr1`, pump scheduler, assert
ran exactly once; two-before-drain coalesces to one. **Gate:** eval suite green;
`--check`/interp of a `Signal.watch` program works.

**Stage B — compiled runtime + codegen (the delicate C slice):** the
`runtime/march_runtime.c` signal table + `sigaction` dispatcher + drain wired
into scheduler/HTTP loops; `march_http.c` shutdown interplay; codegen extern +
owned-closure borrow. Test: `test/native/signal_watch.march` (Usr1 self-send)
+ Term-suppression + second-delivery escape-hatch native tests. **Gate:** native
fixtures pass; existing HTTP-shutdown tests green with no watcher; ASAN-clean
(only TERM/INT/HUP/USR1/USR2 touched, no SA_ONSTACK — scheduler altstack
arrangement untouched). Parity with Stage A is a test obligation.

**Stage C — docs/bookkeeping:** stdlib doc + a capabilities.md `IO.Signal` note;
mark `todos:380` done.

## Risks
Async-signal-safety (handler only sets a `sig_atomic_t` flag — no alloc/RC in
signal context); the Term/Int default-suppression + second-delivery interplay
with the existing HTTP/interpreter shutdown paths (regression-guard those);
touching only non-fatal signals so the ASAN/`--test`-harness/scheduler-preempt
`sigaltstack` arrangement is never disturbed. Multi-day; Stage B (C signals) is
the delicate part.
