# `task_cancel_by_id` leaked the Task it was handed

**Fixed** 2026-10-12. Found by the LSan pass of the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh -l`): `proc_reclaim_kill_respawn` leaked
432,000 bytes of 48-byte cells from `march_task_spawn_thunk` (its `settle`
awaits each Task, then cancels it).

## The bug

`task_cancel_by_id` had no row in `lib/tir/borrow.ml`'s `extern_borrow_table`,
so Perceus treated its argument as OWNED and emitted no release for a Task
whose last use was the cancel. `march_task_cancel_by_id` only reads the Task
(its pid word) and stores the cancelled sentinel into its result word; it
neither keeps nor releases it. So `Task.await(t); task_cancel_by_id(t)` leaked
one Task per call, as does `Task.race`/`Task.any`'s cancel of the losers.

## The fix

Both spellings (`task_cancel_by_id`, `march_task_cancel_by_id`) are now
borrowed in `extern_borrow_table`; the caller releases the Task at its last
use as for any borrowed builtin.

## Verification

- `test/native/task_cancel_by_id_leak_probe.march`: 1,000 await-then-cancel
  calls leaked 1,000 Tasks on main, 0 now; the `again` leg (cancel, then await
  the same Task again) is the double-free witness. Matches the interpreter.
- Linux arm64: the probe and `proc_reclaim_kill_respawn` are clean under the
  ASAN error pass; in the LSan pass the latter no longer reports the Task cells
  (its remaining reports are in the actor/proc-reclamation paths, unchanged).
