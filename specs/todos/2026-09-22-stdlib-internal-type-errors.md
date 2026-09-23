# `[P2]` 98 type errors inside stdlib bodies that the compiler hides

Filed 2026-09-22, surfaced by making `assert_stdlib_file_typechecks_cleanly`
non-vacuous (see `specs/progress/2026-09-22-stdlib-typecheck-helper-vacuous.md`).

`bin/main.ml` typechecks the whole stdlib once (`get_stdlib_tc_env`) and DROPS
the resulting diagnostics — `is_user_file` filters out anything spanned in a
stdlib file. That filter is right for the user's terminal and wrong as a
development policy: it means a stdlib function whose body does not typecheck
ships silently. The function stays callable, because a call site in another
module resolves it through `Module_registry.ensure_loaded`, and
`load_module_into_env` (`lib/typecheck/typecheck_env.ml:1235`) binds every
registry export as `Mono (fresh_var 0)` — an unconstrained type variable that
unifies with anything. So the call typechecks against any argument and any
result. Two observed consequences:

- `System.os()` returns an atom; `string_length(System.os())` typechecks and
  dies at runtime with "string_length: expected string".
- A generic export in that state reaches monomorphization unresolved, which is
  the boxed-vs-niche silent-wrong-value class `lib/modules/stdlib_manifest.ml`
  documents at length.

`test_stdlib_internal_errors_ratchet` (test/test_compiler.ml) pins the current
counts so no NEW one can land. This item is the backlog it pins, by class:

| class | files (errors) | todo |
|---|---|---|
| `Array(a)` annotations vs the `PVec(a)` the Array module returns | rrb_vec (19), aho_corasick (11) | `2026-09-22-stdlib-array-pvec-annotations.md` |
| gzip/zstd builtins return `Result(_, String)`, signatures say `Compress.Error` | compress (19) | `2026-09-22-stdlib-compress-error-type.md` |
| qualified `Csv.CsvRow` does not unify with bare `CsvRow` | csv (12) | `2026-09-22-stdlib-csv-qualified-type-name.md` |
| ~~builtins the interpreter and codegen know but the typechecker does not~~ | ~~system (8), io (3), uuid (2), crypto (1), logger (1)~~ | fixed 2026-09-23: `specs/progress/2026-09-23-builtins-missing-from-the-typechecker.md` |
| undeclared `needs`, unknown constructors, ambiguous ctors, `Pid` arity | node_call (5), session_node (3), actor (2), cluster_node (1) | `2026-09-22-stdlib-distributed-module-errors.md` |
| one-off: `plot.march:714` expects `String`, gets `FileError`; `logger.march:208` expects `Int`, gets `()` | plot (1), logger (1) | this file |

Reproduce any of them with
`march --check stdlib/<file>.march` (the user copy of the file is checked
unfiltered), or run `test_stdlib_internal_errors_ratchet` and read its output.
Note that `list.march`, `map.march` and `array.march` cannot be reproduced that
way — checking one of those standalone loads it a SECOND time as a user module
that shadows the real one, and the resulting errors are an artifact.

Fixing a file means lowering its row in `stdlib_known_internal_errors` in the
same commit; the ratchet fails on a count that is too LOW as well as too high.
