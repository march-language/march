`[P3]` Use proved preconditions to drop the compiler's own runtime checks

Filed 2026-11-05. Slice 1 (division) is done as its cheap alternative; see
"Slice 1, measured" below. Slices 2 and 3 are open.

## What

Refinements are already erased: a refined type compiles to its base type and
neither backend inserts a predicate check (`specs/lang/refinement-types.md`,
golden `g46_refinement_erasure`). The checks that remain are the compiler's
own safety checks, and the refinement checker often proves them dead:

| Check | Emitted as today | Proof that removes it |
|---|---|---|
| `/` `%` by zero | an inline `icmp eq b, 0` to a cold trap, then `sdiv` / `srem` (`Llvm_ctx.emit_checked_divmod`; until 2026-11-06 an opaque call to `march_checked_div_op` / `march_checked_mod_op`) | divisor != 0; `Division_safety` already proves it, but only reports under `cap no_panic`. Measured not worth it: see "Slice 1, measured" |
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

1. ~~Division only~~ — done as the inline test, the proof rewrite measured and
   dropped (below).
2. NativeArray bounds, measured on `bench/simd_kernels.march`; bounds checks in
   index loops block vectorisation (see
   `2026-08-11-march-index-loop-per-iteration-overhead.md`).
3. Overflow, last.

## Slice 1, measured (2026-11-06)

`specs/progress/2026-11-06-inline-int-divmod-check.md` has the numbers. In short, on a
division-heavy loop at `--opt 2` (user time, three loops: a literal divisor, `gcd`, a
loop-invariant divisor):

| Build | Time |
|---|---|
| main: every `/` `%` an opaque call to `march_checked_div_op` | 0.57-0.60 s |
| the zero test inline, then `sdiv` / `srem` | 0.32-0.34 s |
| no zero test at all (unsound, measurement only) | 0.32 s |

Inlining is the whole win: LLVM folds the test for a literal divisor, reuses a dominating
`b == 0` branch (`gcd`), and the tests left are well-predicted branches. The binary with the
test inline has 2 trap call sites left; dropping them changes nothing measurable. So the
proof-based division rewrite (design steps 1-3 for `/`) is **not shipped**, by this todo's own
rule, and the inline test shipped instead. Its determinism problem (step 3) never arises for
division.

What this suggests for slice 2: measure the same cheap alternative first. Array and `Bytes`
getters are also opaque runtime calls (`native_*_arr_get`), so emitting the bounds test inline
may again be most of the win; the proof should be needed only where a remaining in-loop bounds
test blocks vectorisation.

## Done when

- Each slice: an `--emit-llvm` test showing the unchecked form at a proved site
  and the checked form at an unproved one (and at one proved only by
  `@[trusted]`).
- `ir-oracle` diffs only at proved sites; `determinism-oracle` green.
- A benchmark number for each slice; a slice with no measurable win is not
  shipped.
