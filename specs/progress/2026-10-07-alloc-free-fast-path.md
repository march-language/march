# DONE Cheaper per-object allocation and free (binary-trees)

Done 2026-10-07. Follows `specs/progress/2026-10-07-owned-call-drop-fusion.md`
and `specs/todos/2026-08-04-x86-benchmark-findings.md` (section 2, binary-trees),
which stays open for its other findings.

## The problem

With the drop pass fused away, a `sample` profile of `bench/binary_trees.march`
(depth raised to 20, `--opt 2`) still spent a large share outside `make`/`check`,
in the fixed per-object cost of the runtime:

- `_tlv_get_addr`, three times per object on macOS: once for the live-object
  gauge in `march_alloc`, once for it again in `march_rc_last_atomic`, and once
  inside `mi_malloc` for mimalloc's thread-default heap. On Darwin every
  `_Thread_local` access is a call.
- `mi_is_in_heap_region`, the provenance test in `march_free_any` that decides
  whether a `free()` goes to `mi_free` or libc `free`.
- `OUTLINED_FUNCTION_n` stubs inside `mi_free` and `mi_malloc`: Apple clang's
  AArch64 machine outliner is on at `-O2` and turns runs of the hottest code into
  `bl`/`ret` round trips.
- Stack frames in `march_alloc` (ten registers, from an inlined `gc_emit`) and in
  `march_rc_last_atomic` (for destructor and underflow calls it almost never
  makes).

## What changed

1. **Live gauge via the pthread TSD, read directly (macOS).** The per-thread slot
   pointer is now stored only under `march_live_key` and read as `tsd[key]`, the
   array whose base Darwin keeps in `TPIDRRO_EL0` (arm64) or `GS` (x86_64). That is
   what `pthread_getspecific` itself does on Darwin, and what mimalloc reads its
   thread id from. `march_live_key_init` self-checks the direct read against a
   sentinel once and falls back to `pthread_getspecific` for good if it ever
   disagrees. The read is `asm volatile` so it is never CSE'd across a call (a
   call can be a green-thread switch to another OS thread). Linux keeps the
   `_Thread_local`, which is a thread-pointer-relative load there. Counting is
   unchanged: every alloc and free still bumps, so `live_allocs()` and the
   observe snapshot's `live_objects` are exact as before.
2. **mimalloc's heap lookup via TSD slot 89 (macOS).** The driver passes
   `-DMI_TLS_SLOT=89` with the mimalloc flags on a macOS host. This is mimalloc's
   own macOS configuration whenever it overrides malloc (`prim.h`,
   `MI_MALLOC_OVERRIDE`); slot 89 is libpthread's `__PTK_FRAMEWORK_OLDGC_KEY9`,
   unused since the Objective-C GC was removed. No vendored source is modified.
3. **Inline provenance fast path.** `march_free_any` / `march_realloc_any` first
   test the pointer against the bounds of mimalloc's first arena (`mi_arena_area(1)`,
   learnt lazily on the first slow-path hit). For a pointer in that arena,
   `mi_is_in_heap_region` answers yes by exactly that comparison
   (`_mi_arena_contains`), so the answer never changes, only its cost. The bounds
   start as the empty range `[UINTPTR_MAX, 0)`, so a racing reader that sees only
   one of the two relaxed stores still sees an empty range and falls back. No
   allocation site was moved: this deliberately does NOT route anything to
   `mi_free` without the provenance test (strings are still libc `malloc`, see
   below).
4. **Frameless hot tails.** `march_run_resource_dtor`, the string-stats tally and
   the underflow reports are now out of line behind one inlined `tag < 0` test
   (only the reserved negative tags, String/Resource/Task, ever did any work there),
   and `march_rc_last_atomic`/`_local` reach every slow case by a tail call, so the
   constructor-cell case runs with no stack frame and tail-calls `mi_free`.
   `march_alloc`'s string-stats and GC-trace work moved to a cold function behind
   one combined test of the two state words (both -1 once resolved off; anything
   else still runs the lazy init and the work, so `MARCH_STRING_STATS` and
   `MARCH_TRACE_GC` behave as before: verified identical `obj_allocs`, `live_objs`
   and trace event counts against the base).
