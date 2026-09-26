# Builtins that linked only because a same-named C function existed: audited

Filed 2026-09-24 as `specs/todos/2026-09-24-audit-same-named-runtime-builtin-abis.md`
(split out of `specs/progress/2026-09-24-interpreter-only-builtins.md`). Closed
2026-09-26.

## The problem

`Llvm_builtins.mangle_extern` maps a March builtin to its C symbol through the
row's `c_name`. A name with no row falls through to itself. `Llvm_emit_call`
then synthesizes a `declare` from the call site's March types, and the call
links only if the runtime happens to define a C function of that exact name.
Nothing checked that declare against the C prototype. The borrow guard
(`test_builtin_borrow_classification`) only sees table rows, so these builtins
had no ownership classification either: every heap argument defaulted to OWNED.

`test/test_builtin_compiled_lowering.ml` accepted sixteen builtins this way in
`special_lowerings`: `__try_call`, `__try_call_val`, `http_fetch`,
`http_fetch_available`, and the twelve Logger v2 builtins (`logger_add_field`,
`logger_field_count`, `logger_get_fields`, `logger_pop_to_depth`,
`logger_dispatch`, `logger_register_appender`, `logger_remove_appender`,
`logger_clear_appenders`, `logger_appender_names`, `logger_set_module_level`,
`logger_clear_module_level`, `logger_module_level`). `dns_resolve`, `uuid_v7`
and `uuid_v7_at` had already left the group
(`specs/progress/2026-09-25-runtime-symbol-naming-and-uncompiled-caps.md`).

## How the set was enumerated

Three sources were joined:

1. The typechecker's builtins (`Typecheck_builtins.builtin_bindings`). The
   existing total-accounting test proves that each one is a table row, a
   `Builtin_name`, a SIMD op, interpreter-only, or in `special_lowerings`.
2. The codegen table. 129 rows have `c_name = None`. 31 have no declare (the
   operators, `task_*`, `int_and` and similar, each with a dedicated emit arm).
   The rest declare their own symbol: `march_*` names, the typed native arrays
   (`native_*`) and the ring buffer (`ring_buf_*`), all with explicit
   prototypes.
3. The runtime's real ABI. Every `runtime/*.c` in `runtime/sources.list` was
   compiled with `clang -S -emit-llvm`, and each `define` line was compared,
   parameter by parameter at the LLVM type level, with every `declare` the
   compiler emits. The preamble covers every row. The sixteen synthesized
   declares came from `--emit-llvm` on probe programs.

That leaves exactly the sixteen `special_lowerings` names as calls with no
checked prototype.

## Audit table

"Declare" is what the compiler emitted on origin/main. "C" is the definition.

| builtin | declare (origin/main) | C | ABI | ownership / behaviour | verdict |
|---|---|---|---|---|---|
| `__try_call` | synthesized `ptr (ptr)` | `void *(void *)` | agrees | thunk consumed by its own apply fn (`$clo` drop), as documented | OK; renamed `march_try_call`, row added |
| `__try_call_val` | synthesized `ptr (ptr)` | `void *(void *)` | agrees | as above; Int/Float/String/tuple results round-trip | OK; renamed `march_try_call_val` |
| `http_fetch_available` | synthesized `i64 ()` | `int64_t (void)` | agrees (raw Bool) | none | OK; renamed |
| `http_fetch` | synthesized `ptr (ptr,ptr,ptr,ptr)` | `void *(4 × void *)` | agrees | 4 Strings owned by default, never freed: **leak** (~3 objects per call; dead code on native) | borrowed |
| `logger_add_field` | synthesized; **none** through `$clo_wrap` | `void *(void *, void *)` | agrees when declared | stores both (owned, correct) | **`Logger.with_fields` / `with_scope` did not compile** (`use of undefined value '@logger_add_field'`), fixed by the row and `Defun.builtin_names` |
| `logger_field_count` | `i64 ()` | `int64_t (void)` | agrees | none | OK |
| `logger_get_fields` | `ptr ()` | `void *(void)` | agrees | **returned the runtime's stack without a reference**: the caller's drop freed it, then `RC underflow` abort / use-after-free | `march_incrc` before return |
| `logger_pop_to_depth` | `ptr (i64)` (via `with_scope`) | `void *(int64_t)` | agrees | popped cells and fields never released: **leak** per scope | pops release cell, field, key, value |
| `logger_dispatch` | `ptr (ptr,ptr,ptr,ptr)` | `void *(4 × void *)` | agrees | owned by default, never freed: **leak** (~4 objects per log line); printed the context stack a second time | borrowed; prints `fields` only |
| `logger_register_appender` | `ptr (ptr,ptr)` | no-op | agrees | owned by default: leak | borrowed (appenders stay unimplemented compiled, see below) |
| `logger_remove_appender` | `ptr (ptr)` | no-op | agrees | leak | borrowed |
| `logger_clear_appenders` | `ptr ()` | no-op | agrees | none | OK |
| `logger_appender_names` | `ptr ()` | returns Nil | agrees | none | OK |
| `logger_set_module_level` | `ptr (ptr, i64)` | `void *(void *, int64_t)` | agrees | **no-op**; String leaked | implemented (name copied); borrowed |
| `logger_clear_module_level` | `ptr (ptr)` | **no-op** | agrees | String leaked | implemented; borrowed |
| `logger_module_level` | `i64 (ptr)` | `int64_t (void *)` | agrees | **always the global level**; String leaked | implemented; borrowed |

