# `unix_time_ms` / `unix_time` typecheck but have no codegen backing

Filed 2026-08-21. Found while writing `test/test_socket_timeout.ml`, which
wanted to measure elapsed time inside a compiled March probe.

## Symptom

A program that calls `unix_time_ms()` typechecks cleanly, compiles to LLVM IR,
and then fails at link time:

```
Undefined symbols for architecture arm64:
  "_unix_time_ms", referenced from:
      _probe_recv_timeout in march_socket_timeout_564-e5aec1.o
```

The builtin is registered in `lib/typecheck/typecheck.ml` (type
`() -> Int`, capability `IO.Clock`) but has no entry in
`lib/tir/llvm_builtins.ml` and no `march_*` symbol in the C runtime, so the
compiled backend emits a call to a symbol nobody defines. It works interpreted.

The same appears to apply to `unix_time` (`() -> Float`) — both are registered
side by side at `typecheck.ml:2512-2513` — though only `unix_time_ms` was
observed failing.

## Why it matters

The failure lands at **link** time, not compile time, with a C-level symbol
name and no March span. Nothing tells the author that the builtin they used is
interpreter-only, and nothing in the stdlib docs marks it as such.

## Fix

Either give it codegen backing (a `march_unix_time_ms` runtime symbol plus the
`llvm_builtins.ml` entry and `PDeclare`, following any `IO.Clock` sibling that
already links), or reject it at typecheck time under `--compile` with a real
diagnostic. The first is preferable — a clock is not an unreasonable thing to
want in a compiled program.

Worth auditing the whole builtin table for other entries that typecheck but do
not link: the two tables are maintained by hand and nothing cross-checks them.
That audit is the more valuable half of this item.
