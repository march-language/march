# DONE NativeArray map / map2 chain fusion (phase B)

Done 2026-10-04. Phase B of `specs/plans/2026-09-28-nativearray-fusion-plan.md`
(its "Phase 1: map / map2 composition"). The open todo
`specs/todos/2026-09-28-nativearray-fusion.md` stays open for phases C–E.

## The change

- `lib/tir/fusion.ml`, new section `run_nativearr` (the list patterns are
  untouched). After Mono, before Defun, it rewrites
  - `map(map(a, f), g)` → `map(a, f;g)`
  - `map2(map(a, f), b, g)` and `map2(a, map(b, f), g)` → `map2(a, b, …)`
  - `map(map2(a, b, f), g)` → `map2(a, b, …)`

  by **substituting** the two lambda bodies (`Inline.alpha_rename` /
  `Inline.subst_args`) into one fresh `ELetRec([fd], EAtom fv)` lambda, applied to
  a fixed point per let chain so longer chains collapse. The wrappers are found by
  name (`NativeArray.map_<w>` / `map2_<w>`, through `Fusion.base_name`) **and** by
  their body being exactly the `native_<w>_arr_map(2)` call.
- How a chain is analysed: the enclosing let/seq spine is flattened (a let RHS's
  own leading lets float out when no name they bind is mentioned later), fusion
  runs on the flat list, and the result is rebuilt with every lambda whose only
  use is the next binding moved back into that binding's RHS — the lowering's own
  shape, which `Native_map_inline` needs to see the closure through the alias let
  that inlining the wrapper leaves. If nothing fused, the original expression is
  returned, so programs without an eligible chain get identical TIR.
- Eligibility, all required:
  1. the intermediate array is used exactly once (`Fusion.use_count` over the rest
     of the chain);
  2. both callbacks are `FnLambda` literals bound in the same chain,
     non-recursive, of the wrapper's arity (a parameter, a top-level fn or a
     closure from elsewhere is not fused);
  3. both bodies are pure per `Purity.is_pure_ext` against the module's
     transitively-impure functions (`Purity.impure_fns_of_module`, computed lazily
     once per run), stricter than `Purity.is_pure` alone, which would call any
     user function pure;
  4. every item between the producer and the consumer is pure (closure creation
     counts as pure), so the producer's work never moves across an effect;
  5. no binder between a callback's (or the producer's) binding and the consumer
     reuses a name the callback (or the producer's inputs) mentions;
  6. same width, composed arity at most 2 (no map3), composed depth at most 8
     original links.
- Narrow widths: the intermediate array of a u8 / i32 chain stores the producer's
  result **wrapped**, and the consumer reads the wrapped value, so the composed
  body applies the same wrap between the bodies (`int_and(x, 0xff)`; i32 the
  sign-extending `((x land 0xffffffff) xor 0x80000000) - 0x80000000`), matching
  `Eval_simd.u8_wrap`/`i32_wrap` and the runtime's C casts. f32 is **not** fused:
  the intermediate rounds to binary32 and March has no scalar builtin to do that
  rounding inside the composed body. Without the wrap, the fixture's u8/i32 lines
  change (see perturbation 2).
- `lib/tir/contract_pipeline.ml`: runs right after `Fusion.run`, only with `opt`,
  never for JS; kill switch `MARCH_NO_NATIVEARR_FUSION=1`
  (`nativearr_fusion_env_disabled`). `bin/main.ml`: `nonafuse` CAS tag, so an
  A/B run never reuses the other variant's binary (verified: the `=1` compile
  printed `compiled`, not `(cached)`).
- Fresh names `$nafuse_*` come from a counter `run_nativearr` resets on entry.
  The snapshot harness does not run Fusion, so no snapshot stage was added.

### Narrower than the plan

- A callback that divides (`/`, `%`) does not fuse: `Purity` lists them as impure
  because they trap on zero. The plan assumed `Purity` treated them as pure and
  recommended accepting the panic reordering; with the purity rule as specified,
  the question does not arise. Relaxing it is a decision for phase D.
