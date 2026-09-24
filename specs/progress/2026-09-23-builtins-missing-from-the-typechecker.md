# Fixed 2026-09-23: 14 builtins the interpreter and codegen implement but the typechecker did not know

Each now has a `Typecheck_builtins.builtin_bindings` entry. The type was taken
from what the interpreter (`lib/eval/eval_builtins.ml`) and the C runtime
actually do, checked side by side. Where they disagreed, the disagreement was
fixed, not papered over by the binding; five of the fourteen disagreed.

| builtin | binding | capability | interpreter vs C: what was checked / fixed |
|---|---|---|---|
| `sys_os` | `() -> String` | ambient | **Disagreed three ways.** Interpreter returned a nullary `VCon` (not a `VAtom`, so `== :macos` was false even interpreted); codegen row said `TString`; **`march_sys_os` did not exist in C**, so any compiled program calling `System.os()` failed to link. Now a lowercase String everywhere; C implemented with `uname(2)`. |
| `sys_arch` | `() -> String` | ambient | Same as `sys_os` (`march_sys_arch` added). Values `x86_64` / `aarch64` / `x86` / lowercased uname machine. |
| `sys_cpu_count` | `() -> Int` | ambient | Agree. |
| `sys_cpu_load_milli` | `() -> Int` | ambient | Agree on type; interpreter is `/proc`-only (0 on macOS), as its comment already documents. |
| `sys_mem_total_bytes` | `() -> Int` | ambient | Same as above. |
| `sys_mem_available_bytes` | `() -> Int` | ambient | Same as above. |
| `sys_uptime_ms` | `() -> Int` | ambient | Agree. Kept ambient on purpose: gating it to `IO.Clock` like `unix_time_ms` was tried and broke `test/native/timer_leak_probe.march` (a Console-only `main` timing itself with `System.monotonic_time`). It is process-relative elapsed time, not the wall clock, and gating it would break every such caller in a bugfix. |
| `march_version` | `() -> String` | ambient | **Disagreed.** Interpreter said `"0.1.0"`, C said `"march/dev"`, the compiler is 0.4.0. Now both come from dune-project's `(version ...)` via a generated `March_ast.March_version`: the interpreter returns it and `lower_expr` folds every direct call into a string literal. The C `march_get_version` and its codegen row were removed (nothing references them). |
| `print_stderr` | `String -> ()` | `IO.Console` | **Disagreed.** C appended a newline, the interpreter did not; both callers (`IO.warn`, `Logger.appender_stderr`) add their own `"\n"`, so compiled output had a blank line after every warning. C no longer appends. Gated like `print`. |
| `io_read_line` | `() -> String` | ambient (as `read_line`) | **Disagreed on edges.** C truncated at 4096 bytes (a long line came back in pieces) and stripped `\r`; the interpreter kept `\r`. C now uses `getline`; the interpreter strips a trailing `\r` (for `read_line` too). |
| `io_read_byte` | `() -> Int` | ambient (as `read_byte`) | Agree (`-1` on EOF). |
| `uuid_v4` | `() -> String` | `IO.Random` (already in the cap table) | Agree. **Not** a rename of `uuid_v7`: both are live, distinct generators and `UUID.v4`/`UUID.v7` wrap one each. |
| `sha1_bytes` | `Bytes -> Bytes` | ambient | **Disagreed.** The interpreter accepted String or Bytes; C read its argument as a String. The only caller (`UUID.v5`) passes Bytes, so **compiled `UUID.v5` crashed with SIGBUS**. C now reads Bytes. |
| `stdlib_sha512` | `String -> String` | ambient | **Disagreed.** C `march_sha512` was a stub returning the **SHA-256** digest. Now a real FIPS 180-4 SHA-512 (a copy of tweetnacl.c's, which is static and linked only into hot-reload builds). `Crypto.sha512` is annotated `String -> String`, like `stdlib_sha256`. |

Public wrapper signatures: `System.os/arch : () -> String` (the docs said atom;
no caller in the tree depended on either shape), `Crypto.sha512 : String -> String`.

## How it was checked

- `march --check stdlib/{system,io,uuid,crypto,logger}.march`: 0 errors each,
  except logger's unrelated `logger.march:208` one-off. The ratchet
  (`test_stdlib_internal_errors_ratchet`) lost the system/io/uuid/crypto rows
  and logger went 2 → 1.
- `test_stdlib_builtin_wrappers_have_real_types` (test/test_compiler.ml)
  typechecks a user module against the whole stdlib and requires an error on
  exactly the lines that misuse a wrapper's type. Red on origin/main (the
  `System.os() + 1`, `System.arch() : Bool`, `Crypto.sha512` result and
  argument misuses were all accepted), green here.
- One probe program run interpreted and compiled: `System.version/os/arch`,
  `Crypto.sha512` (matches `shasum -a 512`, including the 2-block padding
  case), `UUID.v5` (matches Python's `uuid.uuid5`), `IO.warn` (identical
  stderr bytes), `IO.read_line` on a CRLF line. All agree. Before: the compiled
  run printed `march/dev`, the SHA-256 digest, then died with SIGBUS in `UUID.v5`.

Out of scope, noted: the JS backend lowers `print_stderr` to `console.error`,
which appends a newline.

---

Original filing:

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
