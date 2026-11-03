# Int `+ - *` and negation panic on overflow (all three backends)

Road to 1.0, Phase 2, the first base change (`specs/plans/2026-09-28-road-to-1.0.md`).
Decided 2026-09-29: trap at run time rather than model overflow in every VC.

**Why.** Compiled Int is 63-bit and wrapped (bed09ee0a made that normative), while the
refinement checker models unbounded integers, so `x + 1 > x` "proved" and a wrapped
negative sum could satisfy a bounds contract. With the trap every `+ - *` a program
reaches is the unbounded result, so the checker's model is sound for code that runs.
`cap no_panic` code proving it never takes the trap is the follow-up
(`specs/todos/2026-10-30-no-panic-int-overflow-obligations.md`).

## Semantics

`a + b`, `a - b`, `a * b` and `-a` on `Int` panic when the result leaves
[-2^62, 2^62), with `attempt to add|subtract|multiply|negate with overflow`, the same
text in the interpreter, compiled code and `--target js` (the parity tests compare the
caught message). `int_wrapping_add` / `int_wrapping_sub` / `int_wrapping_mul` are the
explicit modulo-2^63 forms. Unchanged (still wrap): `/` (only `-2^62 / -1`), `int_div`,
`int_abs`, `int_pow`, `int_shl`, `NativeArray.sum_int` and the fused map-sum loop.
`specs/lang/type-system.md` "Int width and overflow" rewritten; `docs/types.md`
regenerated.

## Implementation

- **Compiled** (`Llvm_ctx.emit_checked_int_op`): both operands are read normalised, one
  is pre-shifted left by one bit (both, for `+`/`-`), and
  `llvm.{sadd,ssub,smul}.with.overflow.i64` decides it: `2a + 2b` overflows i64 exactly
  when `a + b` leaves 63 bits (the tagged-Int trick). The result is the exact `ashr 1`,
  so it is always normalised. The overflow edge branches to a block calling
  `march_int_overflow(op, file, line)` (`cold noreturn`, `runtime/march_runtime.c`),
  which records the enclosing function's source site as the panic site, the way
  `march_panic_site` records a `panic` call, then panics. TIR has no expression spans,
  so the site is the function's definition line (`Provenance.effective_span`).
  Negation is `ssub(0, 2a)`. The wrapping builtins are dedicated `Builtin_name` arms:
  a bare `add/sub/mul`, normalised lazily at the first observation, which is what
  `+ - *` did before.
- **Interpreter** (`Eval_runtime.int_add/sub/mul/neg`): the host-overflow tests that
  already existed for the 32-bit browser REPL now run on every host; OCaml's native
  `int` is March's 63-bit Int, so the host test is the March test. `int_abs` and
  `int_pow` moved to the wrapping helpers so they keep wrapping.
- **JS** (`js_emit`, `march_int_ovf` in `runtime/march_runtime.mjs`): an Int-typed
  `+ - *` / negation is emitted as `march_int_ovf(a OP b, code)`, which range-checks
  the double result against ±2^62. Exact within the target's documented ±(2^53 - 1)
  subset (where nothing can overflow) and at power-of-two boundaries; near ±2^62 the
  double is already rounded, as the reference says.
- **Constant folding** (`Fold.fold_int_op`) leaves an overflowing literal `+ - *`
  unfolded, so it panics at run time instead of being wrapped at compile time.
- **Simplifier**: the `x * 2 -> x + x` strength reduction is gone; `*` and `+` now
  panic with different messages and the interpreter reports the multiply. LLVM
  strength-reduces the checked multiply itself.

## Code that relied on wrapping

- Derived `Hash` (`lib/desugar/desugar_derive.ml`) combined field hashes with
  `acc * 31 + hash(f)`; field hashes are arbitrary Ints, so it now uses
  `int_wrapping_mul`/`int_wrapping_add` (same values).
- The five SIMD vector `Hash` impls (`stdlib/simd.march`), same change.
- `Msgpack.from_int64`: an int64 outside 63 bits documentedly wraps; the top-byte term
  now uses the wrapping ops.
- `bench/native_array_chains.march`'s `int_map3_heavy` case squares values near 10^13
  (the checksum depends on the wrapped result); its later links use the wrapping ops,
  same checksum. The bench gate (all 53 benches compiled) is green.
- The stdlib's other hashes and RNGs were already overflow-free by construction:
  `Random` (32-bit sfc32 core, every product masked), `DataFrame`'s FNV/djb2 (masked to
  31 bits each step), HAMT/Map/Set slots (shifts and masks), and the C-side string/int
  hashes and `iolist_hash_fnv1a` (C arithmetic, unaffected).
- Tests that pinned wrapping (`test_compiled_int_overflow_parity`,
  `test_compiled_int_overflow_lazy_norm_parity`, the REPL-JIT
  `test_orc_lazy_int_normalisation`) now spell the wrap `int_wrapping_*`, with the same
  expected output.

## Tests

- `test_compiled_int_overflow_trap_parity` (`test/test_codegen.ml`): every boundary of
  `+ - *` and negation, each caught with `__try_call_val`, with its in-range neighbour,
  plus an overflowing literal sum (the folder), `x * 2` (the simplifier), `+` as a
  first-class fold argument, and the three wrapping builtins; compiled must equal the
  interpreter's lines.
- `test_int_overflow_uncaught_panic`: an uncaught add / multiply / negate overflow ends
  the program with its message and exit 1 in the interpreter, compiled code
  (`panic: ...`) and node.
- Every `test/native`, `test/whole_program` and `examples` program (457) run under the
  interpreter: none hits an overflow.
- Red before: on main the trap-parity case prints the wrapped values (for example
  `-4611686018427387904` for `mx + one`) and the uncaught case prints `after`.

## Cost (compiled, `--opt 2`, same box, before vs after)

`bench/index_loop.march` is new (a counted arithmetic loop and an indexed NativeArray
read loop) and is registered in `test/test_bench_gate.ml`. Measured 2026-10-30 on the
dev Mac (arm64, 14 cores): the base binaries were built from this branch's parent
commit before any change, the new ones from this branch, and the two were run
interleaved, 15 rounds each, wall clock per run. The box was shared with other
sessions (load average 32 to 47 during the run), so the minimum is the number to
read; medians are noisy.

| bench | base min / median (ms) | trap min / median (ms) | min delta |
|---|---|---|---|
| `bench/fib.march` (fib 40) | 420 / 645 | 499 / 669 | +19% |
| `bench/index_loop.march` | 651 / 994 | 690 / 1026 | +6% |
| `bench/list_ops.march` | 42 / 59 | 41 / 70 | none measurable |

fib pays the most: `fib(n-1) + fib(n-2)` is now an overflow-checked add with a cold
branch, which LLVM's accumulator tail-recursion elimination no longer turns into a
loop (the reason the lazy-normalisation scheme returned the add bare,
`specs/progress/2026-10-02-lazy-int63-normalisation.md`). Loop-carried index
arithmetic costs a few percent; list_ops is allocation-bound. These numbers size the
cost, they do not decide whether to ship; the perf A/B runner built in parallel is
meant to re-measure on a quiet box.
