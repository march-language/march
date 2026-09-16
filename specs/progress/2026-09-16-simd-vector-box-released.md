# A SIMD vector crossing a `ptr` parameter slot is released

**Landed 2026-09-16.** Closes
`specs/todos/2026-08-12-simd-nontco-vector-param-leak.md` and §5 of
`specs/2026-09-11-codegen-leaks-design.md` — the last section of that design.

## The leak

A vector value lives in a register, but a parameter slot that is not a native
TCO vector slot is `ptr`, so the call site boxes the argument
(`march_simd_alloc`, 32 bytes). Nobody released that box for a callee outside
`ctx.native_vec_params`: one leaked cell per call to any non-tail-recursive
function or closure with a vector parameter. Measured on `main` a0ec3287a,
Darwin arm64, `--compile --opt 2`: 20,002 objects over 20,000 calls, on each of
two shapes.

## Root cause, and why it is not what the design predicted

The design (§5) chose option A — materialise the box as a TIR binding — and
rejected option B (a callee-side release) because "the read-only (borrowed)
shape is the one that leaks". Measured against the tree as it is now, that is
no longer true, and the reason is instructive: **every SIMD builtin was
classified OWNED**. `Simd.sum_f32x4(v)` therefore counted as consuming `v`, so
a function that merely reads its vector parameter owned it, and the TIR was
internally consistent — `inc_rc v; sum(v)`, transfer to the recursive call — while
nothing at runtime ever released the box, because the builtins lower to LLVM
vector instructions, not to a C call that frees anything.

So the fix is ownership accounting after all, but one layer earlier than either
option:

1. **`lib/tir/borrow.ml`: SIMD builtins borrow their operands.** Matched by
   name (`simd_`), because the grid is 127 names across five lane types and a
   list would rot. `_load`/`_store` are excluded: their first parameter is a
   NativeArray, and that array's ownership is the array builtins' story —
   classifying it borrowed moved a live array's release to its last syntactic
   use and broke `simd_vector_mem`, `simd_vector_core` and
   `native_arr_map_inline_vectorize`.
2. **`lib/tir/llvm_emit_call.ml`: the call site releases a box it made for a
   BORROWED parameter.** Same question `ctx.native_vec_params` answers for one
   shape, asked of every shape, through the per-parameter borrow modes
   `Clo_flags` already carries to the emitter. An owned parameter — the
   escaping `fn wrap(v) = [v]` — keeps its box, as it must.

Together these fix both shapes by opposite halves: a read-only callee's
parameter is borrowed so the CALL SITE releases; a closure's apply fn owns
every parameter (the closure ABI), so the CALLEE releases at last use.

## Found while measuring, filed not fixed

A vector stored into a list leaks its box when the list dies — the third leg of
the probe, 60,000 objects over 20,000 iterations, identical before and after
this change. The `Cons` cell owns the box and never releases it:
`specs/todos/2026-09-16-simd-box-in-an-aggregate-field-is-never-released.md`.

## Verification

- `test/native/simd_nontco_leak_probe.march`: a non-tail-recursive callee and a
  closure, each flat over 20,000 calls (RED before: 20,002 each), plus the
  escaping leg as a crash witness — it prints its length, so an over-eager
  release shows up as a wrong number rather than as a leak.
- Kept green: `simd_vector_escape_arg` (the 2,000,000-call double-free guard),
  `simd_vector_core`, `simd_vector_mem`, `simd_mutual_tco`,
  `simd_nested_closure_acc`, `simd_actor_msg`, `simd_fma_fuzz`, `simd_poly_eq`,
  `simd_to_string`, `native_arr_map_inline_vectorize`.
- ASAN (linux/arm64 container, the gate that now sweeps the two-node scenarios):
  81/81 clean, plus the six SIMD fixtures three runs each.
