# ocap phase 4: actors and tasks run under their spawner's authority; restarts restore the first spawn's

Plan: specs/plans/2026-11-15-ocap-p4-runtime-plan.md, Task 6.

Design §7: a worker spawned under a limit is limited for life, and a supervisor restart
restores the authority of the child's first spawn.

## Native and JIT runtime (runtime/march_runtime.c)

- `march_actor_meta.auth` holds an owned reference to the spawner's slot. It is set in
  `march_spawn_common` before activation and released by `meta_free`.
- `actor_install_auth` puts `meta->auth` into the actor's own proc slot. It runs:
  - before the first handler;
  - again before `on_stop`.

  The proc otherwise inherits whatever slot its activator had:
  - for an ordinary spawn, that is the spawner's;
  - for a supervised child, it is whatever is in force at registration or at a restart.
- `march_sup_child.first_auth` holds an owned reference to the child's `meta->auth` at
  `march_actor_register_child`. It is released with the supervisor's meta.
  `march_respawn_child` enters `first_auth` around the spawn thunk and
  `march_spawn_supervised`, so the replacement's `init` and its whole life run under
  the first spawn's authority. Before this fix, what ran was:
  - **after a crash inside a frame:** the dying handler's innermost frame, because the
    crash longjmp skipped its restore;
  - **after a kill from main:** the killer's slot, which is the launch authority, i.e. a
    widening;
  - **after a delayed restart:** whatever thread the restart ran on.
- Tasks already inherited through `sched_spawn_common` (Task 1).
  `march_task_spawn_with_cancel_thunk` goes through `march_sched_spawn_with_cancel` →
  `march_sched_spawn` → `sched_spawn_common`, so it copies too.

## Compiled capture pass (lib/tir/auth_rt.ml)

- `Auth_rt.captures` no longer wraps an actor's runtime-held glue fns in a capturing eta
  closure: `A_dispatch`, `A_on_stop`, `A_inspect` and `A_spawn`, for each `A_Actor`
  record type.
- Why: the runtime calls these through borrowing trampolines, so a heap closure there
  was released once per message. Any framed program whose actor handler reached a
  capability op aborted at exit with "RC underflow".
- They need no capture: they run on the actor's own proc, under `meta->auth`.

## Interpreter (lib/eval)

- The slot (`cap_slot`, `cap_nil`) moved to `Eval_runtime`; `Eval_builtins` re-exports
  it.
- `actor_inst.ai_authority` is the slot at the first spawn. It is recorded at these
  sites:
  - `ESpawn`;
  - supervise-block children;
  - `spawn_from_spec`;
  - restarts, which copy it from the crashed incarnation in `spawn_child_actor`, the
    path every strategy and dynamic supervisors go through. A restart also evaluates
    the replacement's `init` under it.
- `with_actor_authority` installs it around every handler (`run_scheduler`), the
  shutdown handler (`shutdown_actor_pid`) and `on_stop` (`run_on_stop`), and restores
  the slot afterwards, also on an exception. The interpreter runs handlers nested inside
  whatever is in force: a send from main, or an `Actor.call` pumping the scheduler from
  inside a frame.
- Interpreter tasks run eagerly on the spawner's stack, so they inherit the slot with no
  change.

## Tests

- `test/cap_conformance/`: three new fixtures.
  - `actor_under_frame_restricted`;
  - `actor_restart_keeps_authority`: restarts after both a crash inside a narrower frame
    and a kill from main;
  - `task_inherits_capture`.

  The runner's header is generalised: an optional `-- GRANT:` (`MARCH_GRANT`), and
  `-- REFUSE:` becomes optional. The JS target skips the three fixtures with "the JS
  target has no tasks".
- `test/test_auth_rt.ml`: an actor spawned only through a function value runs under the
  frame, and the interpreter and compiled code agree (Task 4's deferred case).
- `test/test_cap_runtime_slot.ml`: 10,000 spawn/exit cycles under a frame (actor, task,
  and a supervisor every tenth cycle), compiled with `--rc-trace`. Every
  authority-touched address must balance, up to 16 still held by the last killed
  actors. With `meta_free`'s release removed, about 20,000 addresses are unbalanced.
