`Lsit.length([1,2])` (a misspelled module whose member names a builtin) passed `march --check` and
failed only at run time with "unbound variable: Lsit.length". `Lsit.nope(...)` was already rejected.

Cause: the last-resort dot-suffix fallback in the `EVar` case of `infer_expr`
(`lib/typecheck/typecheck.ml`), which exists for multi-component paths such as
`Conduit.Storage.workflow_load`, stripped `Lsit.` and resolved the bare builtin `length`.

Fix: a single-qualifier `Q.member` whose `Q` is not a registry module, not a type (`env.types`,
records, aliases), not an in-file module with private members, and the prefix of no binding in
scope skips the fallback and reports
"Unknown module `Lsit`. Did you mean `List`?". A dotted name that fails to resolve now carries
`unknown_qualified_name` instead of `unbound_variable`.

Regression: `test/errors/unknown_qualified_name_5.march`.

A first version skipped the fallback for type qualifiers too, and CI's `provenance` test caught it
rejecting `Int.to_string(n)`. Type-qualified names keep the old behaviour. They check, but fail at
run time; that is pre-existing and filed as
`specs/todos/2026-11-03-type-qualified-name-checks-but-fails-at-runtime.md`.

The survey also reported the run-time stack trace naming the wrong line; that was a misreading:
frames are call sites by design (see the plan's §X9).
