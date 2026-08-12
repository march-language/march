# Hand-written March index loops carry ~4 calls + a volatile load per iteration

Filed 2026-08-11 during Task 4b of the SIMD vector types plan
(`.superpowers/sdd/2026-08-10-simd-vector-types/`), after fixing the
vector-accumulator boxing that was masking this.

## Symptom

`bench/simd_kernels.march`'s `dot_simd` bar — "an explicit `Simd` dot product
should beat `dot_composed`, which materializes a useless 20MB intermediate
array" — is still unmet after the boxing fix:

| dot(5M f32)  | ms   |
|--------------|------|
| dot_simd     | 10.01 |
| dot_composed | 2.55 |

This is NOT a SIMD problem. An attribution probe that holds the loop framework
constant (same preempt check, same bounds checks, same RC ops) and varies only
the width shows the vector lowering working exactly as intended:

| 5M f32 dot, same March loop framework | ms    |
|---------------------------------------|-------|
| SIMD index loop (4 lanes/iter)         | 9.89  |
| scalar index loop (1 elem/iter)        | 39.95 |
| `map2_f32` + `sum_f32` (one C call)    | 2.34  |

SIMD is **4.0x** faster than scalar within March-loop-land. The gap to the C
path is the loop framework itself, and it applies to *every* hand-written
March index loop over a NativeArray, not just SIMD ones.

## What the loop actually emits

From `--emit-llvm` on `dot_loop` (a top-level self-tail-recursive `pfn`, so
already TCO'd into a loop with native accumulator slots):

- `load volatile i64, ptr @march_preempt_request` + branch — per iteration.
  Volatile blocks unrolling and vectorization of the surrounding loop.
- `call ptr @llvm.stacksave()` / `call void @llvm.stackrestore(...)` — per
  iteration.
- `call void @march_incrc_local(ptr %a)` and the same for `%b` — two real
  calls per iteration, on array parameters that are only ever read.
- `call i64 @native_f32_arr_length(ptr %a)` and the same for `%b` — two more
  real calls per iteration, for the SIMD load bounds check, on arrays whose
  length is loop-invariant.
- `%va.addr`/`%vb.addr`/`%$t...addr` allocas emitted **inside** the loop body
  rather than the entry block, so `mem2reg` does not promote them and every
  intermediate round-trips through memory.

That is ~4 function calls and a volatile load per 4 elements of useful work.

## Candidate directions (unmeasured — do not assume any of these wins)

1. **Hoist loop-invariant bounds-check length calls.** `native_f32_arr_length`
   on a parameter never reassigned in the loop is trivially invariant; LLVM
   cannot hoist it because it is an opaque call. Marking these runtime
   accessors `readnone`/`speculatable` (or emitting the length once into the
   TCO prologue) is probably the single cheapest win.
2. **Elide `march_incrc_local` on borrowed params inside TCO loops.** The
   borrow inference (`lib/tir/borrow.ml`) already has the notion; the RC ops
   here look like they survive because the value is forwarded into the next
   iteration's slot.
3. **Emit body allocas in the entry block** when they are not genuinely
   dynamic, so `mem2reg` can promote them and `stacksave`/`stackrestore` can
   be dropped for loops with no dynamic alloca.
4. **Preemption check throttling** — CAUTION: an in-TLS-counter throttle was
   already tried and measured **+65% WORSE** (see
   `project_fib_throttle_counter_rejected` in repo memory). Do not rebuild
   that specific design. In-register (BEAM-style) reduction counting is the
   remaining untried lever.

## Why it wasn't fixed in Task 4b

Task 4b's mandate was explicitly scoped to the vector-ABI gap (closure
kickoff/self-call agreement, and native TCO slots for vector accumulators).
All four directions above are general codegen changes touching every compiled
March loop, with a correspondingly large blast radius and their own benchmark
matrix — a separate piece of work, not a rider on a SIMD fix.

## Note on the bar itself

`dot_simd` vs `dot_composed` compares a March-level loop against a single call
into a C runtime pipeline, so it is as much a test of March's loop codegen as
of SIMD. If the loop overhead above is fixed, re-run
`bench/simd_kernels.march` and update `bench/RESULTS.md`'s simd-kernels
section; the same fix would also re-open the DataFrame Min/Max migration
question (currently at ~8.2x slower than the C reduction, down from ~35x —
see the "DataFrame Min/Max: not migrated" section there).
