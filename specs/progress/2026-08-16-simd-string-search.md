- ✅ **SIMD literal scan for `String.index_of`/`index_of_from`/`contains`**
  (`specs/plans/2026-08-09-parsing-and-string-search.md` §10 step 4).

  `march_memmem`'s helper in `runtime/march_runtime.c` previously called libc
  `memchr` to find candidate first-byte positions, then `memcmp` to confirm —
  correct and already SIMD-accelerated *inside libc*, but not a kernel this
  codebase wrote or controlled, unlike the hand-written NEON/SSE kernels
  elsewhere in the runtime (`march_http_parse_simd.c`'s SSE4.2 PCMPESTRI path,
  the compiled `Bytes<->u8`/`Simd` fold kernels from #273).

  Replaced the `memchr` call with a hand-written `march_simd_memchr`:
  broadcast the target byte across a 16-byte vector register, compare against
  64-byte chunks (4 lanes) at a time, and use a cheap "any lane matched"
  reduction (`_mm_movemask_epi8`/`vmaxvq_u8`) before paying for exact-position
  extraction — only entered on an actual hit. Two real implementations:

  - `__SSE2__` (x86-64 ABI baseline — no `-msse4.2`/`-mavx` flag needed,
    unlike `march_http_parse_simd.c`'s SSE4.2 path)
  - `__ARM_NEON`/`__aarch64__` (AArch64 ABI baseline — always available on
    both CI platforms, macos-15 arm64 and any aarch64 Linux target; see
    `bin/main.ml`'s `arch_cflags`, which passes `-msse4.2` only for
    `X86_64`/`Native` and leaves arm64 flag-less)

  Anything else (32-bit ARM without NEON, WASM) falls back to plain libc
  `memchr`, unconditionally correct.

  The rest of `march_memmem`'s control flow (candidate-then-memcmp,
  resume-at-hit+1 on a failed candidate to catch overlapping needles like
  `("aaaa", "aa")`) is untouched, so byte-for-byte behavior — empty-needle
  match at the clamped start, `index_of_from`'s negative/out-of-range `start`
  clamping, needle-longer-than-haystack, embedded NUL bytes (March strings
  are length-counted, not NUL-terminated) — is unchanged by construction: the
  SIMD kernel only ever replaces "find the next occurrence of one byte."

  **First attempt was a regression, not a win.** A naive 16-bytes-per-iteration
  NEON loop that unconditionally extracted two 64-bit lane words and ran
  `ctzll` on both every iteration measured ~45% *slower* than libc `memchr` on
  Apple Silicon — Apple's `memchr` is itself a heavily tuned wide-chunk
  kernel, and the naive per-16-byte reduction overhead dominated. Widening to
  64-byte (4-lane) chunks with a `vmaxvq_u8`-gated "any hit" test before doing
  the precise extraction turned that into a ~30% *improvement* over the old
  `memchr`-based baseline. Lesson: "hand-written SIMD" is not automatically
  faster than a good libc implementation; the reduction shape matters as much
  as the vector width. (See `project_bench_first_position_warmup.md` and
  related measurement-apparatus memory entries for the general pattern of
  "measured, not assumed.")

  **Tests:** `test/native/string_search_edge_cases.march` (new, compiled-only
  — the interpreter has a separate OCaml implementation in `lib/eval/eval.ml`
  that never touches `march_memmem`, so a `test/stdlib/` fixture run through
  `test_stdlib_march.exe` would not exercise this kernel at all). Confirmed
  green against the OLD `memchr`-based implementation first (TDD), then
  against the new kernel. Covers: short (<16-byte) and long (>16-byte,
  forcing the vector loop) haystacks; a needle match straddling a 16-byte
  window boundary; many repeated first-byte candidates before the real match
  (exercises the resume-at-hit+1 path across a SIMD window); overlapping
  needle/haystack repeats; embedded NUL bytes, including past the 16-byte
  SIMD boundary; `index_of_from`'s full clamping contract (negative start,
  past-end start, empty needle at a clamped start); needle longer than
  haystack. Wired into `test/dune` as a native golden-diff rule
  (`native_string_search_edge_cases`), so it runs under `scripts/run-tests.sh`
  going forward. Also cross-compiled the runtime for `x86_64-linux-gnu` via
  `zig cc` to confirm the SSE2 path compiles cleanly (this Mac is arm64, so
  it never exercises the SSE2 branch natively).

  **Benchmark:** `bench/scratch_string_memmem.march` (ad hoc, not wired into
  the permanent suite — `bench/string_scan.march` already exists but its 1MB
  buffer is too fast, ~10-12ms, for `/usr/bin/time` to distinguish before/after
  cleanly). 32MB haystack, `String.repeat("abcdefghij", 3_200_000)`, 20
  iterations each of an absent-needle scan (full O(n) miss) and a
  near-end-of-buffer match. Compiled `--opt 2`, before/after built by
  swapping `runtime/march_runtime.c` between `git show HEAD:...` and the new
  version and rebuilding (`dune build --root . _build/default/runtime/march_runtime.c bin/main.exe`
  — a targeted `dune build bin/main.exe` alone does NOT restage the runtime
  the compiler links, per this repo's CLAUDE.md CAS-cache note). Checksums
  identical before/after (`135000150` on `bench/string_scan.march`,
  confirming no behavior change); wall-clock on this Apple Silicon Mac:
  absent-scan ~12.3ms (old, memchr-based) → ~8.7ms (new, SIMD kernel), late
  match ~11.9ms → ~8.4ms — roughly 30% faster.

  ASan verification (`specs/lang/golden/sanitize.sh`) could not run on this
  dev box: CrowdStrike Falcon (an EndpointSecurity system extension) hangs
  ASan's shadow-memory mmap setup on *any* binary, even a no-op
  `println("hi")` program — confirmed pre-existing and unrelated to this
  change by reproducing the identical hang on an unmodified trivial program.
  `sanitize.sh` self-detects this and skips with an explanatory message; CI
  (no Falcon) covers the ASan gate.
