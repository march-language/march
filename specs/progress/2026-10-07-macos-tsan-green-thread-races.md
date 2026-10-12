# `MARCH_SANITIZE=thread` on macOS reports races in `march_decrc` across green threads

Logged 2026-10-07 while fixing the macOS ASAN hang
(specs/progress/2026-10-07-macos-asan-hang.md). Until then TSAN never got past
startup on macOS 26 (Apple clang 17's TSAN runtime segfaults); with the driver now
falling back to Homebrew LLVM 22, it runs.

`test/native/hof_spec_closures.march` is clean. `actor_counter.march` (11 reports) and
`nativearray_builtin_borrow_leak_probe.march` (53) abort with "data race" between a
plain read in `march_decrc` (runtime/march_runtime.c ~606) on one scheduler thread and
the atomic write at ~610 on another, under `actor_green_thread` / `proc_trampoline`.

The scheduler already has TSAN fiber annotations (`MARCH_TSAN_SWITCH_TO_*`,
runtime/march_scheduler.c), so this is not obviously an annotation artifact. The read at
~606 is the immortal-cell check, a plain `((march_hdr *)p)->rc >= MARCH_RC_IMMORTAL`
load of a word other threads update with `atomic_fetch_sub`. That is a C11 data race
(benign in practice: the load only compares against the immortal threshold), and TSAN is right to flag it.
Likely fix: make it an `atomic_load_explicit(..., memory_order_relaxed)` (and audit the
same pattern in `march_incrc` and the other rc readers), then re-run the three programs
under `MARCH_SANITIZE=thread` on macOS to see what is left.

## Fixed 2026-10-11

**The plain reads are now relaxed atomic loads.** `runtime/march_runtime.h` gains
`march_rc_peek(p)` (`__atomic_load_n(&hdr->rc, __ATOMIC_RELAXED)`), next to
`march_rc_is_unique`. Every read of a count another thread may be RMW-ing goes through
it: the immortal checks in `march_decrc`, `march_decrc_freed`, `march_clo_release`,
`march_decrc_local`, `march_decrc_local_freed` and `march_free`, plus `march_free`'s
`MARCH_RC_CHECKS` shared-object test and its diagnostic print.

**Audit of the other readers.**
- `march_incrc` / `march_incrc_local`: no plain read; the increment is a relaxed RMW (the
  `_local` forms take the atomic path on any scheduler thread, which includes compiled
  `main`).
- The non-atomic `h->rc--` / `rc++` in the `_local` forms run only off the scheduler with
  `march_tls_concurrent_rc` clear, i.e. single-threaded; unchanged.
- `march_rc_is_unique` (FBIP / in-place writes): already an acquire load, and the LLVM
  emitter's mirror (`llvm_emit_alloc.ml`, `llvm_emit_simd.ml`, `llvm_case.ml`) is
  `load atomic i64 ... acquire`.
- The inline RC twins the compiler emits (`lib/tir/llvm_rc_inline.ml`): the immortal check
  is already `load atomic i64 ... monotonic` (= C11 relaxed), so no change. Those twins are
  not used in sanitizer builds at all (the driver turns them off), which is why TSAN only
  ever saw the runtime's own read.
- `runtime/march_gc.c` (per-process heap compaction, single-threaded) and the
  `march_extras.c` record-shape panic message: not shared-object paths; left alone.

**Cost: none.** The non-sanitized code for `march_decrc`, `march_decrc_local`,
`march_decrc_freed` and `march_incrc` in `bench/binary_trees` compiled `--opt 2` is
instruction-for-instruction identical between origin/main and this change (otool,
addresses masked): a relaxed 64-bit load is the same `ldr` as the plain one on arm64.
Timings (9 interleaved runs, load average ~16, so noise dominates): `list_ops` median
38.8 ms base vs 40.1 ms fix; `binary_trees` 60.5 vs 67.0, with the fix's runs spread
60.0 to 96.2. Identical machine code means these differences are load.

**TSAN results (macOS 26, M3, Homebrew LLVM 22.1.8, `TSAN_OPTIONS=halt_on_error=0`).**
The reports this file was filed for did not reproduce on 2026-10-11, before or after the
change: 0 `WARNING: ThreadSanitizer` across 15 runs each of `actor_counter`,
`nativearray_builtin_borrow_leak_probe` and `hof_spec_closures` on origin/main (a937a9c0b),
3 runs each with a compiler built from 975bb7353 (the commit that filed this), 11 runs each
with the fix, and 1 run of the leak probe at `MARCH_NUM_SCHEDULERS=14`. The binaries are
instrumented (`march_decrc` calls `__tsan_read8` before the change and
`__tsan_atomic64_load` after). So the race is intermittent on this host; the fix removes it
by construction (TSAN never reports a race between two atomic accesses), but there is no
before/after report count to quote.

**What TSAN does show instead: a TSAN-only wedge.** `actor_counter` hangs at exit in
about a third of TSAN runs, `actor_monitor_down_reason` in 4 of 11, and
`run_until_idle_ping_pong` at 14 schedulers in 11 of 11, all with no report. `actor_counter` wedges on origin/main, with this change and at
975bb7353 alike. It does not happen without TSAN, or under ASAN.
Filed separately: `specs/progress/2026-10-11-macos-tsan-scheduler-wedge.md`.
