# Three x86_64 performance findings from the first dedicated-host benchmark run

Filed 2026-08-04. Measured on GCP `mgrep-c4`: Intel Xeon Platinum 8581C
(Emerald Rapids) @ 2.30GHz, 4 cores, 14 GB, **load 0.10** — idle, unlike the
shared dev machine every previously published number came from. Linux
6.17.0-1021-gcp x86_64, OCaml 5.3.0, rustc 1.97.1, Elixir 1.14.0, NumPy 2.5.1.

Medians of 10 runs, spreads under ~2%:

| Benchmark | March | OCaml | Rust | Elixir |
|---|---|---|---|---|
| fib(40) | 429.5 | 557.8 | **268.6** | 1513.6 |
| binary-trees(15) | 526.3 | **26.5** | 119.6 | 370.1 |
| tree-transform | **3017.6** | 6947.0 | 4310.7 | 4837.6 |
| list-ops(1M) | 148.8 | 49.7 | **1.3** | 356.0 |
| simd-sum(5M) | **4.0** | 7.2 | 5.1 | 79.2 (NumPy 2.8) |
| simd-map(5M) | 18.6 | **8.7** | 17.4 | 460.6 (NumPy 9.2) |

---

## 1. fib(40): a volatile preemption load on every call

Emitted IR, at the top of every March function:

```llvm
define i64 @fib(i64 %n.arg) {
entry:
  %red1 = load volatile i64, ptr @march_preempt_request
  %need_yield2 = icmp ne i64 %red1, 0
  br i1 %need_yield2, label %sched_yield1, label %sched_cont2
```

`volatile` is doing real work here: LLVM may not hoist it out of a loop, merge
it across calls, or delete it. fib(40) is ~300M calls, so this is ~300M
un-elidable loads plus a predictable branch that neither Rust nor OCaml pays.

**Measured, not just theorized.** Neutralizing the check in the emitted IR
(replace the volatile load with a constant 0, keeping the SSA name — LLVM folds
the branch away at -O2) and building both variants against the identical
runtime, 7 runs each, outputs verified byte-identical:

```
base   (check present)  median 441.4 ms   min 439.3   max 442.3
nopre  (check removed)  median 303.3 ms   min 303.2   max 304.1
```

The check costs **138 ms — 31% of fib's runtime, and 80% of the gap to Rust**
(441 − 269 = 172 ms gap; 303 − 269 = 34 ms remains). Per call that is
~0.46 ns ≈ one cycle at 2.3 GHz; fib is simply 300M calls of almost nothing, so
one cycle per call is 31%.

The stripped binary's hot path is 22 instructions and otherwise optimal: LLVM
loop-converts the second recursive call, and **no tag/untag arithmetic survives**
— the erased-i64 tagging visible in the raw IR is fully folded intraprocedurally
at -O2. So fib's story is entirely the preemption check; there is no second
codegen problem hiding behind it. The residual 13% vs Rust is call-shape/layout
territory, not worth chasing.

Candidate mitigations, all gated on the starvation test (the per-call check IS
the progress guarantee — a CPU-bound TCO loop once starved a sibling green
thread):

- **Skip the check in leaf functions** (no calls, no loops): bounded work
  between checks is preserved by the caller's own check. Does not help fib
  (recursive), but shrinks the tax generally.
- **Amortise via a counter** (Erlang-style reductions): decrement a
  thread-local, poll the shared flag only on zero. Trades a volatile global
  load for a thread-local decrement — needs measuring, not obviously cheaper.
- **Relax volatile to an atomic monotonic load**: LLVM may then merge some
  adjacent checks. Risky — the optimizer is also allowed to hoist monotonic
  loads out of loops in ways that could unbound the check interval. Would need
  a hard argument, not just a green test run.

## 2. binary-trees: `march_alloc` is `calloc`, against OCaml's bump allocator

`runtime/march_runtime.c`:

```c
void *march_alloc(int64_t sz) {
    void *p = calloc(1, (size_t)sz);
    ...
    h->rc = 1; h->tag = 0; h->pad = 0;
```

Per node March pays a `calloc` (allocator bookkeeping **plus zeroing**) and
later an individual `free`. OCaml bump-allocates in a minor heap and never frees
individually — the minor GC copies survivors and resets the pointer. On a
workload that is nothing but millions of short-lived nodes, that is a structural
difference, and 526 ms vs 26.5 ms (**20×**) is what it buys.

