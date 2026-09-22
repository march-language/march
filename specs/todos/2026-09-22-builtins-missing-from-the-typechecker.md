# `[P2]` 15 builtins the interpreter and codegen implement but the typechecker does not know

Filed 2026-09-22 from the stdlib internal-error sweep
(`2026-09-22-stdlib-internal-type-errors.md`). The exact mirror image of
`2026-09-22-triage-interpreter-only-builtins.md`, which tracks builtins the
TYPECHECKER knows and codegen cannot lower.

These names have an `eval_builtins.ml` entry and an `llvm_builtins.ml` row but
no binding in `Typecheck_builtins.builtin_bindings`, so the stdlib wrapper that
calls each one is "I cannot find `<name>`":

| builtin | stdlib caller |
|---|---|
| `sys_os` | `system.march:33` |
| `sys_arch` | `system.march:41` |
| `sys_cpu_count` | `system.march:46` |
| `sys_cpu_load_milli` | `system.march:56` |
| `sys_mem_total_bytes` | `system.march:61` |
| `sys_mem_available_bytes` | `system.march:66` |
| `sys_uptime_ms` | `system.march:101` |
| `march_version` | `system.march:195` |
| `print_stderr` | `io.march:31`, `logger.march:490` |
| `io_read_line` | `io.march:39` |
| `io_read_byte` | `io.march:54` |
| `uuid_v4` | `uuid.march:154` |
| `sha1_bytes` | `uuid.march:289` |
| `stdlib_sha512` | `crypto.march:135` |

The wrapper still RUNS — the interpreter and the compiled backend both have the
symbol — but its body never typechecked, so its return type is whatever the
caller's unconstrained metavariable becomes. `println(string_length(System.os()))`
compiles and dies at runtime with "string_length: expected string", because
`os()` actually returns an atom.

For each: add the binding with the type the interpreter and the runtime C
function actually agree on (check both — the point of this item is that nobody
has), or delete the wrapper if the builtin is dead. `uuid_v4` may be a rename
(the typechecker knows `uuid_v7`); confirm before adding it back.
