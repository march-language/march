# Spec: inline refcount fast path

**Date:** 2026-09-30
**Todo:** `specs/todos/2026-09-30-inline-rc-fast-path.md`

## As built (2026-10-01)

Implemented in `lib/tir/llvm_rc_inline.ml`, applied by `maybe_inline_rc` in
`bin/main.ml` at both `emit_module` call sites (`--compile` and `--emit-llvm`).
Where it differs from the design below:

- **One rewrite of the finished module text, not a rename point.** The six
  refcount calls are printed by 13 emitter files; rewriting `@march_incrc(` and
  friends in the module text (declarations and definitions excepted) catches all
  of them, including future ones, and touches none. `test_codegen` calls the
  library `emit_module` directly and still sees the original calls.
- **Six twins, one per runtime entry point**, each mirroring its original
  exactly, including the details the design glossed over: the decrement forms
  skip immortal objects (`rc >= MARCH_RC_IMMORTAL`), and a non-heap value returns
  1 from `march_decrc_freed` but 0 from `march_decrc_local_freed`.
- **Last reference: `march_rc_last_atomic` / `march_rc_last_local`.** These run
  the original's free or underflow tail without decrementing again. A first
  version restored the count and called the original instead; that cost an extra
  atomic and a second decrement on every free and made `binary_trees` about 6%
  slower, so the helper the design proposed was the right call after all.
- **Trace state** is exported as `march_gc_trace_state` and resolved in
  `spawn_main_impl`. A program that never runs `spawn_main` (`--compile-so`)
  simply takes the out-of-line branch until something resolves it.
- **Entry-block alloca hoisting, in the same rewrite.** The emitter gives every
  let binding a stack slot where it is bound, inside case-arm and loop blocks,
  and LLVM only promotes slots in the entry block. Inlining the twins split
  blocks, so fewer of those dynamic slots got cleaned up, and frames grew:
  `test/native/array_sort_by.march`'s `ordered_and_stable`, which recurses
  through a join-point closure instead of looping, went from 208 to 256 bytes per
  level and overflowed its 1 MiB green-thread stack at 4,500 elements instead of
  about 6,000. Hoisting the fixed-size scalar and pointer slots to the entry block
  takes the same recursion to 160 bytes per level, so it now survives 6,000. A
  release-only decrement was tried first and changed nothing.
- **Hoisting only applies to functions whose slots are all scalars or
  pointers.** Hoisting the scalar slots of `test/native/simd_mutual_tco.march`'s
  mutual-TCO dispatcher, which also allocates `<4 x float>` slots inside its
  loop, made it crash (SIGSEGV at address 0x10). No slot is type-punned, and each
  class of slot hoisted alone was fine; the mechanism is not understood yet, so a
  function with any vector or aggregate slot keeps its layout exactly.
- **`march_gc_trace_state` is a plain external global.** Marking it `dso_local`
  (tried to reduce register pressure; it did not) broke every `--compile-so` and
  hot-reload patch build: a shared object resolves the symbol from the host.
- **Off** for wasm targets, sanitizer builds, and `MARCH_NO_INLINE_RC=1` (also a
  CAS-key tag). The switch turns off the hoisting too, so off is exactly the old
  code generation. The REPL JIT does not go through `emit_module`'s driver path and
  is unchanged.

Measured on Apple M3 Max, same compiler on and off, interleaved, 9 rounds,
median, with hoisting: `list_ops` 1.25×, `tree_transform` 1.06×, `binary_trees`
1.12×.
**Not yet measured on x86 Linux**, where the spec asked for a run before merge:
an atomic RMW (`lock xadd`) costs more there than on arm64.

## Problem

Every refcount operation in compiled code is an out-of-line call into the
precompiled runtime objects. The runtime isn't LTO'd with the program, so LLVM
can't inline or elide any of them. Compiled `main` runs on a scheduler worker
(`march_spawn_main` sets `tl_sched`), so `march_incrc_local` and
`march_decrc_local` always take their atomic branch after a thread-local check. In
practice every RC op is a call, a TLS load, a heap-pointer test, and an atomic.

Measured 2026-09-30 by patching `--emit-llvm` output with an inline fast path and
relinking with the driver's own command (`MARCH_ECHO_CC=1`). A relinked unmodified
build matched the driver's binary, and every variant printed identical output.
M3 Max, minimum of 5 rotated runs:

| bench | today | inline, atomic | inline, non-atomic (unsafe ceiling) |
|---|---:|---:|---:|
| `list_ops` | 65.3 ms | 57.4 ms (1.14×) | 57.6 ms |
| `tree_transform` | 624.5 ms | 613.6 ms (1.02×) | 618.1 ms |
| `binary_trees` | 207.3 ms | 202.7 ms (1.02×) | 204.8 ms |

Two conclusions:
- the call overhead is worth up to 14% on closure-heavy code;
- atomic vs non-atomic makes no difference on Apple silicon, so this spec keeps
  the atomic path and gives up nothing for it.

## Goal

Emit the RC fast path inline in every LLVM module the native backend produces, with
exactly today's semantics, falling back to the runtime whenever something unusual
happens (the last reference, underflow, tracing on).

## Design

### Where: `lib/tir/llvm_builtins.ml` and the preamble

The six RC entry points are declared through the builtin table
(`llvm_builtins.ml`, the `march_incrc` … `march_decrc_local_freed` entries and
their `PDeclare` lines). Call sites are spread over `llvm_emit.ml` (EIncRC and
EDecRC), `llvm_case.ml`, `llvm_emit_data.ml`, `llvm_emit_task.ml` and
`llvm_emit_call.ml`.

