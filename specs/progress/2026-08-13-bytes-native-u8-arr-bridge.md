# Bytes <-> NativeU8Arr bridge for SIMD byte scanning

**Filed and closed:** 2026-08-13 (Task 1 of the SIMD follow-ups plan,
`.superpowers/sdd/2026-08-13-simd-followups/`).

## Problem

`Simd.load_u8x16`/`eq_u8x16`/`first_set_u8x16` — the codebase's best
measured SIMD win (11.5x on a byte scan) — had no way to receive real byte
data. `Bytes` (files, sockets, `Bytes.from_hex`, etc.) and `NativeU8Arr`
(what the SIMD ops load from) are two different, non-aliasable heap
layouts, and nothing converted between them.

## Fix

Two new C functions in `runtime/march_extras.c` (kept there, not
`march_runtime.c`, because `bytes_wrap` — needed by the outbound
direction — is `static` to that file):

- `bytes_to_u8_arr(void *b)`: copies a `Bytes`' `march_string` payload
  (data at +24) into a freshly allocated `NativeU8Arr` (data at +32,
  16-byte aligned, `elem_kind` byte) via `native_u8_arr_alloc_raw` + one
  `memcpy`.
- `u8_arr_to_bytes(void *arr)`: the inverse — `march_string_alloc` + one
  `memcpy`, wrapped through `bytes_wrap` (never hand-rolled, per the prior
  `Bytes.concat` miscompile this exact shortcut caused).

`NATIVE_ARR_HDR`/`NATIVE_ELEM_*` and a declaration for the existing
non-static `native_u8_arr_alloc_raw` moved from a `march_runtime.c`-local
`#define`/static scope into `runtime/march_runtime.h`, so `march_extras.c`
can share them (matching the existing `march_string_alloc` pattern) instead
of a second `#define` copy.

Registered as builtins `bytes_to_u8_arr : Bytes -> NativeU8Arr` and
`u8_arr_to_bytes : NativeU8Arr -> Bytes` across all six sites (typecheck
signature, eval impl, `defun.ml` `builtin_names`, `llvm_builtins.ml` table
row + `PDeclare`, `test_codegen.ml` golden preamble) — pure data movement,
deliberately kept out of the capability table. Stdlib wrappers
`Bytes.to_u8_arr`/`Bytes.from_u8_arr` added to `stdlib/bytes.march` and
mirrored to `share/march/bytes.march`.

New compiled/interpreted parity fixture `test/native/bytes_u8_bridge.march`
covers round-trip identity, the empty-Bytes case, high bytes (0x80-0xFF
zero-extend to 128-255, never negative), and the motivating end-to-end
case: `Bytes.from_string("key=value") -> to_u8_arr -> Simd.load_u8x16 ->
eq_u8x16(splat('=')) -> first_set_u8x16` finds the delimiter at index 3.

## Verification

`scripts/run-tests.sh` and `dune build --root . @test/runtest` both exit 0
against the full tree, including the new `bytes_u8_bridge` compile-run-diff
rule in `test/dune` (modelled on `simd_vector_core`'s). See
`.superpowers/sdd/2026-08-13-simd-followups/task-1-report.md` for the full
file-by-file change list and six-place registration cross-check.
