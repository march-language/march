# A proc parked in `receive()` inside a handler was an RC underflow at process exit

Filed and fixed 2026-09-17 while building the actor-hosted runner
([[2026-09-17-actor-hosted-runner]]).

An actor whose handler blocks in `receive()` (the monitor-fixture pattern:
`on Watch(...) do let _ = monitor(...) match receive() do Down.Down(...) -> ...`) and is
still parked there when `main` returns aborts the process:

```
march: RC underflow (rc was 0) at 0x1032230c0 — aborting
```

Reproduced with a 40-line program (a supervisor, a worker, a watcher parked in
`receive()` with nothing ever sent; `MARCH_NUM_SCHEDULERS=1`, compiled). Sending the
watcher any message before `main` returns -- so `receive()` returns and the handler
finishes -- exits cleanly. So the failure is the shutdown endgame's wake of an idle daemon
(`wake_idle_daemons`, `march_scheduler.c`) reaching a proc parked in `march_sched_recv`
*inside a handler turn*: the wake returns from `receive()` with no message, and what the
handler then drops has no reference to drop.

`SessionNode.run_hosted` works around it by sending its watcher `Stop` when the session
ends. The fix belongs in the runtime: either a proc parked in `receive` from within a
handler is not woken at shutdown (it is not idle: its turn is in progress), or the wake
makes `receive()` return a value whose drop is a no-op.

Also observed on the way, not root-caused: a one-argument `monitor(pid)` called from
inside an actor handler compiles and produces no `Down` for that pid's crash, where the
two-argument `monitor(watcher, pid)` from outside does. Either the one-argument form is a
different function or it is silently inert; `test/test_endpoints.ml`'s typecheck-only
`Watcher` uses the one-argument form, so nothing runs it.

## Fixed (2026-09-17)

- **The runtime.** The compiled `receive()` builtin now calls `march_actor_recv`
  (`march_runtime.c`), which is `march_sched_recv` plus: a `MARCH_RECV_NO_MSG` never
  reaches user code. An actor's proc carries a `stop_jmp` (set by `actor_green_thread`
  for every actor around its dispatch loop, supervised or not); the stopped nested
  receive longjmp's there and lands on the loop's normal death path (`do_actor_death`
  NORMAL, the hot-reload pin released as the crash trap does). A task or `main` parked
  in `receive()` ends its green thread (`march_sched_exit`). Witness:
  `test/native/receive_in_handler_at_exit` -- an actor parked in a nested receive with
  nothing ever sent, `main` returns; exit 0 and no "woken" line, where it aborted.
- **The one-argument `monitor(pid)`** was a partial application: `monitor` is a
  two-parameter builtin whose scheme is a curried arrow chain, so `monitor(target)`
  typechecked as a `Pid(a) -> Int` *value*, which `let _ =` discarded -- no monitor was
  set, no `Down` came. March has no partial application; the arity check that already
  rejected under-applied module functions now covers builtins (some arguments but fewer
  than the parameters -- a zero-argument call is the nullary convention `f()` and stays
  accepted; `typecheck.ml`, the `arity_error` in the `EApp` case, keyed on
  `builtin_bindings`). Witness: `builtin_under_application` in `test/test_endpoints.ml`;
  the CLI monitor test there now writes `monitor(self, target)`.
- `SessionNode.run_hosted` keeps sending its watcher `Stop` at session end (a watcher
  left parked is now ended cleanly at exit, but ending it at session end is tidier).
