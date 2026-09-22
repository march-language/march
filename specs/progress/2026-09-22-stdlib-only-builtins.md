# Stdlib-only builtins: the mechanism, landing with an empty set

**DONE 2026-09-22.** G3 of
[specs/plans/2026-09-21-distributed-deploys-groundwork-plan.md](../plans/2026-09-21-distributed-deploys-groundwork-plan.md).

Two parts of the distributed-authority plan need builtins that user code cannot
call: the raw reference-forging builtins once `Actor.introspect` exists (II.1)
and `epoch_hold`/`epoch_release` (II.4.4). Nothing gated a builtin on the
caller before this.

## What landed

- `Typecheck_builtins.stdlib_only : (string * string) list ref`: builtin name
  and the suggestion shown to user code. **Empty.** II.1 and II.4.4 populate
  it. A ref, so tests can install an entry around one check.
- `Typecheck_caps.check_stdlib_only_refs env decls`: for each `DFn` (body,
  guard, default arguments), `DLet` and actor (`init` and every handler) whose
  declaration span is not a stdlib file, a reference to a listed name is an
  error:

  ```
  `pid_of_int` is internal to the standard library; use `Actor.list(cap)` (see `Actor.introspect`)
  ```

  "Referenced" is decided by `free_vars_expr`, so a value use (`let f =
  pid_of_int`) counts and a parameter or `let` of the same name shadows it; a
  module that declares its own function of that name is not gated
  (`locally_declared_names_of`, as Check 1b does). The error sits on the call
  when there is one, else on the declaration. One error per (declaration,
  name).
- Called from `check_module_needs` beside Check 1b (so every module, nested
  ones included), and from `Typecheck.check_module_with_env` for the REPL's
  top-level fragment, which never goes through `check_module_needs`.
- One "is this file the stdlib's?" predicate:
  `Typecheck_builtins.file_is_stdlib` (membership in `stdlib_source_files`,
  set by the driver from the stdlib declarations it prepends).
  `span_is_stdlib`, the gate, and the driver's diagnostic filter
  (`bin/main.ml`, `user_diag_file`) all use it. The filter now never treats a
  stdlib file as the user's unless it is the entry file
  (`march --check stdlib/<mod>.march`), so a gate error can never land in a
  file the filter hides as the stdlib's, nor the reverse.

## Tests

`test/test_stdlib_only.ml` (group `stdlib-only builtins`, run by
`run_compiler.exe`), each with a throwaway `pid_of_int` entry:

| Case | Asserts |
|---|---|
| user call rejected | the error text above |
| user value reference rejected | `let f = pid_of_int` is gated |
| local definition shadows | a module's own `pid_of_int` is not the builtin |
| stdlib module allowed | a module whose spans carry a file in `stdlib_source_files` passes |
| stdlib-looking path is not stdlib | `stdlib/g3_fixture.march` outside the set is user code |
| REPL is user code | `check_module_with_env` runs the gate |
| lands with an empty table | `stdlib_only = []`, and user code may call `pid_of_int` |

Perturbations, each RED on exactly the intended cases: dropping the stdlib
exemption failed "stdlib module allowed"; dropping the shadowing guard failed
"local definition shadows"; removing the REPL call failed "REPL is user
code".

`forge search` is not affected: it reads the builtin tables through
`lib/search`, which does not consult the gate. The gate is at the reference.

## Not done

- A file that is neither the user's nor in `stdlib_source_files` (none is
  known today) would be gated, and its diagnostics hidden by the driver's
  filter. When the set is first populated, check that every entry point that
  typechecks the stdlib (driver, LSP, forge) sets `stdlib_source_files`; with
  it empty, the stdlib's own calls would be rejected.
