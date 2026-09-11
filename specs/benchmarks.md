# March Benchmarks

## HTTP benchmark: Run 5 (2026-08-01) — LINUX, quiet box. The macOS numbers were a platform artifact.

Every HTTP figure before this section was measured on macOS/arm64 on a shared,
heavily loaded machine. This run is an idle 4-vCPU DigitalOcean droplet
(Ubuntu 24.04, kernel 6.8, epoll), load < 1. **Three earlier conclusions do not
survive it.**

### 1. The "~30k req/s ceiling" was macOS loopback, not March

| | macOS (contended) | Linux (idle) |
|---|---:|---:|
| req/s, c=64 | ~30,000 | **72,703 / 62,951** |
| req/s, c=256 | ~30,000 | **47,418** |

Linux does 2.1–2.4× the throughput. Earlier text calling this ceiling
"client/kernel-side, not March" was right about the cause and wrong to imply it
was a property of the workload — it is a property of *Darwin*.

### 2. The event loop is far better on Linux than the macOS numbers suggested

wrk `-c256`, order-swapped, one binary switching implementation at runtime:

| server | req/s | CPU-µs/req |
|---|---:|---:|
| thread pool (default) | 45,990 / 51,018 | 47.46 / 43.04 |
| event loop | 76,488 / 80,416 | **27.35 / 24.76** |

**+61% throughput and −42% CPU per request.** On macOS/kqueue the gap was 21%
CPU and the event loop actually *lost* on req/s to a scheduling artifact. This
is a Linux-specific win, and Linux is where servers run.

### 3. SO_REUSEPORT accept sharding does nothing — built, measured, reverted

Sharding the thread pool's accept loop across per-thread `SO_REUSEPORT`
listeners was implemented and then reverted, because on the box and in the
regime most favourable to it, it produced nothing:

| | shards=1 | shards=4 | effect |
|---|---:|---:|---:|
| connection-close (**treatment**) | 106.7 µs | 107.5 µs | +0.7% |
| keep-alive (**control**) | 32.6 µs | 37.6 µs | +15.5% |

The control is the result. In keep-alive, accept happens ~64 times in ten
seconds and sharding *cannot* matter — yet it moved 15.5%. That is the noise
floor, and the treatment effect is twenty times smaller than it. The
within-arm spread on shards=1 close (13.1 µs) is itself larger than the whole
treatment effect. Reverted in the commit following its own.

### 7. Hoisting per-connection setsockopt onto the listener — verified inheritable, measured no effect

Followed up on the syscall inventory in §6: does Linux inherit `TCP_NODELAY`
/ `SO_SNDBUF` / `SO_RCVTIMEO` from the listening socket onto `accept()`ed
sockets, which would let `connection_thread` skip all three per connection?

**Inheritance itself is real** — verified with a standalone probe
(`getsockopt` on an accepted socket after setting all three only on the
listener): all three inherited exactly, unlike the *documented* POSIX
behavior (there is none; this is Linux-kernel-specific and not guaranteed on
BSD/macOS, so any implementation must stay Linux-gated).

**But it does not measurably help.** Env-gated single-binary A/B
(`MARCH_ABL_HOIST_SOCKOPT`, not merged), connection-close, order-swapped:

| | baseline (per-connection) | hoisted (listener-only) |
|---|---:|---:|
| CPU-µs/req | 98.61 / 86.09 (mean 92.4) | 100.66 / 90.10 (mean 95.4) |

Hoisted is *slightly worse*, well inside the run-to-run spread. Three fewer
syscalls out of the seven counted in §6 produced no measurable change —
consistent with §6's own caveat that `setsockopt` is cheap relative to
`accept`/`close` socket-lifecycle and TCP state-machine work, which this
change does not touch. Not implemented.

