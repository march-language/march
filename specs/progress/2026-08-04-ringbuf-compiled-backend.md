# RingBuf compiled backend

Status: done (2026-08-04)

## Problem

`stdlib/ring_buf.march` (RingBuf — mutable fixed-capacity circular buffer) was
interpreter-only: the `ring_buf_*` builtins existed solely as `VBuiltin` cases
in `lib/eval/eval.ml`. There was no C runtime symbol and no codegen wiring, so
any program using `RingBuf` compiled with `march --compile` failed to link
(`Undefined symbols: _ring_buf_make …`).

This is one of three items filed under
`specs/todos/2026-08-04-compiled-backend-nativearray-set-int-queue-retain-memory.md`
(RingBuf being the "in-place mutable ring" the steady-state demo wanted); the
other two items are owned by a sibling PR.

## Implementation

Modelled on `NativeArray` (the closest existing mutable-heap codegen builtin),
but RingBuf is generic over its element type and manages element reference
counts, so its element-ownership discipline follows `march_typed_array`.

Sites touched (a codegen builtin needs all of them):

1. **C implementation** — `runtime/march_runtime.c`: `ring_buf_make/push/pop/
   get/peek_oldest/peek_newest/size/cap/clear/to_list`. A RingBuf value is a
   resource cell (`MARCH_RESOURCE_TAG`) whose native pointer is a separately
   `calloc`'d backing store `{cap, head, size, slots[]}` and whose destructor
   (`march_ring_dtor`) decrefs every occupied slot and frees the store when the
   cell's refcount hits 0. Elements are stored as uniform `march_value` words;
   `march_incrc`/`march_decrc` are `IS_HEAP_PTR`-guarded so immediates no-op.
   Ownership: push transfers a reference in (decref on overwrite-when-full),
   pop moves it out (slot cleared, no decref), get/peek/to_list incref the
   aliased-out copy, the destructor decrefs remaining elements. `clear` only
   resets the cursors (matches the interpreter — the array is not zeroed).
2. **Extern declarations** — `lib/tir/llvm_builtins.ml` (`builtins` list), with
   the erased element/return slots typed `ptr` and `pop`/`get`/`peek` returning
   niche `Option(TVar "_")`.
3. **Preamble** — `lib/tir/llvm_builtins.ml` `PDeclare` list (shared by all five
   `llvm_repl` finalizers via `emit_preamble`).
4. **`defun.ml` builtin_names** — so calls stay top-level (no `ECallPtr`).
5. **Borrow table** — `lib/tir/borrow.ml`: the buffer is borrowed by every op
   (mutated in place, never consumed); push's element is owned (transferred).
6. **Generic-param boxing** — `builtin_boxed_generic_params_tbl` in
   `llvm_builtins.ml` plus a reverse-coercion branch in `llvm_emit.ml`. Needed
   because the general builtin call path only coerces ptr→scalar; an inlined
   `push` wrapper handed `ring_buf_push` a **raw** `i64` element, which the
   erased-i64 conditional untag then read back at half value (odd 7 → 3). The
   element slot is now opted into scalar→ptr boxing so Int elements are stored
   tagged `(n<<1)|1`, the erased uniform representation both consumers expect.

## Verification

- `test/native/ring_buf_ops.{march,expected}` + a `test/dune` compile-run-diff
  rule: every op with Int and String elements, wraparound, and the odd-value
  round-trip; compiled `--opt 2` output is byte-identical to the interpreter.
- Preamble golden (`test/test_codegen.ml`) updated for the new declares.
- 500k-iteration loop with dynamically-allocated String elements: flat 2.8 MB
  RSS (no leak), no RC-underflow abort (no double-free).
- ASAN (`MARCH_SANITIZE=1`) could NOT be run: on this machine the sanitizer
  build spins at ~90% CPU even for a trivial hello-world, independent of this
  change.

## Not covered

- JS backend (`lib/tir/js_emit.ml`) — RingBuf remains native + interpreter only.
