`[P3]` cap-check coverage exempts `random_bytes` across the whole stdlib

Filed 2026-11-19 from the ocap phase 4 PR B fix-wave re-review.

`test/test_cap_check_coverage.ml` (around lines 160-162) reuses
`Io_ops_gen.shadowed_by_stdlib`, so a bare `random_bytes` call is exempt from the audit in
every stdlib file, not only inside `stdlib/crypto.march`. No other stdlib file calls it
today, but a future unchecked raw call would pass. The `Io_ops_gen` doc comment also still
gives the rationale "a user's call resolves to the stdlib fn", which is false: the raw
builtin is stdlib-only since PR B.

Also: the REPL-JIT typecheck path (`check_module_with_env` in
`lib/typecheck/typecheck.ml`) does not go through `check_module_core`, so it resets
neither `Json_dispatch` nor `stdlib_only_call_spans`; the comment saying a REPL fragment
is covered holds only for the interpreter REPL.

Done when the exemption is scoped to `crypto.march`, the doc comment is corrected, and
the REPL-JIT path resets the span table.
