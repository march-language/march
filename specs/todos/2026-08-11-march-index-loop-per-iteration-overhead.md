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

1. ~~**Hoist loop-invariant bounds-check length calls.**~~ Done 2026-09-29: the
   `native_*_arr_length` declares are `nounwind willreturn speculatable memory(none)`,
   and at `--opt 2` the calls leave the loop (see
   `specs/progress/2026-09-29-native-arr-length-hoisted.md`; `dot_simd` ~12% faster).
2. **Elide `march_incrc_local` on borrowed params inside TCO loops.** The
   borrow inference (`lib/tir/borrow.ml`) already has the notion; the RC ops
   here look like they survive because the value is forwarded into the next
   iteration's slot.
3. ~~**Emit body allocas in the entry block** when they are not genuinely
   dynamic, so `mem2reg` can promote them and `stacksave`/`stackrestore` can
   be dropped for loops with no dynamic alloca.~~ **Tried 2026-10-01: works as
   IR, buys nothing measurable. Not shipped.** See "Direction 3 measured" below.
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

## Direction 3 measured (2026-10-01): hoisting allocas moves no benchmark

Implemented and then discarded. The change: `Llvm_ctx.emit` parks every
constant-size `%x = alloca ...` line in a per-function buffer while a function is open
(`begin_fn_allocas` after the `entry:` header, `end_fn_allocas` before the closing
`}`), splices it in right after `entry:`, and the self-TCO and mutual-TCO prologues stop
emitting `llvm.stacksave` (so `tco_stack_save` / `mutual_tco_stack_save` stay `""` and
the back-edge `stackrestore` is skipped). Every alloca the emitters produce is
constant-size, so all of them qualified. Sites it covered without editing them:
`llvm_case.ml` (arm bindings, result slots), `llvm_calls.ml` (arg arrays, closure envs),
`llvm_data.ml` (stack cells), `llvm_emit.ml` (let slots, task arrays).

**The IR change was real.** `--emit-llvm --opt 2` of `bench/simd_kernels.march`:
204 of 242 allocas were outside the entry block and 6 `llvm.stacksave` calls were
emitted before; after, 0 of 242 and 0 (e.g. `dot_loop` had `%va.addr`, `%res_slot11`,
`%$t41828.addr` in loop blocks). The same check over 16 benchmark programs found 0
non-entry allocas and 0 stacksave calls after the change.

**The speed change was not.** Same box, origin/main compiler vs the patched one,
`--compile --opt 2`, alternating order, 1-min load average 5.3 to 6.0 (slightly above
the <5 target), n = 11 for simd_kernels (self-reported times) and n = 9 for the others
(whole-process wall time):

| bench | base min / med | hoisted min / med |
|---|---|---|
| simd_kernels `dot_simd` | 8.71 / 9.09 ms | 8.71 / 9.00 ms |
| simd_kernels `dot_composed` | 2.14 / 2.30 ms | 2.04 / 2.28 ms |
| simd_kernels `scan_simd` | 7.48 / 7.63 ms | 7.35 / 7.65 ms |
| simd_kernels `scan_scalar` | 79.52 / 84.48 ms | 80.77 / 82.28 ms |
| array_numeric | 27.8 / 28.8 ms | 28.4 / 29.2 ms |
| heapsort | 31.8 / 36.0 ms | 32.9 / 35.5 ms |
| mergesort | 26.7 / 29.2 ms | 25.4 / 27.6 ms |
| list_ops | 68.9 / 77.1 ms | 73.7 / 78.2 ms |
| fib | 400.6 / 415.8 ms | 394.9 / 412.8 ms |

Every delta is inside the run-to-run spread. So at `--opt 2` clang already deals with
these constant-size in-loop slots (they never were the cost); the `dot_simd` gap to
`dot_composed` (about 9 ms vs 2.3 ms here) is NOT the allocas. What remains in that
loop is the volatile preempt load and the `march_incrc_local` calls, i.e. directions 2
and 4. Do not retry direction 3 expecting a speedup; it could still be worth doing for
IR readability or to drop the `stacksave`/`stackrestore` pair at `--opt 0`, but that
is a separate (unmeasured) motive.