5. **`-mno-outline` on arm64.** Added to the arm64 `arch_cflags` (runtime and the
   generated `.ll`; the program's own code had no outlined calls). It changes the
   Stage A object-cache key automatically (it keys on cflags).

## Measurements

Same box (Apple M3 Max), base = `origin/claude/owned-call-drop-fusion` (9dec7f999)
compiler and runtime vs this branch, `--compile --opt 2`, interleaved runs,
outputs byte-identical. The box was heavily loaded by other sessions (1-min load
average 17 to 50), which wrecked wall-clock times, so child CPU time (user+sys)
is the figure quoted; wall-clock minima move the same way where they are readable.

Incremental, `binary_trees` at depth 18 (CPU ms, 11 runs each, one interleaved
round; each row adds to the one above):

| step | CPU min | CPU med |
|---|---|---|
| base | 742.8 | 759.4 |
| 1. live gauge via direct TSD | 676.7 | 707.0 |
| 2. mimalloc `MI_TLS_SLOT=89` | 587.3 | 618.4 |
| 4a. out-of-line dtor/stats behind `tag < 0` | 593.5 | 617.1 |
| 3. first-arena provenance fast path | 537.5 | 578.6 |
| 4b. `march_alloc` cold note path | 539.4 | 573.7 |
| 4c. frameless last-free tails | 534.0 | 546.1 |
| 5. `-mno-outline` | 464.5 | 496.2 |

Step 4a alone is flat; it is kept because 4c (a frameless tail) depends on it.
Step 4b looked like 1-3% at this point but is worth more in the final build: the
final branch against the final branch with only `march_alloc` reverted was
486.9 vs 524.0 ms CPU median (15 runs), so it stays.

Final A/B (CPU ms, min / median):

| bench | base | this branch | n |
|---|---|---|---|
| binary_trees 15 | 65.3 / 72.0 | 45.4 / 50.8 (-29%) | 11 |
| binary_trees 18 | 714.9 / 734.9 | 452.5 / 488.2 (-34%) | 11 |
| list_ops | 31.6 / 34.5 | 27.1 / 27.8 (-19%) | 11 |
| tree_transform | 617.9 / 685.7 | 634.4 / 666.8 (flat, noise) | 9 |
| string_build | 53.2 / 59.9 | 52.4 / 61.2 (flat) | 11 |

## Measured and not kept

- **Skipping the preemption tick entirely** (ablation only: no `pthread_kill`):
  ~2% wall, inside the noise, and the tick also delivers cancellation to a busy
  task, so it is not removable. The sampler still shows `_sigtramp` on the
  busy thread; that is the 1 ms quantum doing its job.
- **Routing every RC last-free straight to `mi_free`** without a provenance test
  (the earlier crash): not attempted again. `march_string_alloc` uses libc
  `malloc`, which is at least one producer of RC'd cells outside mimalloc, and
  closing all of them needs an audit of every runtime allocation site. The
  first-arena fast path gets the same win (measured equal to an unsafe direct
  `mi_free` for constructor cells: 497.8 vs 516.0 ms min at depth 18) with no
  safety argument needed.

## Open

- Strings are libc-allocated, so a string free still takes the full slow path
  (`mi_is_in_heap_region` miss, then libc `free`). Moving `march_string_alloc`
  onto `march_obj_malloc` would put them on the fast path too, after checking
  that nothing frees string memory with an unshimmed `free`.
- The runtime-object cache and whole-binary CAS key on `runtime/*.{c,h}` only, not
  `runtime/third_party/**`: an edit to a vendored mimalloc source alone is
  served stale objects. Found while experimenting; not changed here.
- Not measured on Linux or the x86 host. There only the first-arena check, the
  frameless tails and (arm64) `-mno-outline` apply.

## Verification

- `scripts/run-tests.sh -q compiler codegen stdlib`: exit 0, all suites passed.
- Native leak fixtures (`dune build --root . test/<target>.out`, diffed against
  `test/native/<name>.expected`), all identical: nativearray_builtin_borrow_leak_probe,
  static_nullary_ctor, owned_call_drop_fusion, rc_inline_fast_path,
  record_ownership_drops, ffi_resource, ffi_leak, task_lifetime_leak_probe,
  string_pattern_literal_leak_probe, idle_worker_leak_probe, actor_state_released,
  closure_capture_release_probe, timer_leak_probe, erased_float_slot_leak_probe.
- Linux (march-amdr-repro container, arm64): the three benches and eleven of
  those fixtures compiled and run in the default (mimalloc) build and under
  `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1` (ASAN, `halt_on_error=1`): every run
  exit 0, every fixture matches its `.expected`.
