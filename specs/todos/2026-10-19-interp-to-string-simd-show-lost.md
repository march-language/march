# `[P3]` Interpreter: `to_string` on a SIMD vector fails when the program imports Json

Filed 2026-10-19 from CI on #1009 (`test (ubuntu-24.04, rest)`).

`march test test/stdlib/test_island_bridges.march` (a module that `import Json`s and
derives Json) runs every stdlib doctest in that program's context. There,
`to_string(Simd.make_i32x4(1, 2, 3, 4))` raises
`Match_failure("Non-exhaustive pattern match: no branch matched the value I32x4[...]")`:
the call does not reach `stdlib/simd.march`'s `impl Show(I32x4)` (it seems to land in a
`to_string`/`show` that pattern-matches on value shapes and has no vector arm). The same
example passes under `march test imports/test_cross_import.march`, in the native REPL and
in the browser REPL. Reproduced locally on macOS arm64.

The Simd doc examples were rewritten to compare with `==` against `Simd.make_*` instead of
printing (stdlib PR #1009), so nothing currently depends on it. To reproduce, put
`march> to_string(Simd.make_i32x4(1, 2, 3, 4))` / `"I32x4[1, 2, 3, 4]"` back in a Simd doc
block and run `march test` on `test/stdlib/test_island_bridges.march`.

Fix: find which `to_string` the call resolves to in that context (`march query`, or the
eval dispatch in `lib/eval/`), and make interface dispatch for the stdlib's `Show` impls
independent of what the program imports.
