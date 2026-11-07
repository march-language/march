# Int `/` and `%`: the zero-divisor check inline (2026-11-06)

Slice 1 of `specs/todos/2026-11-05-proved-preconditions-drop-runtime-checks.md`, done as the
todo's "cheaper alternative to measure first". The proof-based rewrite for division was
measured and not built.

## What changed

- `Llvm_ctx.emit_checked_divmod` (`lib/tir/llvm_ctx.ml`): an Int `/` or `%` is now
  `icmp eq b, 0` → a cold block that calls `march_checked_div_op(a, 0)` /
  `march_checked_mod_op(a, 0)` and is `unreachable`, otherwise `sdiv` / `srem`. Before, every
  `/` and `%` was an opaque call to those helpers.
- The panic message is unchanged: the cold block calls the same helper with a zero divisor,
  and `march_panic` does not return.
- The emitter in `lib/tir/llvm_emit_arith.ml` still draws the `ar` temp it used to name the
  call's result, so functions with `+ - *` and no division keep their temp numbering.
- `bench/int_divmod.march`, registered in `test/test_bench_gate.ml`.

## Rulings

1. **The proof-based division rewrite is not shipped.** The todo's design (rewrite a proved
   `/` at lowering into an unchecked builtin, a deterministic solver budget, the elision
   decisions in the CAS key) was measured against the inline check first:

   | Build (`--opt 2`, minimum user time) | int_divmod |
   |---|---|
   | main: opaque call | 0.57-0.60 s |
   | inline test | 0.32-0.34 s |
   | no test at all (unsound, measurement only) | 0.32 s |

   With the test inline, LLVM folds it for a literal divisor and drops it where a dominating
   branch already tested the divisor (`gcd`'s `b == 0`). The inline build of the benchmark
   has 2 trap call sites left in the binary, and removing those gains nothing. The todo's
   rule is that a slice with no measurable win is not shipped. The design's determinism
   problem never arises for division.
2. **No pass switch.** The design's switch was for the proof rewrite, whose output depends on
   the solver. The inline test depends on nothing but the operator, like the overflow check.
3. **`sdiv` sees normalised operands.** Int is 63-bit, so `INT64_MIN / -1` cannot occur. The
   `-2^62 / -1` quotient is the bare `2^62`, normalised lazily as before (the parity test
   pins `-4611686018427387904`).

## Verification

| Check | Result |
|---|---|
| New: compiled-vs-interpreter parity for `/` and `%` (signs, zero divisor from a NativeIntArr and as a literal, `-2^62 / -1`, a literal divisor), caught with `__try_call_val` | passes; also passes on main (it pins behaviour) |
| New: IR test (`sdiv` / `srem` behind `icmp eq … 0`, the helper only in the trap block) | RED on main, passes here |
| `run_compiler`, `run_codegen`, `run_eval`, `run_stdlib`, `test_jit` (full) | all pass |
| ir-oracle vs main `01cae3ed2` | 106 of 520 programs changed. They are exactly the programs whose IR has an Int `/` or `%`. Every one is identical to main's after rewriting the inline sequence back into the call and renumbering temps and labels; the one left after that (`bench_native_array_chains`) differs only in the result's name prefix (`%ar` → `%dv`) |
| Benchmarks, minimum user time of 7 interleaved runs, `--opt 2`, load average about 20 | int_divmod 0.56 → 0.31 s; index_loop 0.64 → 0.49 s; hash_map_bench 0.67 → 0.65 s; rrb_bench 12.83 → 12.43 s; array_sort, native_array_chains, ring_buf, simd_kernels, simd_sum, merkle, json_stream, list_ops and the sorts unchanged. Every output identical with printed timings masked |

## For slice 2

Array, `Bytes` and SIMD getters are also opaque runtime calls (`native_*_arr_get`) with the
bounds test inside. Measure the same cheap alternative there first: the bounds test inline
may again be most of the win, with a proof needed only where a test left in a loop blocks
vectorisation.
