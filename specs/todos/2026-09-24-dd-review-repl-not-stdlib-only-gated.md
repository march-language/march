# `[P2]` The REPL accepts the stdlib-only builtins, and its test does not exercise the REPL

Filed 2026-09-24 by the distributed-deploys review (step 2, PR #594). The
progress entry says the REPL and its JIT are covered.

## Defect

`lib/repl/repl.ml` typechecks each input with `check_decl`/`infer_expr`
(for example `:134`, `:412`, `:764`, `:1022`) and never runs the gate.
`lib/jit/repl_jit.ml:1004, 1078, 1319` call `check_module_with_env` but
discard its error context (`let (_, type_map) = …`).
`test_repl_is_user_code` (`test/test_stdlib_only.ml:94-101`) calls
`check_module_with_env` directly, so it proves nothing about either REPL.
This also reaches `forge i` and notebooks.

## Confirmed

Piped into the compiler binary's REPL:

- With `MARCH_REPL_INTERP=1`: `pid_of_int(0)` gives `= Pid(0)`,
  `actor_registered()` gives `= []`, and `let pid_of_int = pid_of_int;
  pid_of_int(3)` is accepted. In the same REPL, `Actor.introspect(root_cap)` is
  rejected, so this is a real step up.
- In the JIT REPL: `= {node_id: null, local_pid: 0, creation: 0}`.

## Fix I would make

Run `check_stdlib_only_refs`, or the resolution-based check, on each REPL
input in `repl.ml`. Make `repl_jit` report the errors it now drops. Replace the
unit test with one that drives the REPL entry itself.
