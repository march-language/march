# The 16 interpreter-only builtins: 9 lowered, 6 rejected with a span, 1 deleted

**Landed 2026-09-24.** Every name the todo below listed now either compiles or
fails `--compile` with a March diagnostic; none reaches the linker as
`Undefined symbols: _<name>`.

| builtin | decision | how | evidence |
|---|---|---|---|
| `char_is_alpha` | lowered | `march_char_is_alpha` (C), table row | native golden parity; red on main: `_char_is_alpha` undefined |
| `char_is_uppercase` | lowered | `march_char_is_uppercase` | same golden; red: `_char_is_uppercase` |
| `char_is_lowercase` | lowered | `march_char_is_lowercase` | same golden; red: `_char_is_lowercase` |
| `char_to_uppercase` | lowered | `march_char_to_uppercase`, returns a fresh string | same golden; red: `_char_to_uppercase` |
| `char_to_lowercase` | lowered | `march_char_to_lowercase`, returns a fresh string | same golden; red: `_char_to_lowercase` |
| `float_from_string` | lowered | alias row onto `march_string_to_float` (the interpreter implements both names identically) | same golden; red: `_float_from_string` |
| `print_int` | lowered | `march_print_int`, one `write(2)`, no newline | same golden; red: `_print_int` |
| `print_float` | lowered | `march_print_float`, shares `march_format_float_ocaml` with `march_float_to_string` | same golden (`3.`, `inf`, `1e+20`); red: `_print_float` |
| `tap` | lowered | `lower_expr.ml` rewrites `tap(x)` to `x` | same golden (Int, String, List, Float, via a generic fn, and a local named `tap`); red: `_tap` |
| `Supervisor.stop_child` | rejected | `Lower_expr.interpreter_only_builtin_reasons` | codegen test `interpreter_only_dsl` 2; red on main (link error) |
| `Supervisor.which_children` | rejected | same | same test |
| `Supervisor.count_children` | rejected | same | same test |
| `App.stop` | rejected | same | same test |
| `task_spawn_link` | rejected | same, plus its type fixed to `(Int -> a, Pid(b)) -> Task(a)` | same test; interpreted call now typechecks and returns 99 |
| `to_json` | lowered via dispatch; missing codec is a diagnostic | `Llvm_calls.fail_if_unresolved_iface_method` now also fires when no JsonTo impl exists anywhere | codegen test `interpreter_only_dsl` 4; red on main: `_to_json` undefined |
| `respond` | deleted | removed from typecheck, eval, defun, purity and REPL completion | an interpreter no-op stub (`[_] -> VUnit`) with no callers in stdlib, tests or docs |

## Why each rejected name is not lowered

- **The dynamic-supervisor queries** read the interpreter's `dyn_sup_registry`,
  which only `dynamic_supervisor(...)` fills, and that call was already
  rejected at lowering. A compiled program has no dynamic supervisor to query.
  A compiled port means building a dynamic-supervisor runtime in C, which is a
  design task and out of scope here.
- **`App.stop`** sets the interpreter's `shutdown_requested` for an `app`
  declaration. Compiled lowering ignores `DApp` completely. The diagnostic
  points the user to returning from `main` or calling `process_exit`.
- **`task_spawn_link`** runs its thunk eagerly and fails if the linked actor is
  dead. The compiled task runtime has no task/actor link, so lowering it to
  `task_spawn` would silently drop the link. The diagnostic suggests
  `task_spawn` plus `monitor` or `is_alive`. Its type was also wrong: it
  declared one argument while the interpreter takes `(f, pid)`, so every
  typechecked two-argument call failed with "This is not a function".

The rejection message used to be the supervisor-spec sentence for every name.
It is now a per-name reason (`interpreter_only_builtin_reasons`).

## `tap`

The interpreter pushes `x` onto a bus that only the REPL drains
(`Repl` → `Eval.tap_drain`). A compiled program has no REPL, so the identity
is all a compiled program can observe. The rewrite fires for `tap(x)` when no
module fn, parameter or let-bound local named `tap` is in scope. A first-class
`tap`, as in `List.map(xs, tap)`, is a positioned lowering error that suggests
`fn x -> tap(x)`. It is not given a symbol: a polymorphic C identity would need
its erased-slot ABI worked out for each type.

## `to_json`

A call on a type with a derived codec already resolved to `JsonTo$T.to_json`
(lowering, or Mono for a generic caller). If the type had no impl but some
other type did, `fail_if_unresolved_iface_method` already reported
"no `JsonTo` implementation for type `T`". The link error happened only when
NO type in the program derived Json, because that check then had no candidates
and did nothing. That case now raises the same kind of error. For a primitive it
suggests building the `JsonValue` directly, since `derive Json for Int` is not
possible. This check has no span, like its sibling. A positioned typechecker
check was considered and not done: `json_cap_sites` records any EVar named
`to_json`, including user functions, so a head-type check there would reject
valid programs.

## Guard

`test/test_builtin_compiled_lowering.ml`: `interpreter_only` now holds exactly
the nine names rejected at lowering (the four earlier supervisor-DSL names plus
the five above), and a new case checks that it EQUALS
`Lower_expr.interpreter_only_builtins`. A listed name can no longer link-fail
silently, and a rejected name cannot go unaccounted. `to_json` and `tap` moved
to `special_lowerings` with their routes.

## Other sites

- `Borrow.extern_borrow_table`: the five char builtins are `[true]` and
  `float_from_string` is `[true]`. The C only reads the argument, and every
  Char producer returns an owned or immortal reference. **Mutation:** with
  the five char entries removed, the golden's leak leg printed `flat: false`
  (10,000 fresh chars leaked). With them present it prints `flat: true`.
- `Alloc_contract.scalar_builtins`: `char_to_uppercase` and
  `char_to_lowercase` were listed as non-allocating. They allocate, so they
  were removed from the list. (`char_from_int` and `byte_to_char` are still
  listed and also allocate through `march_char_from_int`. That is an older
  mislabel and was not changed here.)
- The preamble golden in `test/test_codegen.ml` gained 7 declares.

## Verification (local, targeted)

- Native golden `test/native/interpreter_only_builtins_lowered.march`: its
  `.expected` is the interpreter's output, and the dune rule
  `test/native_interpreter_only_builtins_lowered.out` compiles with `--opt 2`
  and diffs against it. It passed.
- Red on origin/main (production files swapped back, tests kept): the golden
  failed to link (`_char_is_alpha _char_is_lowercase _char_is_uppercase
  _char_to_lowercase _char_to_uppercase _float_from_string _print_float
  _print_int _tap`). `builtin_compiled_lowering` 0 and 2 failed. The three
  new `interpreter_only_dsl` cases and the three byte-identical preamble
  cases failed.
- Green: `run_compiler` groups `builtin_compiled_lowering`,
  `builtin_borrow_classification`, `alloc_contract` and `cap_no_alloc`, and
  `run_codegen` groups `interpreter_only_dsl` and
  `llvm_builtins_preamble_golden`.

The ABI audit of the "same-named runtime C function" group (the `logger_*`
family and others), suggested below, is still not done.

---

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