Two directions:

- **Stop zeroing.** The header is overwritten immediately, and constructor
  fields are written by the emitted code, so most of the zeroing is dead work.
  **Careful:** at least one caller depends on it —
  `march_task_spawn_with_cancel_thunk` notes "march_alloc zeroed the object and
  the trampoline records task[2] itself". Any switch to `malloc` needs an audit
  of who relies on zero-init, not a blanket replacement.
- **Bump-allocate.** `specs/gc_design.md` already describes per-actor arenas
  with bump allocation ("Linear/affine: bump pointer in actor arena"). This
  benchmark is the argument for implementing that layer.

Note the shape of the result: March *wins* tree-transform (FBIP reuses nodes in
place, so it barely allocates) and *loses* binary-trees (pure allocation). Those
two results are the same fact seen from both sides.

## 3. simd-map: vectorizes fine; the ISA baseline costs ~13%, and the 2× gap to OCaml is still unexplained

**A first pass at this was wrong twice, and the corrections are the useful part.**

*Wrong claim 1: "the map loop is scalar."* An instruction census showed one
scalar `mulsd` and zero `mulpd`, which looked conclusive. It is not: the
benchmark computes `x * 2.0 + 1.0`, and LLVM strength-reduces `x * 2.0` into
`x + x`. The vectorized loop therefore contains packed **adds** and no multiply
at all. Counting instructions cannot answer "did this vectorize"; ask the
vectorizer:

```
$ clang -O2 -msse4.2 -Rpass=loop-vectorize -c simd_map.ll
remark: vectorized loop (vectorization width: 2, interleaved count: 2)
```

It vectorizes. `-Rpass-missed=loop-vectorize` reports nothing precisely because
nothing was missed. (The generic `native_float_arr_map` in the runtime — which
calls a closure per element and genuinely cannot vectorize — is not used here:
the binary contains zero calls to it and zero `clo_call_dbl_dbl`. The Stage 4
inlined clone does fire on x86.)

*Wrong claim 2: "so the `-msse4.2` baseline is the bottleneck."* The baseline is
real — `bin/main.ml:3154` pins x86 to SSE4.2, and the width follows:

| flags | width × interleave | doubles/iteration |
|---|---|---|
| `-msse4.2` (shipped) | 2 × 2 | 4 |
| `-march=native` (AVX-512 present) | 4 × 4 | 16 |

But 4× the vector width is not 4× the speed. Linking the same IR both ways
against the real runtime and timing the self-reported operation, 7 runs each:

```
sse     18.76 18.88 20.78 20.87 21.11 22.94 23.05   median 20.87 ms
native  17.40 17.81 17.94 18.12 19.33 19.76 19.88   median 18.12 ms
```

**~13%.** The loop is not vector-width-bound. Something else dominates —
plausibly the result-array allocation, the `memcpy`-per-element in/out pattern,
or memory bandwidth at 5M doubles (40 MB touched, far past L3).

So the honest state of simd-map:

- The docs' "genuinely vectorizes" claim is **correct on x86**, contrary to the
  first draft of this file. No documentation change needed.
- Raising the ISA baseline is worth ~13% here and is cheap to offer (a
  `--target-cpu`/`-march` passthrough), but it is not the answer to the OCaml
  gap.
- **March 18.6 ms vs OCaml 8.7 ms remains unexplained** and is the actual open
  question. Profile before theorising further; the two wrong turns above both
  came from reasoning about the artifact instead of measuring it.

---

## Suggested order

1. **The allocator (finding 2)** — the largest single gap, 20×, and the one with
   a design already written down (`specs/gc_design.md`'s per-actor bump arenas).
2. **The preemption check (finding 1)** — now quantified at 31% of fib and 80%
   of its gap to Rust, with the leaf-function elision as the safest first cut.
   Gated on the starvation test.
3. **Profile simd-map** to find what the remaining 2× vs OCaml actually is.
   Allocation and the per-element `memcpy` are the first suspects; measure
   rather than reason, per the two wrong turns recorded above.
4. Optionally expose a `--target-cpu` passthrough — worth ~13% on simd-map here,
   but it is a knob, not a fix.
