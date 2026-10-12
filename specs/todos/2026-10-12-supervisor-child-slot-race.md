`[P3]` A supervisor's child-pid slot is written from the dying child's thread with a plain store

Found 2026-10-12 by the TSAN sweep (`MARCH_SANITIZE=thread`, `test/native/*.march` at
1, 2 and 14 schedulers). It is the one report that survives the sweep's fixes:
`proc_reclaim_kill_respawn` at 2 and 14 schedulers, in about every run.

```
Write  march_respawn_child  runtime/march_runtime.c   *sup_child_slot(supervisor, ...) = pe_pid_or_0(...)
       <- march_one_for_one_restart <- march_supervisor_notify <- do_actor_death_kind
       <- actor_green_thread                       (the CRASHED CHILD's green thread)
Read   rec_field_raw        runtime/march_extras.c   <- march_get_actor_field (Actor.get_field)
       <- the program's main green thread
Location: the supervisor's state record (heap block from Boss_spawn)
```

## Why it is not a one-line atomic

The slot is an ordinary word of the supervisor's actor-state record
(`sup_child_slot`: `supervisor[4 + word_idx]`, or a word of the `$f_state` record under
`--hot-reload`). It is written by whichever thread processes a child's death. It is read
by:

- the supervisor's own **compiled** handler code (a plain field load, not instrumented
  and not changeable from the runtime)
- `march_one_for_all_restart` / `march_rest_for_one_restart`
- actor stop (`march_runtime.c`, the `sup_num_children` teardown)
- introspection (`march_get_actor_field` -> `rec_field_raw`)

Making only the two C sites `__atomic` would quiet this report. It would leave the
compiled-code read racing, and restarts of two children of one supervisor on two
threads would each still read-modify the record unsynchronised.

## Options

- Serialise all restarts of one supervisor, so one thread writes its slots at a time.
  For example: hand the restart to the supervisor's own green thread (as a system
  message), or take a per-supervisor lock around read-slot -> respawn -> write-slot.
- Then write the slot with a release store, and make `rec_field_raw` (introspection
  only) a relaxed load.

Repro: build `test/native/proc_reclaim_kill_respawn.march` with
`MARCH_SANITIZE=thread` and run it with `MARCH_NUM_SCHEDULERS=2` (no debugger attach;
SIGTERM timeout).
