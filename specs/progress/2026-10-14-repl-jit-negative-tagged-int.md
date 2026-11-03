# JIT REPL printed negative Ints in tagged slots as max_int garbage (2026-10-14)

Found by the new doctest check: in `march repl` (the JIT path),
`NativeArray.to_list_i32(NativeArray.from_list_i32([3, -1, 2]))` printed
`[3, 9223372036854775807, 2]`, and `sort_i32` of the same list
`[9223372036854775807, 2, 3]`. Interpreted and `--compile` both print the right list.

**Root cause.** Not the narrow arrays at all. `[-1]`, `Some(-1)` and `(-1, 2)` printed
the same garbage at the JIT prompt, while a bare `-1` and `get_i32` (an unboxed result)
printed correctly. The REPL value printer, `pp_word` in `lib/jit/repl_jit.ml`, untagged a
low-bit-tagged scalar word `(v<<1)|1` with `Int64.shift_right_logical`, so any negative
`v` lost its sign: `-1` (all ones) became `0x7FFF_FFFF_FFFF_FFFF`. The same logical shift
was in the erased (`TVar`) slot branch. The runtime's `DEF_NARROW_INT_ARR` helpers
(`runtime/march_runtime.c`) widen/tag correctly and were left unchanged.

**Fix.** Both untag sites now use the arithmetic `Int64.shift_right`.

**Regression test.** `test/test_jit.ml`, `repl_session` "negative Ints in
List/Option/tuple slots print" (JIT, plus an interpreter parity control): negative i32
values through `from_list_i32`/`to_list_i32`/`sort_i32`/`get_i32`/`make_i32`, u8
wrapping, and negative Ints in `Option`, a tuple and a nested list. Verified RED with the
logical shift restored.
