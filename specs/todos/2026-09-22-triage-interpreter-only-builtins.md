# Triage the typechecked builtins that still have no compiled lowering

Filed 2026-09-22 with `specs/progress/2026-09-22-compiled-lowering-float-builtins.md`.

`test/test_builtin_compiled_lowering.ml` accounts for every name in
`Typecheck_builtins.builtin_bindings`. These 16 have no compiled lowering and
sit in its `interpreter_only` allowlist, so a `--compile`d call to any of them
fails at LINK time with `Undefined symbols: _<name>` and no March span:

| builtin | notes |
|---|---|
| `App.stop` | supervisor/app DSL |
| `Supervisor.count_children` | supervisor DSL |
| `Supervisor.stop_child` | supervisor DSL |
| `Supervisor.which_children` | supervisor DSL |
| `char_is_alpha` | link failure confirmed 2026-09-22; siblings `char_is_digit` etc. DO have rows |
| `char_is_lowercase` | |
| `char_is_uppercase` | |
| `char_to_lowercase` | |
| `char_to_uppercase` | link failure confirmed 2026-09-22 |
| `float_from_string` | returns `Option(Float)` |
| `print_float` | link failure confirmed 2026-09-22 |
| `print_int` | link failure confirmed 2026-09-22 |
| `respond` | link failure confirmed 2026-09-22 |
| `tap` | link failure confirmed 2026-09-22 |
| `task_spawn_link` | |
| `to_json` | link failure confirmed on a bare `to_json(3)`; derived `JsonTo` impls may cover real uses |

For each, decide one of:

1. **Lower it**: a row in `lib/tir/llvm_builtins.ml` backed by a runtime C
   function, or a `Builtin_name` arm in `llvm_emit.ml`. Add a compiled-vs-
   interpreted test, and remove it from the allowlist (the guard's stale
   check will insist).
2. **Reject it at compile time** with a positioned diagnostic by adding it to
   `Lower_expr.interpreter_only_builtins` (as `worker` / `Supervisor.spec`
   already are), then move it from the test's `interpreter_only` list to its
   `special_lowerings` list under that route.
3. **Delete it** from the typechecker if nothing uses it.

The guard's `special_lowerings` "same-named runtime C function" group (the
`logger_*` family, `dns_resolve`, `http_fetch`, `uuid_v7`, `__try_call`, ...)
was accepted because the symbol links, not because its C signature was checked
against the TIR call. Auditing those ABIs is a separate, cheaper pass worth
doing alongside.
