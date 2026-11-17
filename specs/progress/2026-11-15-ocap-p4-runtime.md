# ocap phase 4: run-time authority in every runtime

Plan: specs/plans/2026-11-15-ocap-p4-runtime-plan.md (PR A: Tasks 1–7 and 10). Design:
`specs/2026-11-10-object-capability-design.md` §3–§8, §11, §17 row 4, §18, §21. Language
reference: `specs/lang/capabilities.md`, "Run-time authority".

Every capability operation is checked, as the program runs, against the authority in force,
identically in the interpreter, `--jit`, the REPL, compiled binaries and `--target js`.

## What landed, by task

- **Task 1, the slot.** A per-green-thread authority slot (`march_proc.auth`, read only
  through the `noinline` `march_sched_auth_slot`, never a `_Thread_local` across a
  `swapcontext`), a launch global, and the fast path: `march_cap_check_raw` reads two globals
  (`march_cap_launch`, `march_cap_frames_ever`) and answers "admitted" without touching TLS
  when neither is set. The interpreter and the JS runtime keep the same slot and rule.
- **Task 2, the policy.** `stdlib/authority.march`: the scope parser (the `needs` grammar),
  the lattice, `admits`, `subset`, the layered check (innermost layer first; the refusing limit
  is the innermost one that refuses), `frame_layer`, `enter_fn`, `launch_init`.
  `test/test_authority_differential.ml` pins it against `lib/caps`.
- **Task 3, the launch.** `main`'s request (decision 3: its `needs` clause and `Cap` parameter
  kinds, else the module's `needs` line; `needs ()` requests nothing), narrowed by
  `MARCH_GRANT` / `--grant` (`march`, `march repl [FILE]`, `forge run`). A malformed or wider
  grant is a launch error: one line on stderr, exit 2, before any code runs. One entry rule
  everywhere (a bare `main`, else the last `Mod.main`). A test file's request is its module's
  `needs` line (`Cap_request.test_request`), whatever `main` it declares; doctests and the
  REPL launch with the full authority, narrowed by a grant.
- **Task 4, frames.** `specs/progress/2026-11-15-ocap-p4-function-frames.md`.
- **Task 4b, the native policy in C.** `specs/progress/2026-11-15-ocap-p4-native-authority-in-c.md`.
- **Task 5, function-value capture.** `specs/progress/2026-11-16-ocap-p4-function-value-capture.md`.
- **Task 6, spawn and restart.** `specs/progress/2026-11-16-ocap-p4-spawn-and-restart.md`.
- **Task 7, the conformance suite.** `specs/progress/2026-11-17-ocap-p4-conformance-suite.md`.
- **Task 10, benches, docs, changelog.**
  - `bench/cap_check_slow.march`: 1M `Authority.check` calls inside a scoped frame under a
    scoped launch request (two layers).
  - `bench/cap_capture_closures.march`: the `list_ops` pipeline with captured, composed
    function values (and the same through `List.map` / `filter` / `fold_left`) in a program
    with one frame.
  - Both are gated in `test/test_bench_gate.ml`. `specs/benchmarks.md` maps run-time-authority
    changes to `println_loop clock_loop spawn_loop actor_ping cap_check_slow
    cap_capture_closures list_ops`.
  - The capability chapter of the language reference gained "Run-time authority"; the grant
    table, per-function bounds (scoped clauses are now accepted) and name-scope text were
    corrected.

## Performance (Task 10, macOS arm64, 14 cores, against merge-base 6987fdf50)

The full tables, load averages and the IR-oracle classification are in the PR description
(from `.superpowers/sdd/2026-11-15-ocap-p4-runtime-plan/task-10-perf.md`). In short:

- `scripts/perf-ab.sh --runs 15` over `fib tree_transform binary_trees list_ops
  list_ops_nested json_stream println_loop spawn_loop actor_ping`: all nine within noise on
  cpu. Allocation counters differ only at startup (one allocation fewer in every bench; +4
  bytes in `spawn_loop` and `actor_ping`), never per operation.
- `cap_check_slow`: 97 ms wall for 1M checks through a two-layer authority, about 75 ns per
  check above the fast-path loop; the budget is 1 µs.
- Entering and leaving a frame from outside it (a call of a framed function from unframed
  code) costs about 60 ns: `Authority.enter_fn` reads the slot (`cap_layers`), compares the
  top layer's name and text, and `cap_push`es a new cons cell; `cap_restore` swaps it back
  and releases it. The layer itself is built once per program (`march_cap_layer_once`), so
  nothing is parsed per entry. Not optimised here.
- `cap_capture_closures`: +60–70% cpu over the same file with its one frame removed, from
  `cap_enter` / `cap_restore` around each of three captured closure calls per element. No
  budget gates it; only programs with a frame pay it.
- Hello world (macOS arm64): 252,904 B → 271,800 B; `__TEXT` grows by one 16 KB page.

## Left open

- `specs/todos/2026-11-17-ocap-cross-node-authority.md` (decision 7)
- `specs/todos/2026-11-17-ocap-path-scope-realpath.md` (decision 7)
- `specs/todos/2026-11-17-ocap-framed-mutual-tail-recursion.md` (decision 7)
- `specs/todos/2026-11-17-ocap-env-and-spawn-scopes.md` (decision 7)
- `specs/todos/2026-11-17-ocap-http-transport-retype.md` (decision 7)
- `specs/todos/2026-11-17-ocap-scoped-fn-needs-literal-check.md` (decision 2)
- `specs/todos/2026-11-17-ocap-doctests-launch-full-authority.md`
- `specs/todos/2026-11-17-ocap-in-browser-runtime-no-launch.md`
- `specs/todos/2026-11-15-ocap-p4-frame-follow-ups.md`,
  `specs/todos/2026-11-16-ocap-p4-capture-gaps.md`,
  `specs/todos/2026-11-17-repl-jit-runs-no-conformance-fixture.md`
- PR B (Tasks 8–9): the raw-builtin gate (`specs/todos/2026-11-10-ocap-p1-gate-raw-capability-builtins.md`)
  and the network opens (`HttpServer.*`, `Udp.resolve`). Until then a direct raw-builtin call
  bypasses the run-time check, though not the compile-time one.

Closed with this phase: `specs/progress/2026-11-10-ocap-p1-handle-uses-not-capability-ops.md`
(none of its builtins is in `Cap_ops` or `builtin_cap_table`).
`specs/todos/2026-11-12-ocap-capture-checking.md` (phase 8) is unblocked.