- Rule 4 (no effect between producer and consumer) is not in the plan. It keeps a
  producer that panics from moving past a `println`.
- f32 chains (above).
- The callback must be bound in the same let chain as the call; one bound in an
  enclosing scope (outside a `case` arm, say) is not fused.

## Verification

- `test/native/nativearr_map_fusion.march` (+ `.expected`, the interpreter's
  output). Positives: Int map∘map non-capturing and capturing, map2 with a mapped
  first and second input, map∘map2, map2 with BOTH inputs mapped, a 3-deep chain
  through named intermediates and a named lambda, a 10-deep chain (the depth cap
  leaves exactly two calls); the same shapes for Float plus a 3-deep chain; u8
  map∘map and map2∘map and i32 map∘map with values that wrap at the intermediate.
  Negatives that must not fuse and must stay correct: intermediate used twice, a
  `println` between producer and consumer, a dividing callback, a callback passed
  as a parameter, impure (printing) callbacks, an f32 chain. Compiled output is
  byte-identical to the interpreter's (`diff` clean, via the dune rule).
- IR shape (`nativearr_map_fusion_llvm_check.out`): main has **21 inline map
  loops, 8 inline map2 loops, 1 runtime map call** with fusion (the two negative
  helper fns are inlined into main by Opt, the runtime call is the
  parameter-callback case). With `MARCH_NO_NATIVEARR_FUSION=1` the same program
  has 47 / 8 / 2. At the fusion stage main has 26 NativeArray map calls instead
  of 53. Every fused chain is ONE inline loop (e.g. the first probe, an Int
  map∘map with a capture: 3 `nmap_pre` mentions = one loop, zero runtime calls).
- Same-binary A/B of `--emit-llvm` with fusion on vs off: byte-identical IR for
  29 of 30 programs (`bench/array_numeric`, `dataframe_bench`, `list_ops`,
  `simd_map`, `simd_map2`, `simd_f32`, `simd_sum`, `binary_trees`, and all 21
  `test/native/native_arr_*.march`); only `bench/native_array_chains.march`
  differs.
- Perturbations, each restored afterwards (file `cmp`-identical to the good copy):
  1. callback-body purity check replaced by `true`: `impure_chain` fused and its
     `f`/`g` lines interleaved (3 lines moved), fixture diff red;
  2. the u8/i32 wrap removed: the three narrow lines changed
     (`1 1 0` → `1 1 1`, `3 250 44` → `3 250 100`, `300001 -1 -1` →
     `300001 -1 -1589934591`);
  3. single-use check replaced by `true`: the "used twice" case fused and the
     compile failed (`use of undefined value '@t'`).

## Benchmark

`bench/native_array_chains.march`, `--compile --opt 2`, the same compiler binary
with and without `MARCH_NO_NATIVEARR_FUSION=1`, 3 interleaved runs of each
binary × 9 rounds, minimum ms, Apple M3 Max, load average ~5–6:

| case | variant | fusion on | fusion off |
|---|---|---:|---:|
| int_map3 | unfused | 1.028 | 5.196 |
| int_map3 | hand-fused | 1.061 | 1.038 |
| int_map3_heavy | unfused | 2.739 | 7.297 |
| int_map3_heavy | hand-fused | 2.770 | 2.776 |
| int_map_map2 | unfused | 0.867 | 3.038 |
| int_map_map2 | hand-fused | 0.834 | 0.854 |
| flt_map3 | unfused | 0.586 | 4.833 |
| flt_map3 | hand-fused | 0.568 | 0.603 |
| flt_map_map2 | unfused | 0.836 | 3.013 |
| flt_map_map2 | hand-fused | 0.823 | 0.907 |

The written-unfused chains now run at the hand-fused speed. The fold/sum cases
are unchanged (no fold or sum fusion here; that is phase C). Both binaries print
the same checksum.