**Pattern across §5-§7:** three independent "obviously true" micro-costs —
per-request header allocation, listener sharding, per-connection
`setsockopt` — each measured and each showed no effect above noise on this
hardware. The connection-close overhead itself (§6) is real and large
(~90-100 µs against keep-alive's ~24-27), but none of these syscall-count
reductions touch it; whatever the real cost is, it lives inside `accept`/
`close`/the kernel's TCP connection lifecycle, not in the small number of
option-setting calls around it. That points toward eliminating connections
entirely (HTTP/1.1 keep-alive already does this when the client cooperates;
HTTP/2 multiplexing would force it) rather than making individual
connections cheaper to set up.

### 6. TCP_FASTOPEN — investigated, not implemented: unmeasurable in this rig

Considered as a way to cut the connection-close cost (Run 5 measured ~94-107
CPU-us/request for a fresh connection per request, against keep-alive's
~24-27). Not built, because two independent facts make it unverifiable here,
either one alone sufficient:

1. **`wrk` has no TFO support** — no `--fastopen` flag, and `strings` on the
   binary shows no `MSG_FASTOPEN` anywhere. TFO's saving only exists when the
   *client* sends data in the SYN packet; our load generator can never
   exercise that path, so a correct server-side implementation would be
   invisible to every benchmark this project runs.
2. **Loopback has no RTT to amortize.** Measured `ping -c3 127.0.0.1`:
   0.027-0.054 ms round trip. TFO's entire mechanism is skipping the wait for
   a handshake ACK before sending data; on a real network with 20-50 ms RTT
   that is decisive, but the maximum theoretical saving over a sub-millisecond
   loopback round trip is a few tens of microseconds. The technique's value
   only exists over real network latency, which this rig cannot produce.

**What actually explains the connection-close cost, from `strace -f -c`
(counts, not the reported timings — `strace`'s ptrace-trap overhead inflates
per-syscall timing by an unknown, large factor, so only call COUNTS are
trustworthy here):**

| syscall | connection-close | keep-alive |
|---|---:|---:|
| accept | 1/request | amortized over the connection |
| setsockopt (NODELAY + SNDBUF + RCVTIMEO) | 3/request | amortized |
| recv | 1/request | 1/request |
| writev | 1/request | 1/request |
| close | 1/request | amortized |

**7 syscalls/request against keep-alive's 2.** The gap is syscall COUNT, not
RTT — every one of those extra 5 is real kernel work (socket alloc, TCP state
machine, buffer setup, fd teardown) that has to happen once per TCP
connection regardless of how fast the network is. Nothing under consideration
here removes that work; TFO specifically only removes a WAIT, not the work
itself, which is why it would not have helped even if it were measurable.

Not investigated: whether `SO_SNDBUF` set on the *listening* socket is
inherited by `accept()`ed sockets on Linux, which would drop one of the three
per-connection `setsockopt` calls if so. Flagged as a small, real, but
unverified follow-up rather than the primary throughput lever.

### 5. Header allocation is not a measurable cost, even at a realistic count

`march_conn_from_parsed` (`runtime/march_http.c`) allocates a March string,
`Header` cell, and `Cons` cell per request header — flagged earlier as
possibly under-costed because wrk's default request carries only 2-3 headers
against a realistic browser's 12-15. Re-measured directly: an env-gated
ablation (`MARCH_ABL_NOHDR`, measurement-only, not merged) that skips the
header-list build entirely, against 12 realistic headers (~550 bytes:
Accept/Accept-Language/Accept-Encoding/Cache-Control/Sec-Fetch-*/Cookie/
X-Request-Id) on the idle Linux droplet, order-swapped:

| | with headers | headers skipped |
|---|---:|---:|
| 2-3 headers (wrk default) | 25.11 / 22.43 µs | 23.60 / 23.81 µs |
| 12 headers (~550 bytes) | 24.75 / 23.09 µs | 23.91 / 23.75 µs |

The "effect" (≤0.1 µs) is an order of magnitude smaller than the spread
*within* either arm (up to 2.7 µs run-to-run). Lazy or borrowed headers would
not be a measurable win at realistic request sizes on this hardware — the
allocator is simply fast enough for a dozen small, short-lived strings.
Superseded, not merely unconfirmed: this closes the question raised after the
macOS thread-pool sweep, which had only 2-3 headers to work with and
correctly flagged the gap rather than asserting a conclusion from it.

### 4. `rrb_bench` parallel-vs-sequential: the earlier lead was contention

Recorded in the 2026-07-31 sweep as "parallel ~22% slower, needs a quiet-box
re-run before anyone concludes the parallel machinery costs more than it
saves." It does not:

| | contended macOS (14 cores, load 15) | idle Linux (4 cores) |
|---|---:|---:|
| `seq_fold_left` | 1011 / 1012 / 1015 ms | 5229 / 4850 / 5230 ms |
| `psum` | 1225 / 1252 / 1245 ms | **2460 / 2320 / 2528 ms** |
| `preduce` | 1228 / 1204 / 1268 ms | **2472 / 2368 / 2531 ms** |

On an idle box the parallel arms are **2.1× faster** than sequential, not 22%
slower. The macOS reading was entirely an artifact of a parallel arm being
unable to get cores on a machine at load 15 while the sequential arm needed
only one. Filing it as a lead rather than a finding was the right call.

**Methodology, restated:** measure HTTP on Linux. A macOS laptop cannot tell
you what a server does, and a contended box cannot tell you what a parallel
algorithm does.

---

## Compute-benchmark sweep, 2026-07-31 — and why absolute-ms baselines cannot detect regressions

All 31 non-network benchmarks compiled at `--opt 2` and ran clean: 31/31 exit 0,
every documented checksum correct (`fib` 102334155, `tree_transform` 104857600,
`list_ops` 333333666666, `merkle` 6400 — not the 51200 that would flag the
pointer-equality bug, `string_build` 2888895, `string_pipeline` 644449).

**The methodology finding is the important one.** `hash_map_bench` measured
~25–29% above its documented 2026-06-24 baseline, on all nine workload/size
combinations, with tight variance (best-of-3 spread ~4%). Nine out of nine in
the same direction, and stable across repeats — the signature of a real
regression rather than noise.

It was not a regression. Built at the baseline commit (`79d10f06`) in a scratch
worktree, confirmed the benchmark source is byte-identical, and A/B'd the two
compilers on the same box at the same moment, order-swapped:

| workload | n | June compiler | today | delta |
|---|---:|---:|---:|---:|
| put/get | 10000 | 36 ms | 31 ms | **−14%** |
| put/get | 50000 | 239 ms | 206 ms | **−14%** |
| put/get | 100000 | 531 ms | 475 ms | **−11%** |
| uniq | 10000 | 19 ms | 16 ms | **−16%** |
| uniq | 50000 | 117 ms | 104 ms | **−11%** |
| uniq | 100000 | 275 ms | 239 ms | **−13%** |
| frequencies | 10000 | 38 ms | 33 ms | **−13%** |
| frequencies | 50000 | 213 ms | 184 ms | **−14%** |
| frequencies | 100000 | 452 ms | 395 ms | **−13%** |

**Today is 13% faster than June.** The documented numbers were simply taken on
a quieter machine. The same trap caught `string_small_churn`: a single run read
1021 ms against a documented 741 ms (+38%), but best-of-3 gave 761 ms (+3%) —
and non-March controls built from `bench/c` and `bench/cpp` were themselves
+7% and +13% over *their* documented numbers, i.e. March was the least affected
of the three.

**So: an absolute millisecond figure in this file is a record of one machine on
one day, not a regression detector.** To decide whether a change regressed
something, do not compare against the numbers here. Instead:

```bash
git worktree add /tmp/base <baseline-commit> --detach
cd /tmp/base && dune build --root . bin/main.exe && dune build --root . @install
./_build/default/bin/main.exe --compile --opt 2 bench/<name>.march -o /tmp/base-bin
# then A/B /tmp/base-bin against today's binary, same box, same minute,
# order-swapped A,B,B,A, and diff the benchmark source first to confirm it
# has not changed underneath you.
```

**One open lead — since RESOLVED, see Run 5 above.** `bench/rrb_bench.march`'s
parallel arms measured ~22% *slower* than its sequential one here, tight enough
to look structural, but on a 14-core box at load 15. It was filed as a lead
rather than a finding pending a quiet-box re-run. That re-run (idle 4-core
Linux) shows the parallel arms **2.1× FASTER** than sequential. The macOS
reading was entirely contention.

---

All benchmarks live in `bench/`. Run the full suite:

```
bash bench/run_bench.sh
```

Compile and run an individual benchmark:

```
dune exec march -- --compile --opt 2 bench/<name>.march -o /tmp/<name>
/tmp/<name>
```

---

## bench/fib.march — Naive recursive Fibonacci

**Command:** `fib(40)`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| Naive recursion | Exponential call tree — no allocation |
| Integer arithmetic | Pure `+` on unboxed `Int` |
| Function call overhead | ~330 million calls for fib(40) |

**Comparison baseline:** C, OCaml, Rust, Python, Go (all naive recursive).
**What to watch:** March should be within ~10% of C/Rust/OCaml. A regression here
points to function-call or codegen overhead.

---

## bench/binary_trees.march — Binary Trees (Benchmarks Game depth=15)

**Command:** depth 15, min 4
**Expected output:** standard Benchmarks Game output

| Feature exercised | Notes |
|-------------------|-------|
| Heap allocation | Millions of `Node`/`Leaf` allocations |
| Reference counting | Perceus dec_rc on every freed node |
| Pattern matching | `check` walks entire tree via `ECase` |
| Tail recursion | `sum_trees` / `run_depths` are tail calls |

**Comparison baseline:** C (manual malloc/free), OCaml (GC), Rust (Box<T>), Python, Go.
**What to watch:** OCaml's tracing GC batches frees and typically wins here.
March pays per-node dec_rc. A large regression vs the previous run suggests
the Perceus pass is inserting extra dec_rc calls.

---

## bench/tree_transform.march — FBIP tree rewrite (depth=20, ×100)

**Command:** `make(20)` → `repeat(inc_leaves, 100)` → `sum_leaves`
**Expected output:** `104857600`

| Feature exercised | Notes |
|-------------------|-------|
| **FBIP (Functional But In-Place)** | Primary target — uniquely owned nodes rewritten in-place |
| Perceus `EReuse` | `reuse t as Leaf(n+1)` / `reuse t as Node(l', r')` |
| `try_fbip_sink` | Sinks `EDecRC` through intermediate `ELet` bindings |
| Constructor-type tagging | DecRC carries concrete `TCon(ctor, [])` for shape matching |
| Recursive tree traversal | `inc_leaves` is structurally recursive, not tail-recursive |

**Comparison baseline:** C (alloc+free every iteration), OCaml (alloc+GC), Rust (Box<T> drop+alloc).
**What to watch:** March should be ~15–17× faster than C and ~7× faster than OCaml.
If FBIP regresses (TIR shows `alloc` instead of `reuse`), check:
1. `shape_matches` — are constructor types being compared correctly?
2. `try_fbip_sink` — is the DecRC reaching the EAlloc through ELet chains?
3. ECase scrutinee handling — is the DecRC emitted with the concrete ctor tag?

---

## bench/list_ops.march — HOF pipeline (range 1M → map → filter → fold)

**Command:** `irange(1, 1_000_000) |> imap(*2) |> ifilter(%3=0) |> ifold(+, 0)`
**Expected output:** `333333666666`

| Feature exercised | Notes |
|-------------------|-------|
| Higher-order functions | `imap`, `ifilter`, `ifold` take closure arguments |
| Closure call overhead | Each element invokes a captured lambda |
| Tail recursion | All list ops use accumulator+reverse pattern |
| Intermediate allocation | Two full intermediate lists (`ys`, `zs`) |
| `EReuse` on list cons cells | FBIP rewrites `ICons` in-place during `imap`/`ifilter` |

**Comparison baseline:** C (arrays, direct loops — best case), OCaml (`List.map`/`filter`/`fold_left`), Rust (iterators), Python (list comprehensions).
**What to watch:** March uses linked lists with intermediate allocations;
C/Rust use arrays or lazy iterators — the gap is expected. March should be
within ~30% of OCaml (same list-based approach, similar RC overhead to GC here).
A large regression vs OCaml points to closure dispatch or intermediate-list GC overhead.

---

## bench/vector_math.march — Vec3 integrator loop (unboxed aggregates)

**Command:** `step(0, 3_000_000, ...)` — a toy integrator building five `Vec3`
temporaries per iteration (`vadd`, `vscale`, `vdot`, `vcross`).
**Expected output:** `6853874.21103`

| Feature exercised | Notes |
|-------------------|-------|
| `Repr.Unboxed` | `Vec3(Float, Float, Float)` is an LLVM struct value, not a cell |
| Struct-value ABI | vectors are passed and returned in registers across `vadd`/`vcross` |
| `Llvm_case` unboxed arm | every operation destructures with `extractvalue` |
| Allocator throughput | under the boxed representation this is 15M `march_alloc(40)` |

**Comparison baseline:** its own boxed representation, via the escape hatch:
`MARCH_NO_UNBOX=1 march --compile --opt 2 bench/vector_math.march -o /tmp/vmb`.
**What to watch:** the two builds must print the same number. The unboxed build
should be roughly an order of magnitude faster — the loop is deliberately free
of any allocation except the vectors, so the whole gap is allocator cost. If
the gap closes, a heap slot has crept back in: check for `march_alloc` in the
emitted IR for `step` (`--emit-llvm`), and for a `coerce` boxing at a slot
boundary (`Llvm_ctx.llvm_field_ty`).

Measured on an M-series Mac, `--opt 2`, min of 5 runs:
`unboxed 20.8 ms` vs `boxed 828.3 ms`.

---

## bench/list_producers.march — list-producer traversal count (TRMC)

**Command:** `List.range(1, 20000)` threaded through `repeat_n(step, 2000)`, `step = List.map(xs, fn x -> x + 1)`
**Expected output:** `239988000`

| Feature exercised | Notes |
|-------------------|-------|
| TRMC (tail-recursion-modulo-cons) | Primary target — `List.map` is a list-producer whose result is threaded straight into the next call, isolating per-pass traversal cost |
| FBIP reuse | Each pass sees a uniquely-owned list, so `EReuse` still applies independent of TRMC |
| Recursive driver | `repeat_n` is itself tail-recursive; the cost under test is entirely inside `step`/`List.map` |

**Baseline (2026-08-10, macOS/arm64 shared/contended dev machine, compiled
`--compile --opt 2`, TRMC off — `MARCH_TRMC` unset, which is the default):**
3 runs of the compiled binary, run 1 discarded as ~25% warmup:

| run | real | user | sys |
|---|---|---|---|
| 1 (warmup, discarded) | 0.96s | 0.64s | 0.05s |
| 2 | 0.77s | 0.64s | 0.04s |
| 3 | 0.86s | 0.64s | 0.04s |

**Usable baseline: real ≈ 0.77-0.86s, user ≈ 0.64s (runs 2-3).** Compare on
`user` CPU time, not `real` — on a contended machine `real` wall-clock time
picks up scheduler noise (this file's own tree_transform/list_ops/binary_trees
sweep saw `real` vary 2x run-to-run while `user` stayed flat), so `user` is
the number Task 8's before/after comparison must beat. Measured on a
different machine class, these absolute numbers do not carry over — re-measure
before comparing. Full raw tables (including the TRMC on/off sweep over
`tree_transform`/`list_ops`/`binary_trees`) are archived in
`.superpowers/sdd/2026-08-10-trmc-on-by-default/task-2-report.md`, which is a
workspace-local (git-ignored) file kept for extra detail only — the numbers
above are the durable, version-controlled record.

---

## bench/string_build.march — Join 500K integer strings

**Command:** build List(String) of 1..500000, `string_join(list, "")`
**Expected output:** `2888895` (sum of digit-lengths of integers 1..500000)

| Feature exercised | Notes |
|-------------------|-------|
| `int_to_string` | 500K calls in a tail-recursive loop |
| `string_join` | Single O(n) join via C runtime `march_string_join` |
| Tail recursion | `build` is tail-recursive with List accumulator |
| Reference counting | Cons cells freed after join |

**Comparison baseline:** C (pre-allocated buffer, single sprintf loop), OCaml (Buffer.t), Rust (String::collect), Python (str.join), Go (strings.Builder).
**What to watch:** March pays per-Cons-cell allocation; C/OCaml Buffer avoids it. A regression vs the prior March run points to RC overhead or codegen for `string_join`.

---

## bench/string_pipeline.march — Double and rejoin 100K integer strings

**Command:** build list of 1..100000, `map double_str`, `string_join(list, ",")`
**Expected output:** `644449` (byte length of "200000,199998,...,4,2")

| Feature exercised | Notes |
|-------------------|-------|
| `string_to_int` | 100K calls inside `double_str` |
| `int_to_string` | 100K calls to format doubled values |
| `string_join` | O(n) join at the end |
| Pattern match on `Option` | `Some(n)` / `None` branch in `double_str` |
| Recursive list map | `map_strings` is non-tail-recursive (100K depth) |

**Comparison baseline:** C (sprintf loop), OCaml (Buffer + atoi), Rust (map + join), Python (list comprehension), Go (strconv + strings.Join).
**What to watch:** March uses a linked list; C/Rust use arrays. March should be within ~2× of OCaml. A regression vs OCaml points to Option allocation or string_to_int overhead.

---

## bench/string_scan.march — Substring search over a 1MB buffer

**Command:** 150 absent-needle scans + 150 late-needle scans over 1MB
**Expected output:** `checksum=135000150`

| Feature exercised | Notes |
|-------------------|-------|
| `String.index_of` | Two-stage `memchr`+`memcmp` via `march_memmem` (`runtime/march_runtime.c`) — rides libc's SIMD-optimised `memchr` |
| Absent needle | Full O(n·m) worst case: every byte examined on every call |
| Late needle | Realistic "found at ~90% through" case |

**Comparison baseline:** C (`memmem`), Rust (`str::find`), Go (`strings.Index`), Python (`str.find`).
**What to watch:** Part of the phase 1 string measurement (`specs/2026-07-26-string-performance-design.md`). The `memchr`/SIMD fast path (Task 2, `specs/plans/2026-07-27-string-performance-phase2.md`) landed — a regression here now points at `march_memmem` or its call sites, not at a missing fast path.

---

## bench/string_case.march — Case conversion over a 1MB buffer

**Command:** 200 × (`to_uppercase` then `to_lowercase`) over 1MB
**Expected output:** `checksum=200000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.to_uppercase` / `to_lowercase` | Full-size allocation + byte-loop transform per call |
| Allocation throughput | 400 full-buffer allocations |
| Memory bandwidth | Pure map-and-copy, no search |

**Comparison baseline:** C (in-place `toupper` loop), Rust (`to_uppercase`), Go (`strings.ToUpper`), Python (`str.upper`).
**What to watch:** Paired with `string_scan` — if both are slow the ceiling is memory bandwidth, not the search loop, and no cleverness in `index_of` will help. **Its checksum cannot detect the conversion being optimized away** (it sums `byte_size`, which case conversion leaves unchanged), so judge a suspicious speedup by `copy_bytes` under `MARCH_STRING_STATS=1` — it should stay near 400MB. Under `MARCH_STRING_STATS=1` this should report ~400MB copied; a reading near 1MB means the byte-loop builders lost their copy accounting again (they don't call `memcpy`, so they're counted explicitly).

---

## bench/string_split_large.march — Split an 800KB CSV-shaped buffer

**Command:** 60 × `String.split(buf, ",")` over 800KB (50K rows, 150K fields)
**Expected output:** `checksum=39000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.split` | One string + one cons cell + one copy per field |
| Cons-cell allocation | ~150K cells per iteration |
| Peak memory | Every field is live simultaneously |

**Comparison baseline:** C (in-place `strtok`, zero copy), Rust (`split` iterator, zero copy), Go (`strings.Split`), Python (`str.split`).
**What to watch:** **Paired with `string_slice_walk`** — same buffer, same field shape, same field count, on purpose. Changing one file's size knob without the other invalidates the comparison. Measured together (60 iterations): `obj_allocs` 9,000,120 vs 0 (the cons cells), `copy_bytes` 39.8MB vs 27.8MB, `peak_live_bytes` **39.8MB vs 800KB**. Note that `allocs` — the *string* counter — is nearly identical for the two (9,000,126 vs 9,000,006), because cons cells go through `march_alloc` rather than `march_string_alloc`; use `obj_allocs` for list overhead.

---

## bench/string_slice_walk.march — Slice 150K fields out of 800KB, no list

**Command:** 60 × 150K `String.slice` calls over 800KB, building no list
**Expected output:** `checksum=27000000`

| Feature exercised | Notes |
|-------------------|-------|
| `String.slice` | Allocates and copies off a large owner — no view representation exists |
| Zero cons cells | The controlled difference vs `string_split_large` |
| Flat peak memory | One field live at a time |

**Comparison baseline:** C (pointer walk, zero copy), Rust (`&str` slices, zero copy), Go (slicing, zero copy), Python (`str` slicing, copies).
**What to watch:** See `string_split_large`. Languages with string views do this with no allocation at all, so the gap is the size of the prize. This benchmark walks by arithmetic rather than by searching: the natural formulation (`index_of` the separator, slice off the tail, recurse) is O(n²) in bytes copied, since `String.index_of` has no start-offset variant and the tail must be re-sliced every step. Search cost is measured separately by `string_scan`.

---

## bench/string_small_churn.march — 2M short-string build/compare cycles

**Command:** 2M × (build two short strings, concat twice, prefix-compare, discard)
**Expected output:** `checksum=17793810`

| Feature exercised | Notes |
|-------------------|-------|
| Small-string allocation | Every string is a `malloc` + refcount, even 4 bytes |
| `++` on short operands | Three concatenations per iteration |
| `String.starts_with` | Short-prefix compare, consumes the concatenation |
| Allocate-and-free churn | Nothing escapes the loop |

**Comparison baseline:** Rust (`String` — no SSO either), C++ (`std::string` — has SSO), Go, Python (interns short strings).
**What to watch:** The size histogram under `MARCH_STRING_STATS=1` is the SSO evidence. Measured: 24,000,004 allocations, of which **91.7% are ≤23 bytes** (13.2M ≤7, 6.9M ≤15, 1.9M ≤23) — 23 being what fits in the footprint the 24-byte header already occupies. Doubling `pairs()` doubles both allocations (24M → 48M) and wall time (0.80s → 1.58s), confirming allocation is the bottleneck rather than incidental. The C++ comparison is the informative one, since it is the baseline that *has* the optimization under consideration.

---

## bench/run_string_xlang.sh — cross-language `string_small_churn`

**Command:** `bash bench/run_string_xlang.sh`
**Expected output:** every implementation prints `checksum=17793810`

Runs `bench/string_small_churn.march` against four baselines, each chosen to
separate an explanation a single number cannot:

| Baseline | Source | Why it is here |
|---|---|---|
| Rust | `bench/rust/string_small_churn.rs` | `String` has **no** small-string optimization — March's exact representation. Isolates allocator + refcount overhead. |
| C++ | `bench/cpp/string_small_churn.cpp` | `std::string` **has** SSO. Bounds the prize from inline storage. The only C++ in the repo, added deliberately as a one-off for this question. |
| C | `bench/c/string_small_churn.c` | Raw `malloc`, no header, no refcount — the floor. |
| Python | `bench/python/string_small_churn.py` | `pymalloc` is itself a size-class freelist, in a much slower language. |

**What to watch:** the run FAILS if any implementation's checksum differs — that
means they are not doing the same work and the timings are meaningless. A
missing toolchain is reported as SKIPPED rather than silently omitted (Go is not
installed on the primary dev machine). Load average is printed and warned on;
compare the *ratios* within one run, never absolute milliseconds across runs.

Measured 2026-07-27: C++ 246ms, C 411ms, Rust 566ms, March 741ms, Python
1305ms. See `specs/2026-07-26-string-performance-profile.md` for what that says
about the freelist-versus-SSO decision.

---

## bench/string_parallel_scan.march — Shared-buffer scan at 1/2/4/8 workers

**Command:** count `"QQ"` occurrences in a 40MB buffer, chunked across 1, 2, 4, 8 workers
**Expected output:** `checksum=16000000`, plus one `workers=N ms=T` line per worker count

| Feature exercised | Notes |
|-------------------|-------|
| `Parallel.pmap` | Vec-based — chunk indices via `RRB.from_list`, results via `RRB.to_list` |
| Shared-owner refcounting | Every worker slices from the same string; atomic RC on one cache line |
| `String.slice` + `replace_all` | Per-chunk copy, then one full O(n) scan |

**Comparison baseline:** Rust (rayon over `&str` chunks, zero copy), Go (goroutines over slices), C (pthreads over pointer ranges).
**What to watch:** The scaling *shape*, not absolute times. Measured on an M3 Max (10 performance + 4 efficiency cores), stable across three runs: **131ms → 66ms (1.97×) → 34ms (3.9×) → 33ms (3.97×)**. Scaling is near-perfect to 4 workers and then flat — 8 workers buy nothing. That ceiling is *not* explained by core count (8 performance cores were available) nor by memory bandwidth (~80MB of traffic in 33ms ≈ 2.4GB/s, far below this machine's capability), which leaves shared-owner refcount traffic and allocator contention as the candidates. Distinguishing those two is phase 3's first job; the gate in `specs/2026-07-26-string-performance-design.md` is triggered.

**Known limitation, deliberate:** a needle straddling a chunk boundary is missed. Every boundary here falls inside the repeated 10-byte unit, so the count stays deterministic and the benchmark remains valid as a timing comparison. Handling boundaries correctly is precisely the problem phase 3 must solve, and it is not solved here.

**Counting method:** hits are counted as the length delta from `replace_all("QQ", "Q")` — one O(n) scan plus one O(n) build. The natural formulation (`index_of`, slice off the tail, repeat) is O(n²) in bytes copied, since `String.index_of` has no start-offset variant; at this size that is ~800GB of copying.

---

## bench/parallel.march — Parallel tree sum (depth=24, threshold=10)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode runs tasks on the M:N pthread work-stealing scheduler
(`runtime/march_scheduler.c`), so subtrees execute concurrently across cores.
The tree-walking interpreter evaluates each `task_spawn` thunk eagerly and
in-order, so interpreted runs are correct but single-threaded.

**Expected output:** `16777216`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Task spawning and join |
| **FBIP + parallelism** | Sibling subtrees have independent RC chains → in-place reuse on both sides with no synchronisation |
| Task granularity | Parallel to depth 10 (1024 tasks), then sequential |
| Scheduler scalability | N pthread workers, Chase-Lev work-stealing deques, one green thread per task (not OCaml Domains) |

**Comparison baseline:** Same sequential sum (measure parallel speedup), C with pthreads, Go goroutines.
**What to watch:** In compiled mode, expect near-linear speedup up to
`min(cores, 1024)` tasks. FBIP correctness in the parallel case: each task's sub-tree has RC=1 in its
own context, so `inc_leaves`-style transforms remain safe without locking.

---

## bench/par_fib.march — Parallel Fibonacci (embarrassingly parallel)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode forks the recursive tasks onto the M:N pthread work-stealing scheduler
(`runtime/march_scheduler.c`); the interpreter runs each `task_spawn` thunk
eagerly and in-order (correct but single-threaded).

**Command:** `par_fib(40, 20)`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` / `task_await_unwrap` | Fork/join with many small tasks |
| Task creation throughput | Thousands of tasks spawned recursively |
| No inter-task communication | Pure embarrassingly parallel — each subtask independent |
| Threshold tuning | Sequential below depth 20 to avoid micro-task overhead |

**Comparison baseline:** `bench/fib.march` (sequential), C with pthreads, Go goroutines.
**What to watch:** In compiled mode, parallelism is real — expect near-linear
speedup up to core count over the sequential `fib`. Measured scheduler
throughput (4-core M1): ~189K–209K tasks/sec (250K green threads in 1.32s;
see `specs/progress.md`). A regression vs sequential `fib` points to
task_spawn/task_await_unwrap call overhead or per-task scheduling cost.

---

## bench/par_map.march — Parallel Collatz map (embarrassingly parallel)

**Status: REAL PARALLELISM (compiled) / SEQUENTIAL (interpreted)** — compiled
mode runs the per-chunk tasks concurrently on the M:N pthread work-stealing
scheduler (`runtime/march_scheduler.c`); the interpreter runs each `task_spawn`
thunk eagerly and in-order (correct but single-threaded). The same machinery
backs `List.pmap`/`pfilter`/`preduce`, measured at ~281% CPU on a 200k-element
workload (see `specs/progress.md`).

**Command:** `par_map_sum(range(1, 100000), 1000)`
**Expected output:** `2660024`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn` with closure captures | Each task captures a list chunk |
| Independent task execution | No shared state between tasks |
| Variable-cost work items | Collatz step counts vary widely per element |
| Chunked parallelism | 100 tasks of 1000 elements each |

**Comparison baseline:** Sequential `map` + `fold` over same data, C with OpenMP parallel for.
**What to watch:** Measures the "map-reduce without reduce" pattern. Task overhead
should be small relative to the Collatz computation. A regression points to
closure capture overhead or list allocation under task boundaries.

---

## bench/par_worksteal.march — Work-stealing Fibonacci (Tier 2)

**Status: REAL WORK-STEALING (compiled) / SEQUENTIAL (interpreted)** — in
compiled mode `task_spawn_steal` spawns a real green thread onto the Chase-Lev
work-stealing deques (`lib/tir/llvm_emit.ml`, `runtime/march_scheduler.c`,
`runtime/march_deque.h`); idle pthread workers steal from busy ones. The
interpreter runs the thunk eagerly and in-order (correct but single-threaded).

**Command:** `par_fib(pool, 40, 20)` with `Cap(WorkPool)` from `main()`
**Expected output:** `102334155`

| Feature exercised | Notes |
|-------------------|-------|
| `task_spawn_steal` | Work-stealing tier (Tier 2) task creation |
| `Cap(WorkPool)` capability | Unforgeable capability threaded from `main()` |
| Capability threading | Pool passed explicitly through function signatures |
| Chase-Lev deque operations | Submit to worker deque, steal from others |

**Comparison baseline:** `bench/par_fib.march` (cooperative tier), C with work-stealing.
**What to watch:** Compare Tier 2 (work-stealing) vs Tier 1 (cooperative) overhead.
In compiled mode the work-stealing scheduler delivers better load balancing for
uneven workloads, since idle workers steal queued tasks from busy ones. The `Cap(WorkPool)` threading should have zero runtime cost
(it's a type-level capability, not a runtime check).

---

## bench/deque_ops.march — Functional deque (push_front/push_back/drain, ×100)

**Command:** 100 rounds of `push_phase(empty(), 10000)` → `drain`
**Expected output:** `20001000000`

| Feature exercised | Notes |
|-------------------|-------|
| `Deque.push_front` / `Deque.push_back` | O(1) worst-case Cons prepend |
| `Deque.pop_front` with rebalance | O(n) amortized; triggers `List.reverse` when front exhausted |
| `Deque.empty` | Zero-allocation initial state |
| RC overhead per push | Every `push_front`/`push_back` allocates one Cons cell |
| Persistent value semantics | Each call returns a new `Deque(Int)` — no mutation |

**Comparison baseline:** OCaml (same two-list algorithm, tracing GC — isolates RC vs GC cost),
Rust `std::collections::VecDeque` (mutable ring buffer — no allocation in steady state),
Elixir `:queue` (OTP two-list functional deque).

**What to watch:** March pays ~2× OCaml due to RC vs GC; gap vs Rust is larger because
VecDeque is mutable and allocation-free in steady state. A regression vs the prior March
run points to RC overhead in the Perceus pass or Cons-cell allocation cost.

---

## bench/merkle.march — Merkle tree build+diff (50 rounds, 1024 leaves, 128 changes)

**Command:** 50 rounds of build two 1024-leaf trees + `Merkle.diff`
**Expected output:** `6400` (50 × 128 differing hashes)

| Feature exercised | Notes |
|-------------------|-------|
| `Crypto.sha256` throughput | Hash every leaf string each build |
| `Merkle.build` | Recursive halving, `Some`/`None` tree allocation |
| `Merkle.diff` / `diff_work` | Work-list tail-recursive diff, skips unchanged subtrees via hash compare |
| String equality dispatch | `root_hash(t1) == root_hash(t2)` on polymorphic TVar return — routes through `march_poly_eq` |
| Reference counting on deep trees | 1024-leaf trees freed each round |

**Comparison baseline:** OCaml with `digestif` SHA-256 (requires `ocamlfind`),
Elixir with `:crypto.hash(:sha256, ...)` OTP builtin.
Rust not included (SHA-256 crate requires `Cargo.toml`).

**What to watch:** If output is `51200` instead of `6400`, the `==` comparison in
`diff_work` is using pointer identity instead of string content equality — this was
a real bug (fixed in `lib/tir/llvm_emit.ml`, TVar equality dispatch now routes to
`march_poly_eq`). A regression in SHA-256 throughput points to `Crypto.sha256`
or the C `mbedtls_sha256` binding.

---

## HTTP benchmark: Run 4 (2026-07-31) — readiness-gated pool: BUILT, MEASURED, REJECTED

A negative result, recorded so it is not rebuilt. **Do not re-attempt this
without first reading the attribution table below.**

**Hypothesis.** Run 3 left the default thread pool at ~36 CPU-µs/request against
the opt-in event loop's ~28. The suspected cause was the threading model:
`conn_serve` owns a connection for its whole keep-alive lifetime and blocks in
`recv()` between requests, so a thread is parked per open *connection* rather
than per in-flight *request* — 256 mostly-asleep threads at c=256. The proposed
fix was a **readiness-gated pool**: a poller thread owns idle connections and
waits on them with one `poll()`, pushes a connection onto the work queue only
when it is actually readable, and a worker runs one dispatch cycle and hands it
straight back. Workers stay ordinary blocking OS threads, so handlers may still
block — the property that makes the pool, not the event loop, the default.

**It was built in full** (poller thread, self-pipe wakeup, `MSG_DONTWAIT`
dispatch cycle, poller-enforced idle sweep, drain-based elastic growth) and it
is **functionally correct**: 256 concurrent connections served by 28 workers +
1 poller (34 threads total vs 256 before), zero persistently-unread Recv-Q,
pipelining and keep-alive intact, clean shutdown, and blocking handlers still
get concurrency (120 blocking handlers grew the pool to 152 threads and all 120
completed).

**It is also 66% more expensive per request, so it was not kept.**

**Machine:** macOS Darwin 25.5.0, 14 logical CPUs, heavily contended — load
average 91–140 and **0.0% idle** for every run below. **Tool:** wrk 4.2.0,
`-t4 -c256 -d10s`, 3 s warm-up, order-swapped A,B,B,A. Metric is CPU-µs per
request (server-process CPU-time delta ÷ completed requests); req/s is not a
valid metric on this box (see Run 3).

| Order | Server | CPU-µs/req |
|---|---|---:|
| 1 | parked-thread pool (kept) | 36.99 |
| 2 | readiness-gated pool | 61.45 |
| 3 | readiness-gated pool | 60.76 |
| 4 | parked-thread pool (kept) | 36.11 |

The parked-thread numbers reproduce Run 3's 35.70/36.16, so the harness is sound.

**Independently reproduced** on a second harness, both binaries rebuilt from the
two branches and confirmed to differ (`cmp`), order-swapped A,B,B,A, load 64–74
at 0.0% idle:

| Order | Server | threads | CPU-µs/req |
|---|---|---:|---:|
| 1 | parked-thread pool | 262 | 36.63 |
| 2 | readiness-gated pool | 34 | 62.03 |
| 3 | readiness-gated pool | 34 | 62.85 |
| 4 | parked-thread pool | 262 | 36.89 |

Same direction, same magnitude (~69%), from a separate measurement script. A
negative result is only worth acting on if it reproduces off its author's
harness — this one does, which is what licenses not rebuilding this design.

The thread counts in that table are the other half of the trade and are worth
reading alongside the CPU column: readiness gating really does deliver what it
promised on thread count (**34 threads for 256 connections, versus 262**). It
simply costs ~70% more CPU per request to get there. That makes it a lever for
a machine where threads or their stacks are the binding constraint, not one for
throughput or latency.

**Attribution — why `kqueue`/`epoll` would not have rescued it.** `poll()` is
O(n) in registered descriptors, so the obvious rebuttal is that the poller, not
the design, is at fault. Re-measured at two connection counts:

| Connections | parked-thread | readiness-gated | penalty |
|---|---:|---:|---:|
| c=32  | 36.01 / 34.28 | 62.73 / 70.46 | ~+31 µs |
| c=256 | 37.41 / 39.26 | 61.66 / 63.17 | ~+24 µs |

The penalty does not grow with the number of polled descriptors — it is
slightly *smaller* at c=256. So it is not the O(n) scan, and swapping in
kqueue/epoll would not recover it. The cost is the **per-request thread
handoff**, which is structural to any readiness-gated pool.

**What the parked-thread pool is actually doing right.** Its per-request path is
close to minimal: the kernel wakes the one thread already blocked in `recv()` on
that socket and copies the data straight into its buffer. One wakeup, no queue,
no lock, no readiness syscall. Readiness gating replaces that single wakeup with
a `poll()` return, poller-side bookkeeping, a mutex + condvar handoff (a *second*
thread wakeup), an extra `EAGAIN` `recv()`, and a re-arm — roughly +25–30 CPU-µs.

**Corollary: the event loop's ~8 µs advantage is not the parked threads.** That
hypothesis is now refuted. The remaining candidates are that the evloop runs the
handler directly on the loop thread with *zero* cross-thread handoff, and its
`SO_REUSEPORT` listener sharding. Any future attempt at closing the gap should
start there — and must not reintroduce a queue between readiness and handler.

The parked-thread pool's real cost is memory and scheduler pressure from holding
a thread per connection (256 threads vs 34), not CPU per request. If that ever
becomes the binding constraint, this trade is worth revisiting — but it is a
trade, not a win.

---

## HTTP benchmark: Run 3 (2026-07-31) — thread pool vs event loop

First run against a harness that measures the routes it drives (see
`bench/tfb/tfb_server.march`) and a compiled server that survives more than one
request. **Read the caveat before quoting the latency column.**

**Machine:** macOS Darwin 26.5.0, Apple M-class, 14 logical CPUs. **Contended** —
load average 4.4 (pool run) / 7.3–8.8 (evloop run), with unrelated processes at
85–102% CPU throughout. **Tool:** wrk 4.2.0, 4 threads, 256 connections, 15 s
captured after primer + warmup.

| Server | Test | Req/s | Avg latency | In-flight (Little's Law) |
|---|---|---:|---:|---:|
| thread pool (default) | JSON | 31,659 | 0.88 ms | **27.9** |
| thread pool (default) | plaintext | 31,788 | 0.88 ms | **28.0** |
| event loop | JSON | 31,769 | 8.04 ms | **255.4** |
| event loop | plaintext | 31,996 | 7.98 ms | **255.3** |
| thread pool | plaintext ×16 pipelined | 482,386 | 0.93 ms | — |
| event loop | plaintext ×16 pipelined | 380,504 | 4.16 ms | — |

**The thread pool is not 9× faster; it is answering 28 of 256 connections.**
`pool_size = ncpus*2` = 28, and a worker owns a connection for its whole
keep-alive lifetime, so 228 connections are accepted by the kernel and never
read. Throughput is identical (~31.8k) because both servers are pinned at the
same external ceiling, but the pool reaches it while serving one ninth of the
offered load. The latency ratio 7.98/0.88 = **9.07** against the served ratio
256/28 = **9.14** is the whole story. The event loop's in-flight figure tracks
offered concurrency (255.3 of 256); the pool's clamps at exactly `pool_size`.
Per *served* connection the event loop is the cheaper of the two, at 15–17%
less CPU per request.

> **Fixed later the same day.** The pool is now elastic — it grows past its
> initial worker count as connections arrive — so the thread-pool rows above
> are a record of the defect, not of current behaviour. Re-measured after the
> fix at c=256: 256 established, **0 unread**, 29,261 req/s, 8.67 ms, **253.7
> in-flight**. The pool's latency now looks like the event loop's because it is
> finally doing the same amount of work. Any future comparison against the
> thread-pool numbers in this table is comparing against a server that was
> answering one connection in nine.

**Req/s here measures the client and the loopback stack, not March.** Both
servers cap at ~31–32k while using under one core of fourteen; a second
independent wrk process raised the aggregate only to 31,243. Every ablation
tried against the thread-pool path — including one doing zero March work —
left req/s flat. **Use CPU-µs per request** for server-side comparisons; the
throughput column is only good for confirming both arms hit the same ceiling.

No Node/Python/Rust columns yet for this run: the Rust actix-web and FastAPI
servers were never in the repo (below), and Node/Python were not re-measured
under the same conditions.

## HTTP benchmark: March vs Rust actix-web 4 vs Python FastAPI

> **The Run 1 and Run 2 tables below are not a valid baseline.** The harness was
> measuring 404 responses, the March server they name is absent from the repo,
> and the compiled HTTP server was itself broken until 2026-07-31. See
> "Runs 1 and 2 are not comparable" at the end of this section before quoting
> any number from it.

### Run 2: 2026-03-25 (batch pipelined writev — evloop handle_read)

**Date:** 2026-03-25 (second run, after Phase 2 batch-writev optimization)
**Machine:** macOS Darwin 24.6.0 (Apple Silicon, 14 logical CPUs)
**Tool:** wrk 4.2.0 — 4 threads, 256 connections, 15s captured run (primer + warmup passes first)
**March:** event-loop server (kqueue + SO_REUSEPORT, 14 threads) + per-thread arena allocator + batch writev in handle_read (N pipelined requests → 1 writev)
**Rust:** actix-web 4.13.0, `--release` (LTO, opt-level 3), 14 workers
**Python:** FastAPI 0.135.2 + uvicorn 0.42.0, uvloop, 14 worker processes

| Test | March | Rust actix-web 4 | Python FastAPI+uvicorn |
|---|---|---|---|
| **JSON** req/s | **52,628** | 46,865 | 46,830 |
| JSON avg latency | 4.84 ms | 5.44 ms | 5.42 ms |
| JSON p99 latency | 5.86 ms | 6.39 ms | 5.97 ms |
| **Plaintext** req/s | **52,812** | 48,384 | 45,963 |
| Plaintext avg latency | 4.84 ms | 5.27 ms | 5.53 ms |
| Plaintext p99 latency | 5.89 ms | 6.37 ms | 7.25 ms |
| **Plaintext pipelined ×16** req/s | 108,572 | **715,186** | 85,409 |
| Pipelined avg latency | 20.40 ms | **3.06 ms** | 24.36 ms |

### vs. Run 1 (pre-Phase-2)

| Metric | Run 1 | Run 2 | Delta |
|---|---|---|---|
| March JSON req/s | 50,270 | 52,628 | **+4.7%** |
| March plaintext req/s | 52,306 | 52,812 | **+1.0%** |
| March pipelined ×16 req/s | 103,611 | 108,572 | **+4.8%** |
| Actix JSON req/s | 46,623 | 46,865 | ±0% |
| Actix plaintext req/s | 47,186 | 48,384 | ±0% |
| Actix pipelined ×16 req/s | 709,265 | 715,186 | ±0% |
| FastAPI JSON req/s | 46,556 | 46,830 | ±0% |
| FastAPI plaintext req/s | 48,068 | 45,963 | ±0% |
| FastAPI pipelined ×16 req/s | 85,866 | 85,409 | ±0% |

### Analysis

**Non-pipelined (JSON/plaintext):** March leads all three frameworks by 8–12%. The event-loop + arena allocator combination eliminates per-request malloc overhead that actix's tokio runtime still pays, and FastAPI's ASGI dispatch adds Python overhead even with uvloop.

**Pipelined ×16 (Phase 2 batch writev):** The handle_read rewrite now batches all N pipelined requests into a single writev() call. This yields +4.8% (103K → 108K req/s), reducing syscall overhead on pipelined connections. The large gap vs actix (715K) persists — actix's tokio `h1` codec is zero-copy through the entire pipeline including the I/O layer, while March still materializes a full `march_response_t` per request. Further gains would require moving to a zero-copy path through the March runtime layer.

**FastAPI multi-worker:** 14 workers with uvloop, on par with March and actix on non-pipelined tests.

### Run 1: 2026-03-25 (initial baseline)

**Date:** 2026-03-25 (first run)

| Test | March | Rust actix-web 4 | Python FastAPI+uvicorn |
|---|---|---|---|
| **JSON** req/s | **50,270** | 46,623 | 46,556 |
| JSON avg latency | 5.08 ms | 5.46 ms | 5.49 ms |
| JSON p99 latency | 5.94 ms | 6.39 ms | 7.38 ms |
| **Plaintext** req/s | **52,306** | 47,186 | 48,068 |
| Plaintext avg latency | 4.87 ms | 5.40 ms | 5.31 ms |
| Plaintext p99 latency | 5.90 ms | 6.34 ms | 5.78 ms |
| **Plaintext pipelined ×16** req/s | 103,611 | **709,265** | 85,866 |
| Pipelined avg latency | 21.31 ms | **3.16 ms** | 24.37 ms |

### How to re-run

```bash
# From repo root — builds bench/tfb/tfb_server.march, verifies its routes, then runs wrk
bash bench/tfb/run.sh march          # March only (default thread-pool server)
bash bench/tfb/run.sh all            # March vs Node vs Node-cluster vs Python
MARCH_HTTP_EVLOOP=1 MARCH_FORCE_REBUILD=1 bash bench/tfb/run.sh march   # event-loop server
```

Servers: `bench/tfb/tfb_server.march` (March, compiled by the harness),
`bench/tfb/node_http.js`, `bench/tfb/node_cluster.js`, `bench/tfb/python_http.py`.
Pipeline script: `bench/tfb/pipeline.lua`.

**The Rust actix-web and Python FastAPI comparisons above cannot currently be
re-run.** The `run_comparison.sh`, `rust_actix/` and `fastapi_server.py` this
section used to point at do not exist in the repository and do not appear
anywhere in its git history — only the numbers they produced were ever
committed. Re-creating those two servers is open work; until then the Run 1 /
Run 2 tables are a historical record, not a reproducible measurement.

### Runs 1 and 2 are not comparable to anything measured after 2026-07-31

Two independent problems invalidate them as a baseline:

1. **The harness was benchmarking 404s.** `bench/tfb/run.sh` drove wrk at
   `/plaintext` and `/json` while its March target was `examples/http_hello`,
   which routes only `GET /`. Both endpoints returned `404 Not Found` with a
   9-byte body. (The Run 1/2 tables name a `bench/tfb/tfb_server` binary that
   is absent, so what they actually measured cannot now be established.)
   `bench/tfb/tfb_server.march` now serves the same two routes as the Node and
   Python servers, and `run.sh` refuses to report numbers if any server under
   test fails a route check.
2. **The compiled server was broken.** Until 2026-07-31 a compiled `HttpServer`
   panicked on the first request, and once that was fixed segfaulted on the
   second (see the 2026-07-31 entry in `specs/progress.md`). Any figure that
   predates that commit was produced by a binary that could not survive two
   requests.

The `/json` figures are further affected: `node_http.js`, `node_cluster.js` and
`python_http.py` used to serialize their JSON body once at startup and write a
pre-baked buffer per request. They now serialize per request, matching what
`tfb_server.march` does via `Json.to_string`, so the JSON test exercises a
serializer in all four servers rather than only in March.

---

## bench/hash_map_bench.march — HashMap + Enum.uniq/frequencies (O(n) proof)

**Command:** compile with `--opt 2`, run directly (includes internal timing via
`System.monotonic_time()`).

```bash
march --compile --opt 2 bench/hash_map_bench.march -o bench/hash_map_bench
bench/hash_map_bench
```

Three workloads at three scales (10 k / 50 k / 100 k elements):

| Workload | What it exercises | Checksum |
|----------|-------------------|---------|
| HashMap raw put/get | HAMT insert + lookup over unique Int keys | sum of values |
| Enum.uniq | dedup 50%-duplicate list via HashMap membership | unique count |
| Enum.frequencies | count 10-repeat list via HashMap + order list | total count |

**Baseline results (2026-06-24, Apple M-class, --opt 2):**

```
=== HashMap raw put/get ===
  n=10000  27ms  (check=149985000)
  n=50000 161ms  (check=3749925000)
  n=100000 367ms  (check=14999850000)
=== Enum.uniq ===
  n=10000  13ms  (check=5000)
  n=50000  84ms  (check=25000)
  n=100000 193ms  (check=50000)
=== Enum.frequencies ===
  n=10000  23ms  (check=10000)
  n=50000 150ms  (check=50000)
  n=100000 323ms  (check=100000)
```

Times grow ~linearly (10× elements ≈ 14× time), consistent with O(n·log₃₂ n)
HAMT operations (effectively O(n) at these scales).  The previous O(n²)
`Enum.frequencies` at n=100k would do ~2.5 billion list-scan steps; this does
100k HashMap lookups.

**What to watch:** a regression here suggests a change to HashMap's HAMT core,
the `hash` builtin dispatch, or Perceus RC paths for `HEntry` nodes.

---

## bench/rrb_bench.march — RRB.Vec + Parallel bulk operations (n=1M)

**Command:** compile with `--opt 2`, run directly.

```bash
march --compile --opt 2 bench/rrb_bench.march -o bench/rrb_bench
bench/rrb_bench
```

Four workloads over n=1,000,000 integers:

| Workload | What it exercises | Expected result |
|----------|-------------------|-----------------|
| `RRB.fold_left` (sequential) | Array-trie-backed Vec traversal | `500000500000` |
| `Parallel.psum` | `task_spawn`/`task_await_unwrap` integer reduce | `500000500000` |
| `Parallel.preduce` (square+sum) | Parallel map-reduce pass | `333333833333500000` |
| `Parallel.pmap` (n=1000) | Vec-building tasks, small n to avoid O(n²) list-push | `333833500` |

**Baseline results (2026-06-24, Apple M-class, no --opt):**

```
seq_sum=500000500000  seq_fold_left: 8ms
par_sum=500000500000  psum: 86ms
par_reduce_sum=333333833333500000  preduce: 87ms
par_map_sum=333833500  pmap+fold (n=1000): 5ms
```

**Note on `pmap` scale:** these baseline numbers predate `RRB.Vec` v2
(`stdlib/rrb_vec.march`), which is now backed by `Array`'s 32-way trie —
`push` is O(1) amortised, not the O(n) of the original list-backed v1 that
motivated capping this workload at n=1000. The n=1000 cap and "verifies
correctness of the task return path only" framing are stale; re-measure at
n=1M before trusting this note.

**What to watch:** `psum` and `preduce` correctness depend on `task_await_unwrap`
correctly double-untagging i64 task results (`lib/tir/llvm_emit.ml`). If results
are `2×correct+N` the i64 double-untagging is broken. A `psum` that is slower
than `seq_fold_left` by more than 3× (on a multi-core machine) suggests the
parallel scheduler is degraded.

---

## bench/json_stream.march — JsonStream chunked NDJSON tokenizer (20,000 records, tiny tokens)

**Command:** compile with `--opt 2`, run directly.

```bash
march --compile --opt 2 bench/json_stream.march -o bench/json_stream_bench
bench/json_stream_bench
```

Builds 20,000 synthetic NDJSON records (`{"id": N, "name": "user-N", "active":
true, "tags": [1, 2, 3]}\n`) into one in-memory source string, then feeds it
to `JsonStream.start_ndjson()`/`feed`/`finish` in 64KB chunks — exercising the
`JsonStream.feed` per-byte tokenizer loop, per-token event allocation, and RC
churn on the chunk-slice `String` pieces passed across `feed` calls.

Each record emits 14 events (`EvObjStart`, `EvKey`×4, `EvNum`/`EvStr`/`EvBool`
scalars, `EvArrStart`, `EvNum`×3, `EvArrEnd`, `EvObjEnd`) — measured
empirically with 1/2/3-record probes (14, 28, 42 events), not derived from
prose arithmetic. Expected checksum: `20000 × 14 = 280000`.

This corpus is **tiny-token**: keys are 2-6 bytes, values ~11 bytes. It is
deliberately unfavorable to any fix that only speeds up long runs (see the
companion string-heavy corpus below) — a 2-6 byte token has almost no run to
slice, so this is where a per-*token* overhead (as opposed to a per-*byte*
overhead) would show up as a residual gap.

**Phase 1 baseline results (2026-07-31, Apple M-class, `--opt 2`):**

```
checksum=280000
ms=224-229 (three runs)
maximum resident set size: ~85 MB (85016576-85049344 bytes)
```

**10× spot-check (n=200,000, same 64KB chunk size):**

```
checksum=2800000
ms=2373
maximum resident set size: 840138752 bytes (~801 MB)
```

RSS grew ~9.9× against a 10× input-size increase (baseline ~82 MB above the
~3 MB empty-program floor; 10× run ~837 MB above floor) — i.e. RSS tracks the
size of the in-memory source string the benchmark holds by construction, not
the record count independent of that. This is consistent with the
constant-memory claim for the parser itself: the benchmark's own input
buffer is O(records), but nothing in `JsonStream`'s chunk-fed state
(`JsState`) accumulates unboundedly across `feed` calls — only the per-chunk
event list and in-flight partial-token buffer are live at any point.

**Phase 2 run-slicing results, tiny-token corpus (2026-07-31, order-swapped
arms, same session as the string-heavy A/B below):**

```
JsonStream: 219 ms / 234 ms
Json.parse: 71 ms / 77 ms
=> ~3.05x (was ~3.6x pre-run-slicing, per specs/2026-07-31-json-streaming-phase2-design.md's "Why" section)
```

Run-slicing (Components 1-2 of
`specs/2026-07-31-json-streaming-phase2-design.md`) narrows but does not
close the gap on this corpus, because there is very little run here to slice
— see the string-heavy corpus below, where the same fix nearly eliminates
the gap. **This residual ~3x is per-*token* overhead** (state-machine
transitions, event-list allocation, a cons + a join even for a
single-content-byte-run), not scanning throughput; a byte-set scanner cannot
speed up a 4-byte `memchr` call, so this corpus is why Component 4 (SIMD) is
closed rather than built — see the verdict below.

**What to watch:**
- If `bench/json_stream.march`'s checksum ever moves off `records × 14` at
  this record shape, that is a tokenizer regression, not a benchmark
  artifact — recompute the empirical per-record count with a 1/2/3-record
  probe before assuming the benchmark itself needs adjusting.
- RSS should stay flat (modulo the input string itself) as record count
  grows at fixed chunk size — re-run the 10× spot-check after any change to
  `feed`/`finish`/the builder drivers and confirm the delta still scales
  with input-string size, not superlinearly.
- **A regression on this corpus specifically (not the string-heavy one
  below) points at per-token overhead** — the state machine in
  `JsonStream.feed`, event-list (`List(Event)`) allocation, or the cons/join
  pair paid even for a single-byte run — since run-slicing has little to win
  here already. Component 5 (`feed_fold`, phase 2 design) is the open item
  that would address this; it is not built.

---

## bench/json_stream_strings.march — JsonStream vs Json.parse, string-heavy corpus (2,000 records)

**Command:** compile with `--opt 2`, run directly.

```bash
march --compile --opt 2 bench/json_stream_strings.march -o bench/json_stream_strings_bench
bench/json_stream_strings_bench
```

Builds 2,000 NDJSON records, each `{"s": "<~1000-byte escape-free payload>"}\n`
— a single content-bearing string field per record, no escapes, no nesting —
then times `JsonStream.start_ndjson()`/`feed`/`finish` over the whole
concatenated source (64KB chunks) against `Json.parse` called once per
record, in the same process. This is the corpus the tiny-token benchmark
above cannot exercise: long, escape-free runs, which is what run-slicing
(Components 1-2) targets and what the phase 1 per-byte accumulation cost the
most on.

Each record emits 4 events (`EvObjStart`, `EvKey("s")`, `EvStr`, `EvObjEnd`).
Expected checksums: `stream_events=8000` (2000 × 4) and `parse_len=2000000`
(2000 × 1000-byte payload) — both are correctness checks, not timings.

**Phase 1 (pre-run-slicing) vs phase 2 (run-slicing) results, interleaved
same-session A/B (2026-07-31, 3 rounds, commit `8a79a275` = phase 1 /
`4afc215d` = phase 2):**

```
BEFORE (8a79a275, per-byte accumulation): JsonStream 322 / 348 / 364 ms; Json.parse 6-25 ms  => ~55x slower
AFTER  (4afc215d, run-sliced):            JsonStream 6 / 6 / 6 ms;       Json.parse 6 / 6 / 6 ms  => 1.0x, PARITY
```

Run-slicing takes JsonStream from ~55× slower than `Json.parse` to parity on
this corpus — confirming the phase 2 design's diagnosis that the tiny-token
gap (above) was materialization (per-byte allocation), not scanning: the two
scan identically, and the only thing that changed here is whether a run
becomes one slice or N one-byte strings plus N cons cells.

**Load caveat — read before trusting an absolute ms figure.** All of the
above numbers, and the tiny-token numbers above them, were taken on a machine
running other concurrent sessions in this worktree set, with reported load
averages of 43-97 on a 14-core machine at measurement time. Absolute
milliseconds from this session are **not comparable** to absolute
milliseconds from any other session, and should not be read as a clean,
reproducible baseline — a quiet-machine re-run would show different absolute
numbers. What *is* sound is the **ratio within an interleaved round**:
compared arms (before/after, or JsonStream/Json.parse) ran back-to-back
under the same load, so a shared load spike inflates both arms together and
the ratio between them stays meaningful even though neither absolute number
does. Re-run on a quiet machine before citing an absolute ms figure from
this benchmark in anything other than a ratio.

**What to watch:**
- A regression specifically on *this* corpus (not the tiny-token one above)
  and not on `Json.parse`'s own benchmarks points at run-slicing having
  regressed to per-byte accumulation — check `str_byte`'s `SPlain` path and
  `num_byte` in `stdlib/json_stream.march` first.
- `stream_events`/`parse_len` moving off `8000`/`2000000` is a correctness
  regression in the tokenizer or `Json.parse`, not a benchmark artifact.

---

## Running benchmarks to validate changes

See also the note in `CLAUDE.md`: run the relevant benchmark after any change
to the features it exercises. Quick reference:

| Changed area | Run this benchmark |
|---|---|
| `lib/tir/perceus.ml` (any) | `tree_transform` + `binary_trees` |
| FBIP / `try_fbip_sink` / `shape_matches` | `tree_transform` |
| ECase / scrutinee dec_rc | `binary_trees` |
| Closure / lambda eval | `list_ops` |
| Tail-call optimisation | `list_ops` + `fib` |
| Codegen / `--opt` levels | all four |
| `string_join` / `string_to_int` / `int_to_string` | `string_build` + `string_pipeline` |
| Task / `task_spawn` / `task_await` | `parallel` + `par_fib` + `par_map` |
| Work-stealing / `task_spawn_steal` / Chase-Lev | `par_worksteal` |
| `Cap(WorkPool)` capability | `par_worksteal` |
| `Deque.*` / Cons allocation / RC amortised | `deque_ops` |
| `Merkle.*` / `Crypto.sha256` / TVar equality | `merkle` |
| `llvm_emit` equality dispatch (TVar / `march_poly_eq`) | `merkle` |
| `HashMap.*` / `Enum.uniq` / `Enum.frequencies` | `hash_map_bench` |
| `RRB.*` / `Parallel.*` / `task_await_unwrap` i64 | `rrb_bench` |
| `lib/tir/trmc.ml` / TRMC / `lib/tir/perceus_fbip.ml` | `list_producers` |
| `lib/tir/repr.ml` / value representation / `llvm_field_ty` | `vector_math` |
| JsonStream / streaming JSON | `json_stream` (tiny-token), `json_stream_strings` (string-heavy) |
| actor / mailbox / scheduler / supervision changes | `scripts/actor-load.sh` (all four scenarios: `fanin`, `churn`, `callstorm`, `crashloop`) |
| interpreter (`lib/eval/eval.ml`) / REPL-JIT (`lib/jit/`) changes | `bench/run_interp_bench.sh` (interp vs. compiled vs. repl-clang vs. repl-orc A-B over `bench/interp/`) |