The v1 rows that already had `c_name`s had the same defects, so they were
fixed with the rest:

- `march_logger_get_context` returned its stored list without a reference.
- `march_logger_write` was listed OWNED as "unaudited". It only reads its
  arguments, so it is now borrowed.
- The v1 context was a separate list from the v2 field stack. The interpreter
  keeps one stack, so `Logger.with_context` fields never reached a compiled
  log line, and `Logger.clear_context` ("Remove all log fields (v1 + v2)")
  left every v2 field in place. `add_context` now pushes
  `LogField(k, LStr(v))` onto the one stack, `clear_context` pops it all, and
  `get_context` renders a fresh `List((String, String))` from it.
- The global level started at Debug (0). The interpreter starts at Info (1).
- Unit returns allocated a 16-byte cell that nobody released. They now return
  0, the compiled Unit.
- A `LFloat` printed with `%g`. It now uses OCaml's `string_of_float` format
  (`2.` not `2`), as the interpreter does.

The IR-level comparison found **no declare/define type mismatch** among the
506 declared prototypes. It found two other problems:

- `march_dir_list_full` was declared, and had a row, a `Defun` entry and a
  borrow entry, but no C definition, no typechecker binding and no
  interpreter arm. It was a dead row, noted and left in place in
  `specs/progress/2026-09-08-file-dir-builtins-fileerror-representation-fix.md`.
  **Removed.**
- `march_send_linear`, `march_msg_copy`, `march_msg_move` and
  `march_process_alloc` are declared in the native preamble but defined only
  by the unit-test-only arena runtime (`march_message.c`, `march_heap.c`),
  which the driver never links. `llvm_emit.ml` emits `march_send_linear` for
  a `send` whose message variable is linear. That path is latent today: a
  destructured `let (m, _) = (Increment(5), 1); send(c, m)` still compiles to
  `march_send`. A program that reached it would fail to link. The four names
  are pinned in the new test. Filed:
  `specs/todos/2026-09-26-send-linear-declared-but-never-linked.md`.

## What changed

- **Runtime.** The sixteen C functions are now `march_try_call`,
  `march_try_call_val`, `march_http_fetch`, `march_http_fetch_available` and
  `march_logger_*`, declared in `runtime/march_runtime.h` /
  `runtime/march_http.h`. The logger fixes listed above are in
  `runtime/march_runtime.c`.
- **Codegen table.** Each builtin has a row with `c_name` and `declare_sig`,
  plus a `PDeclare` in the preamble: the try-call pair next to `try_finally`
  (with `in_is_builtin = false`, since both invoke a closure), the logger next
  to the v1 logger rows, and `http_fetch` next to `http_parse_response`. All
  sixteen are also in `Defun.builtin_names`, so a call from a local fn or a
  lambda stays a direct call instead of a `$clo_wrap` closure.
