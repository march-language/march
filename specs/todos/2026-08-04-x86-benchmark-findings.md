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

This is the price of green threads being preemptible — a compiled March function
must be interruptible, and the reduction check is how. It is not obviously
wrong, but it is the reason a pure-call-overhead benchmark reads the way it
does, and it should be stated rather than left as a mystery.

Worth investigating: whether the check can be elided for **leaf-ish** frames or
amortised (checked every N calls via a counter rather than every call). Any such
change interacts with the starvation guarantee — see the scheduler notes about a
CPU-bound TCO loop starving a sibling green thread — so it needs the starvation
test as its gate.

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

## 3. simd-map does not vectorize on x86_64

`docs/simd-benchmarks.md` says `map_float` "gets the boxing-free inlined clone
(Stage 4 Option B) and genuinely vectorizes". On x86 it does not.

The benchmark computes `x * 2.0 + 1.0`. Instruction census of the compiled
binary:

```
simd_map:   9 addsd   7 addpd   1 mulsd     <- the multiply is SCALAR, no mulpd
simd_sum:   3 addsd   3 addpd                <- sum does get packed adds
```

One scalar `mulsd` and **zero packed multiplies**: the map loop is scalar. The
`addpd`s are reduction paths elsewhere. simd-sum, by contrast, does vectorize —
and it shows in the numbers (March 4.0 ms beats Rust 5.1 and OCaml 7.2), while
map loses to OCaml 18.6 vs 8.7.

Two candidate causes, neither confirmed:

- **ISA baseline.** March compiles x86 with `-msse4.2` (`bin/main.ml:3154`),
  so 128-bit SSE at best — no AVX2/AVX-512 on a machine that has both. This
  caps the win but does not explain a *scalar* multiply.
- **Aliasing.** The map writes a destination array while reading a source. With
  no `noalias`/`restrict` on the emitted pointers, LLVM cannot prove they do not
  overlap and will refuse to vectorize. `-fno-strict-aliasing` is also passed to
  the runtime compile, which removes the other analysis that could have helped.

The docs claim is presumably true on arm64 (where the published numbers were
taken) and platform-specific. Until that is resolved, the SIMD page should say
which platform the vectorization claim holds on.

---

## Suggested order

1. Confirm the aliasing hypothesis for simd-map (`-Rpass-missed=loop-vectorize`
   on the emitted IR will say why the loop was rejected). Cheapest, and it is a
   documentation-correctness issue right now.
2. Decide on the allocator direction for binary-trees — the largest single gap.
3. Investigate amortising the preemption check, gated on the starvation test.