Don't touch the call sites. Instead, when the fast path is enabled, emit
`internal alwaysinline nounwind` **definitions** under new names and add
**one rename point**: a function in `Llvm_ctx` that maps an RC entry name to the
name to call, used by every site that prints `call void @march_…rc…`. The
declares of the real runtime functions stay, because the slow paths call them.

```
__march_rc_inc(p)            replaces  march_incrc, march_incrc_local
__march_rc_dec(p)            replaces  march_decrc, march_decrc_local
__march_rc_dec_freed(p) i64  replaces  march_decrc_freed, march_decrc_local_freed
```

### Fast path semantics

```
inc(p):
  if !is_heap_ptr(p)            -> return
  if trace_state != OFF         -> call march_incrc(p); return
  atomicrmw add [p+0], 1 monotonic

dec(p):
  if !is_heap_ptr(p)            -> return
  if trace_state != OFF         -> call march_decrc(p); return
  prev = atomicrmw sub [p+0], 1 acq_rel
  if prev <= 1                  -> call march_rc_dec_slow(p, prev)
```

- `is_heap_ptr` is `IS_HEAP_PTR` from `runtime/march_runtime.h`, spelled out in IR:
  low bit clear, address at least 4096, positive as a signed value. Many call sites
  already know their operand is a heap pointer; LLVM folds the test away there.
- The orderings match `march_incrc`/`march_decrc` exactly (relaxed increment,
  acq_rel decrement). Threads not on the scheduler used to get non-atomic ops; they
  now get atomic ones, which is never less safe and measured free on arm64.
- `dec_freed` has the same shape, returning 1 from the slow path when the object was
  freed and 0 otherwise.

### Runtime changes: `runtime/march_runtime.c`

1. **Export the trace state.** `gc_trace_state` is `static` today. Add an exported
   `int march_rc_trace_state` holding the same value (0 unknown, -1 off, 1 on).
   The fast path must treat "unknown" like "on" and take the slow path, so resolve
   it eagerly: call the trace init from `march_spawn_main` (and the other
   program entry points: `--compile-so` init and the REPL runtime init) before any
   March code runs. Otherwise the first RC op in every program takes the slow path,
   which is harmless but defeats the purpose.
2. **Add `march_rc_dec_slow(void *p, int64_t prev)`.** It is called after the
   decrement has already happened:
   - `prev == 1`: the object is dead. Run exactly what `march_decrc` runs today at
     zero (resource destructor, `MARCH_FREE_BUMP`, free, and whatever child drops
     it performs). Factor that into a shared helper so the two can't drift.
   - `prev <= 0`: underflow. Report and abort, as `march_decrc_local` does today.
   This replaces the "store 1 back and call `march_decrc`" workaround used in the
   measurement patch, which only works for a sole owner.

### Where the fast path is **off**

- **wasm targets.** `runtime/march_runtime_wasm.c` defines the RC entries as
  **no-ops**. An inline fast path would start freeing memory under wasm. Gate on
  `Llvm_emit.is_wasm_target`.
- **JS:** no LLVM, not applicable.
- **Sanitizer builds** (`MARCH_SANITIZE`). They keep the out-of-line calls, so
  ASAN and TSAN see the runtime's own accesses. This is also what lets the ASAN
  corpus act as a control against the new path.
- **Kill switch:** `MARCH_NO_INLINE_RC=1`, same pattern as `MARCH_NO_UNBOX`, for
  A/B runs and support.

It stays **on** for native, cross targets (linux/amd64, linux/arm64), hot code
reload patch `.so` files and the REPL JIT. Each module gets its own `internal`
copies, so there are no symbol clashes between JIT fragments or patches, and
`march_rc_trace_state` resolves against the one runtime loaded in the process.

### Cache key

Enabling the fast path changes the emitted IR for every program. Add it to
`cas_flags` at both sites (see the `project_cas_cache_key_flags` memory), or
cached binaries built before the change will be reused after it and hide the
effect from any A/B run. Include `MARCH_NO_INLINE_RC` in the key too.

## Tests

- **Full suite plus the native golden tests**, since every compiled program
  changes.
- **ASAN corpus sweep** (`project_asan_corpus_sweep` memory, via Docker on this
  Mac). Sanitizer builds keep the old path, so the useful check is a **non-ASAN**
  run of the same corpus comparing output with the fast path on and off. Pair it
  with a leak count (`MARCH_TRACE_GC` totals or RSS) on the leak-probe fixtures.
- **Tracing:** a program run with `MARCH_TRACE_GC` set produces the same event
  stream as before. That proves the trace fallback works.
- **Underflow:** a runtime-level unit test calls `march_rc_dec_slow` with
  `prev == 0` and expects the abort.
- **Wasm:** a wasm32-wasi compile contains no `__march_rc_*` definitions.
- **Concurrency:** the scheduler stress tests and two-node suites pass. The fast
  path is atomic, so this is a sanity check, not the main risk.
- **Oracle:** `scripts/ir-oracle.sh` changes for every program by design. Check
  that the diff is confined to RC call sites and the added definitions, then
  rebaseline.
- **Perturbation:** make the fast path skip the `prev <= 1` check, and confirm a
  leak probe or the ASAN-equivalent output comparison goes red.

## Benchmark and acceptance

`bench/list_ops.march`, `bench/tree_transform.march`, `bench/binary_trees.march`,
and the HTTP CPU-µs/request benchmark, on vs off with the kill switch, same binary.
Also run **once on x86 Linux** before merging: `lock xadd` costs more there than
on arm64, and the "atomic is free" result is arm64-only evidence.

Accept when:
- `list_ops` improves at least 8% on arm64;
- nothing regresses on either architecture;
- the trace, underflow and wasm tests pass.

## Effort

About 1 day of agent work. The two runtime helpers are small, the rename point is
one function, and most of the time goes to the suite, the corpus comparison and
the x86 run.
