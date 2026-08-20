# The ASAN gate now covers SIMD / narrow-width `NativeArray` / array-backed `Bytes`

Landed 2026-08-20. Pre-0.3.0 release hardening.

## The gap

`specs/lang/golden/sanitize.sh` swept exactly one corpus — `for f in "$here"/*.march`,
i.e. the 47 programs in `specs/lang/golden/`. That corpus contains **zero**
SIMD/NativeArray/Bytes programs:

```
$ grep -rliE 'simd|nativearray|native_arr|Bytes\.|f32|i32|u8' specs/lang/golden/*.march
$          # no output
```

Meanwhile `test/native/` holds ~27 SIMD / NativeArray-narrow-width /
array-backed-Bytes fixtures that `dune runtest` compiles and runs on both OSes —
but never under a sanitizer. So every raw-memory path in that area (native
`<4 x float>` loads/stores, narrow `i8`/`i16`/`i32` element access, `Bytes`'
array backing) had real correctness coverage and no memory-safety coverage.

## What changed

`sanitize.sh` now sweeps **two** corpora, labelled separately in the output so a
failure names the corpus it came from:

```
=== golden sanitize: 47 clean, 0 failed (of 47 programs) ===
=== native sanitize: 24 clean, 0 failed (of 24 programs) ===
=== sanitize TOTAL: 71 programs swept — 71 clean, 0 failed ===
```

The second corpus is a curated, explicitly-named list of 24 `test/native/*.march`
fixtures, not a glob and not new goldens. The reasoning is written into the
script header so it survives the next round of tidying; in short:

- `specs/lang/golden` is **also** the cross-compile oracle corpus
  (`test/test_oracle.ml` narrows to `examples/ + specs/lang/golden/` in cross
  mode), so a SIMD program dropped in there would additionally be cross-compiled
  to linux/amd64 and differentially diffed — dragging arm64-vs-x86_64 vector
  codegen into an unrelated change.
- `specs/lang/golden/INDEX.md` pins the corpus count and `scripts/check-docs.sh`
  Check C enforces it.
- A glob over `test/native` would pull in 165 fixtures including deliberately
  non-terminating, panic-asserting, FFI-shim and `--target js` programs.

The precedent followed is `test/test_oracle.ml`'s own `test_native_allowlist`,
which pulls named `test/native/` programs into its sweep for the same reasons.

Three further hardening changes, all aimed at the same failure mode — a gate that
reports success without having run:

1. The script prints the **program count it actually swept** and exits 2 if that
   count is 0. A green exit code alone was never evidence: the Darwin branch
   exits 0 having compiled nothing when CrowdStrike Falcon is present.
2. That Darwin skip now says so out loud — `*** 0 programs compiled, 0 run —
   this is a SKIP, not a pass. ***`.
3. A curated name that no longer resolves to a file is a **hard error**, not a
   silent skip, so a fixture rename cannot quietly shrink the gate to nothing.
   (`test_oracle.ml`'s allowlist filters missing entries instead — right for a
   sweep that prints per-file verdicts, wrong for a pass/fail gate.)

## Exclusions, and why

Not every SIMD/NativeArray fixture is eligible; the excluded ones are listed in
the script with reasons so they are not re-added:

- `simd_bounds_panic`, `simd_lane_panic`,
  `native_arr_map2_inline_length_panic` — assert a runtime panic, i.e. a
  non-zero exit **by design**. The runner treats non-zero as failure, and
  relaxing that would blind it to the crashes it exists to catch.
- `simd_leak_probe` (~2,000,000 calls), `native_arr_fold_leak_probe`
  (2 × 4,000,000-element folds) — chosen for exclusion rather than raising the
  timeout. They are `live_allocs()` **leak** probes and this gate runs with
  `detect_leaks=0`, so ASAN adds nothing to what they already assert, while
  their iteration counts are the one thing that could blow the wall-clock bound.
- `peak_rss` — asserts an RSS band that ASAN's shadow memory and redzones
  invalidate by construction.

Excluding those two probes is what keeps the standard 25s per-program hang
backstop valid for the native corpus: measured under ASAN on linux/arm64, the
slowest curated program runs in **0.06s**. The sweep's cost is compile time, not
run time.

## Verification

Local macOS runs of this gate are worthless — ASAN binaries hang under
CrowdStrike Falcon, confirmed here down to a two-line C `printf` program built
with plain `clang -fsanitize=address` (30s alarm, rc=142). Everything below was
measured in a Linux container built from `ci/Dockerfile.ubuntu` (linux/arm64,
14 CPUs), which is the environment the gate actually runs in.

| measurement | wall time |
|---|---|
| old gate (golden only), cold cache | 119s |
| new gate, CI phase 1 (plain), cold cache | 156s |
| new gate, CI phase 2 (`MARCH_TRMC=1`), same tree | 153s |
| **both CI phases** | **309s (5m09s)** |

The addition costs **+37s (+31%)** on phase 1. The job's ceiling is
`timeout-minutes: 30` with 15 minutes per step, so both phases fit with wide
headroom even allowing for GitHub's smaller runners. Phase 2 is not meaningfully
cheaper than phase 1, which confirms `MARCH_TRMC` is part of the CAS cache key —
it gets its own artifacts rather than reusing phase 1's.

**Red proof.** A gate that cannot fail has added nothing. A scratch copy of
`native_arr_narrow.march` (one of the newly-covered fixtures) with a single
index changed — `NativeArray.get_u8(a, 2)` → `get_u8(a, 64)` on a 3-element
array — makes the sweep fail, exit 1:

```
  [native/zz_asan_red_proof] SANITIZER FAIL (rc=1)
    ==1223==ERROR: AddressSanitizer: heap-buffer-overflow ... READ of size 1
        #0 native_u8_arr_get
        #1 march_main
    0x504000000070 is located 61 bytes after 35-byte region [0x504000000010,0x504000000033)
    allocated by thread T0 here:
        #0 calloc
        #1 march_alloc
        #2 native_arr_alloc march_runtime.c
        #3 native_u8_arr_make
=== native sanitize: 24 clean, 1 failed (of 25 programs) ===
=== sanitize TOTAL: 72 programs swept — 71 clean, 1 failed ===
```

The scratch fixture lived only inside the container; the repo was mounted
read-only and never carried it.

This works because `march_alloc` is a straight `calloc` per object
(`runtime/march_runtime.c:286`), so ASAN's malloc interceptor gives every March
heap object its own redzones. A bump/arena allocator would have made March-heap
overruns invisible to ASAN.

One caveat surfaced in the reports: ASAN prints
`WARNING: ASan doesn't fully support makecontext/swapcontext functions and may
produce false positives in some cases!` because the scheduler runs green threads
on `ucontext`. No false positive was observed — the actor-bearing goldens and
`simd_actor_msg` are all clean — but it is the first thing to check if this gate
ever goes red on a scheduler-heavy program.

## A real bug found along the way

Building the red proof surfaced a genuine memory-safety hole, filed as
`specs/todos/2026-08-20-nativearray-get-set-unchecked-oob-compiled.md`:
**compiled `NativeArray.get_*`/`set_*` do no bounds check at all**, across all
five element families, so safe March code can read and write arbitrary heap
memory with an out-of-range index. The interpreter checks and panics, the stdlib
docs promise a panic, and `Bytes.get` gets it right — only the compiled
`NativeArray` path is unguarded.

Note this is *not* something the extended sweep finds on its own: every fixture
in the corpus indexes in range. The gate reproduces it only once a program
actually goes out of bounds, which is exactly what the red proof does.
