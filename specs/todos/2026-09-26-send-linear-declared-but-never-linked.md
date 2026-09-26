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
