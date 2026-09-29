# A linear `send` lowers to `march_send`; the four unlinked declares are gone (fixed 2026-09-28)

**Resolution: the second option in the report.** Until the per-process arena
runtime ships, a linear send is lowered to `march_send`.

- `lib/tir/llvm_emit.ml`: the `EApp` arm that emitted
  `@march_send_linear` for a message var with `v_lin = Lin` is removed, so a
  linear send takes the ordinary `send` path. A comment at that spot records
  why, and says a dedicated arm should return only together with linking
  `march_message.c` / `march_heap.c`.
- `lib/tir/llvm_builtins.ml`: removed the `send_linear` builtin row, the
  `march_msg_copy` / `march_msg_move` / `march_process_alloc` declare rows,
  and their four `PDeclare` preamble entries.
- `test/test_builtin_compiled_lowering.ml`: `defined_only_in_unit_test_runtime`
  is now `[]`. Its comment says the list must stay empty, and the existing
  cross-check still compares it against what the preamble declares.
- `test/test_codegen.ml`: the golden native actor preamble drops the four
  declares.
- Docs: `specs/lang/linear-types.md` (with `docs/linear-types.md`
  regenerated) and `specs/features/runtime.md` no longer claim that a linear
  send compiles to a zero-copy move.

**RED/GREEN.** No surface program is known to reach the arm. Both
`linear let m = Inc(5); send(p, m)` and a `linear m : Counter.Msg`
parameter compiled to `march_send` on origin/main (14ec3b71f), and they
compile and run (`n = 5`) after the change too. So the arm is pinned on
hand-built TIR: `test_llvm_linear_send_lowers_to_march_send` ("llvm_emit
correctness" group in `test/test_codegen.ml`) emits a function whose body is
`send(p, m)` with `m` linear.
- On origin/main it FAILED: the IR called `@march_send_linear`.
- It now calls `@march_send`, and the IR mentions none of the four symbols.

---

Original report:

# `march_send_linear` is emitted by codegen but never linked

Filed 2026-09-26 from `specs/progress/2026-09-26-same-named-builtin-abi-audit.md`.

`lib/tir/llvm_emit.ml` lowers a `send` to `call @march_send_linear` when the
message atom's variable is linear (`v_lin = Lin`). The native preamble also
declares `march_msg_copy`, `march_msg_move` and `march_process_alloc`. All
four are defined only in `runtime/march_message.c` / `runtime/march_heap.c`,
which `runtime/sources.list` marks `unit-test-only` and the driver never links.
A program that reaches that emit arm fails at link time with
`Undefined symbols: _march_send_linear`.

The path looks latent today. `let (m, _k) = (Increment(5), 1); send(c, m)`
binds `m` as `Lin` at lowering, yet it still compiled to `march_send`, measured
2026-09-26. Nobody has shown that no program reaches it.

`test/test_builtin_compiled_lowering.ml` pins the four names in
`defined_only_in_unit_test_runtime`. Resolve it one of two ways:

- Link the per-process arena runtime by default.
- Lower a linear send to `march_send` until the arena runtime ships, and drop
  the four declares from the native preamble.

Then empty that list.
