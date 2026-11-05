`[P3]` Use proved preconditions to drop the compiler's own runtime checks

Filed 2026-11-05. Not started; this records the design so the first slice can
start from it.

## What

Refinements are already erased: a refined type compiles to its base type and
neither backend inserts a predicate check (`specs/lang/refinement-types.md`,
golden `g46_refinement_erasure`). The checks that remain are the compiler's
own safety checks, and the refinement checker often proves them dead:

| Check | Emitted as today | Proof that removes it |
|---|---|---|
| `/` `%` by zero | a call to `march_checked_div_op` / `march_checked_mod_op` (`lib/tir/llvm_emit_arith.ml`) | divisor != 0; `Division_safety` already proves it, but only reports under `cap no_panic` |
| `+ - *` overflow | `llvm.*.with.overflow` + panic branch (`Llvm_ctx.emit_checked_int_op`) | result in 63 bits; `Overflow_safety`, also `cap no_panic` only |
| array / Bytes / SIMD bounds | inside the runtime getters (`runtime/march_runtime.c`, `native_*_arr_get`) | the call's `0 <= i < length` precondition, already in the per-call-site verdict index |
| partial stdlib fns (`head`, `unwrap`, `at`) | a `panic` in the March body | the call site's precondition discharged |

## Design

1. **Verdicts to codegen.** The checker keys verdicts by AST span
   (`Panic_surface_by_proof` reads the index after `Refine_check.check_module`,
   `bin/main.ml`); TIR's `EApp` and arithmetic carry no span. Rewrite proved
   sites at lowering, while the AST span is still in hand: a proved `/` becomes
   an `int_div_unchecked` builtin, a proved `NativeArray.get` a `get_unchecked`
   one. That survives every later pass unchanged. (Threading spans through TIR
   is the alternative; rejected as invasive: every pass that rebuilds a call
   would have to carry them.)
2. **Only a solver proof counts.** Skipped, solver missing, unknown/timeout,
   `@[trusted]`, assumed lemmas, foreign results checked at the boundary and a
   verdict replayed from the warm VC cache all keep the check.
3. **Determinism (the real design problem).** Today a timeout loses a proof;
   here it would change the binary. Same source must give the same `.ll` on a
   loaded machine and from the CAS. Needs a deterministic solver budget (z3
   `rlimit`, not wall-clock), the elision decisions in the CAS key, and
   `scripts/determinism-oracle.sh` green with elision on.
4. **Interpreter unchanged.** It keeps every check; a proved check never fires,
   so interp/compiled parity holds.
5. **Overflow soundness.** The checker models `Int` as unbounded *because*
   overflow panics (`Int is mathematical` in refinement-types.md). Drop an
   overflow check only where that very operation was proved in range, never on
   the strength of any other fact.

## Slices, in order

1. Division only: lowering rewrite + deterministic budget + a flag to turn it
   off (`pass_switch`). Benchmark a division-heavy loop compiled at `--opt 2`
   before and after. Cheaper alternative to measure first: just inline
   `march_checked_div_op`.
2. NativeArray bounds, measured on `bench/simd_kernels.march`; bounds checks in
   index loops block vectorisation (see
   `2026-08-11-march-index-loop-per-iteration-overhead.md`).
3. Overflow, last.

## Done when

- Each slice: an `--emit-llvm` test showing the unchecked form at a proved site
  and the checked form at an unproved one (and at one proved only by
  `@[trusted]`).
- `ir-oracle` diffs only at proved sites; `determinism-oracle` green.
- A benchmark number for each slice; a slice with no measurable win is not
  shipped.
