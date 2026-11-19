# ocap phase 4: the conformance suite runs every enforcement test in every runtime

Plan: specs/plans/2026-11-15-ocap-p4-runtime-plan.md, Task 7. Design §18 ("every
enforcement test on every backend"), §3, §5, §7, §11, §21.

## The runner (test/run_cap_conformance.ml)

- Headers, each optional, on the fixture's leading lines:
  - `-- GRANT: <scopes>` is exported as `MARCH_GRANT`; `-- GRANT:` with nothing after it
    exports the empty string (read as unset). Without it `MARCH_GRANT` is unset.
  - `-- EXIT-ONLY` compares only the exit status and stderr's first line (launch errors).
  - `-- REFUSE:` is gone, with the `MARCH_TEST_REFUSE` hook it exported.
- Five runtimes: interpreter, `--jit`, compiled, JS (node) and a new `repl` mode:
  `march repl --grant G <fixture>` with the lines of `main`'s body typed at the prompt.
  The REPL has no `main` and requests the full authority (design §21), so G is the
  header's grant, else `main`'s request when it carries a scope (the launch layer is then
  identical), else none. Prompts and echoes are dropped from its stdout.
  - It runs the interpreter engine (`MARCH_REPL_INTERP=1`): the JIT engine cannot run any
    fixture, for reasons that predate phase 4
    (specs/todos/2026-11-17-repl-jit-runs-no-conformance-fixture.md).
  - `repl_unsupported`: the two actor fixtures (the REPL mode is for fixtures without
    actors) and `grant_wider_launch_error` (no grant is wider than the REPL's request).
- `js_unsupported` gains the actor/task fixtures with "the JS target has no tasks", and
  `capture_stored_in_record_list_vault` (the JS target has no tables).

## Fixtures

All existing `-- REFUSE: K` fixtures became `-- GRANT: <request minus K>`; `.expected` is
unchanged except for the refusing limit's scope, now the grant text. `refuse_two_exact`
changed one more line: a grant of `IO.FileWrite` does not admit its lattice parent
`IO.FileSystem` (the hook had matched kinds exactly). `tls_https_get_refused` grants
`IO.NetConnect.TLS` (the TLS context check still passes, the connect is refused).

New (each hand-checked against its design rule before generating): `grant_narrower_refuses`,
`grant_wider_launch_error`, `grant_malformed_launch_error`, `grant_empty_string_is_unset`,
`grant_unit_grants_nothing`, `request_scoped_computed_path_refused`,
`request_from_module_needs`, `path_scope_relative_and_dotdot`, `host_scope_computed_refused`,
`name_scope_computed_refused`, `fn_scoped_needs_refuses`, `nested_fn_needs_intersect`,
`frame_reenter_noop`, `capture_inside_called_outside`, `capture_outside_called_inside`,
`capture_named_fn_value`, `capture_partial_application` (March has no partial application:
the explicit eta-lambda `fn p -> Authority.check("IO.FileRead", p)`),
`capture_stored_in_record_list_vault`, `toplevel_closure_runs_under_caller`,
`no_scope_program_unchanged`. Task 6 added the actor/task three.

## Fixed on the way

- **Interpreter REPL: a prompt `let`'s function value captured nothing.** `eval_decl` ran
  every top-level `let` as module-level code (design §21: captures nothing), the prompt's
  too, so `let f = fn p -> ...` typed at the prompt ran under whatever frame later called
  it. `capture_outside_called_inside` showed it. `Eval.eval_prompt_decl` evaluates a
  prompt `let` as ordinary code; a preloaded or `:load`ed module's lets still capture
  nothing.
- **`march repl FILE --grant G`** was read as a second preload file; it now narrows the
  REPL's launch, as `march --grant G` with no file did.
- **REPL JIT: a polymorphic fn declared at the prompt crashed on its first call.** The
  fragment has no instantiated body for it; `run_decl` fell back to `List.hd`, which on
  this branch picked a lifted Authority-policy lambda. It now fails with
  `no compiled body for `f`` (on main it failed with `hd`).
- **The `MARCH_TEST_REFUSE` hook and the `cap_launch_text` builtin are removed** from the C
  runtime, the interpreter, the JS runtime, the builtin tables and `Authority.check_slow`.
  `march_cap_check_raw`'s fast path no longer calls `pthread_once` per check.
