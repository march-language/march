# Process builtins leaked their arguments and every LiveProcess (fixed 2026-09-29)

Found 2026-09-28 while fixing the live-process registry (PR #680,
specs/progress/2026-09-28-live-process-registry-unsynchronised.md): its fixture
under `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1` in the Linux container reported
LeakSanitizer "Direct leak of 6400 byte(s) in 200 object(s)" from `march_alloc`
in `march_process_spawn_async`, called from the fixture's `echo_once`. The leak
was identical with origin/main's runtime, so it was not the registry change.

**Cause: classification, not lowering.** `lib/tir/borrow.ml` listed the whole
`process_*` family (`process_env`, `process_set_env`, `process_spawn_sync`,
`process_spawn_lines`, `process_spawn_async`, `process_read_line`,
`process_write`, `process_kill_proc`, `process_wait_proc`) in
`extern_owned_builtins`, so Perceus handed each call a reference and emitted no
release. None of the C functions (runtime/march_runtime.c) stores or frees a
heap argument: the spawns copy the command and args list into a `malloc`'d argv
they free themselves, env/set_env copy into stack buffers, and the four handle
calls only load the LiveProcess's pid and slot words. The TIR of
`Ok(p) -> read_line(p); wait_proc(p)` was `inc_rc p; process_read_line(p);
process_wait_proc(p)`: the inc paid for read_line's "consumption", wait_proc
consumed the last reference, and nothing freed the cell. The args list (`Cons`
+ its String) leaked the same way on every spawn.

**Fix.** The nine names moved to `extern_borrow_table`, all heap params
borrowed. The only LiveProcess producer is `process_spawn_async`, which returns
a fresh owned cell inside a fresh `Ok`, so nothing hands these calls an unowned
reference.

**RED → GREEN**, `test/native/process_handle_leak_probe.march` (`--compile
--opt 2`, `live_allocs()` deltas), before the fix: 161 objects over 40
spawn/read_line/wait_proc cycles (4 each, among them the LiveProcess cell and
the args list's Cons and String), 121 over 40 spawn/write/kill/wait
cycles, 121 over 40 `Process.run` calls, 801 over 400 set_env + env pairs.
After: 1 on every leg (the probe's own bookkeeping). The dune rule diffs the
booleans.

**Not fixed here.** `march_process_spawn_lines` builds a full
`Ok(ProcessResult(...))` via `march_process_spawn_sync` and returns a new
`Ok(stdout)`, never releasing the intermediate Result, the ProcessResult or its
stderr String; its compiled payload is also a String while the type says
`Seq(a)`. Filed as specs/todos/2026-09-29-process-spawn-lines-leaks-and-wrong-payload.md.