- **Borrow.** In `extern_borrow_table`: `logger_write`, `logger_dispatch`,
  `logger_register_appender`, `logger_remove_appender`, the module-level trio
  (the level Int is not borrowed), and `http_fetch`. In
  `extern_owned_builtins`: `logger_add_field` (it stores its arguments), next
  to `logger_add_context`.
- **Tests** (`test/test_builtin_compiled_lowering.ml`):
  - The same-named group is gone from `special_lowerings`.
  - New Quick test: "no builtin reaches codegen through an unchecked identity
    fallthrough". A row with no `c_name` passes only if it has no declare and
    is one of the listed dedicated-emit rows, or if it declares its own symbol
    and that symbol is `march_`-prefixed or in the explicit `native_` /
    `ring_buf_` / `bytes_to_u8_arr` / `u8_arr_to_bytes` allowlist. The test
    also asserts that the sixteen now resolve to `march_*` symbols.
  - New Slow test: "every declared runtime prototype matches its C
    definition". It compiles the runtime to IR, compares every native
    preamble declare with its `define`, pins the four unit-test-only
    definitions, and fails if a `special_lowerings` name is a runtime C
    function (the route this audit closed).
- **Parity fixture.** `test/native/same_named_builtin_abi_parity.march` runs
  interpreted and compiled against one stdout golden and one stderr golden
  (the log lines), and has two lines in `test/refine_audit/corpus.baseline`.

## Evidence

RED on origin/main at `1877afc22`, measured with a
compiler built from `git archive origin/main`:

- `Logger.current_fields()` read twice: `march: RC underflow (rc was 0) at
  0x… — aborting`, exit 134. The interpreter printed both reads.
- `Logger.with_fields([...])`: `clang: error: use of undefined value
  '@logger_add_field'` in `define ptr @logger_add_field$clo_wrap(...)`.
- The fixture without the two constructs that could not compile, compiled:
  `default level: 0` (interpreted: 1), `Noisy level: 0` / `Other level: 0`
  (3 / 1), `module levels x200: 0` (4200), `module levels leaked nothing:
  false`, `dispatch leaked nothing: false`. On stderr, `Noisy`'s filtered-out
  Warn line was logged, and after the first `current_fields()` the context
  fields were gone from every later line.
- `live_allocs` growth over 100 calls: `logger_dispatch` 403,
  set/level/clear module level 302, `http_fetch` 306. After the fix each is a
  small constant that does not grow with the call count, and the fixture's
  warmed-up loops measure 0.
- Before the fix, one run printed the context fields twice:
  `[INFO] hello {ok=true, fl=1.5, n=42, user=alice, ok=true, fl=1.5, n=42, user=alice}`.

GREEN:

- The fixture's four diffs (compiled and interpreted, stdout and stderr) are
  identical.
- Perturbation: the new pop-release code was removed from a copied runtime,
  and `with_scope leaked nothing: false` appeared, so the leak line is not
  vacuous.
- The Slow prototype test turns RED on a perturbed declare:
  `march_logger_module_level: declared i64(ptr, i64), C defines i64(ptr)`.
- The Quick fallthrough test turns RED on a row added with `c_name = None`
  and an unprefixed declare (`foo_bar (unprefixed C symbol reached through
  the identity fallthrough)`), and on one added with neither (`baz_qux (no
  c_name, no declare, no dedicated emit arm)`).

## Found, not fixed

- **Compiled Logger appenders are no-ops.** `Logger.add_appender`'s callback
  never runs compiled, and `list_appenders()` is always empty. Filed:
  `specs/todos/2026-09-26-compiled-logger-appenders-are-no-ops.md`.
- **`LAtom` values render as `null` compiled** (interpreted: `:name`). Atoms
  are interned integers and the runtime has no name table. Recorded in the
  appenders todo, since both live in the compiled logger runtime.
- **`__try_call*` Err messages differ.** The interpreter gives `panic: boom`,
  compiled gives `boom`. Filed:
  `specs/todos/2026-09-26-try-call-err-message-divergence.md`.
- **`http_fetch` differs on native.** The interpreter raises an eval error;
  the compiled stub returns `Err(msg)`. Both are dead code behind
  `http_fetch_available() == false`. Not filed.
- The declared-but-never-linked `march_send_linear` family is covered above.
