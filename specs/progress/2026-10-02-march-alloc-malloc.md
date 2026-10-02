# `march_alloc` is a `malloc`, not a `calloc` (x86 finding 2, step 2)

Landed 2026-10-02. Step 2 of the plan in
`specs/todos/2026-08-04-x86-benchmark-findings.md` ("binary-trees:
march_alloc is calloc"): the object allocator no longer zeroes the payload.
The todo measured the zeroing at ~11% of binary_trees (530 -> 474 ms, x86,
pre-mimalloc). Steps 1 (mimalloc, 2026-10-01) and this one are done; the
per-actor arena (step 3 of finding 2) and findings 1 and 3 stay open, so the
todo file stays open.

## The change

- `runtime/march_alloc.h`: `march_obj_calloc` -> `march_obj_malloc`
  (`mi_malloc` under `MARCH_USE_MIMALLOC`, libc `malloc` otherwise, so the
  `MARCH_MALLOC=libc` fallback, the sanitizer builds, the JIT `.so` and the
  C unit harnesses all take the same non-zeroing path). There is deliberately
  no `march_alloc_zeroed`: no caller needed one once the three below were
  fixed, and a zeroing entry point would be the thing every new caller
  reaches for instead of writing its fields.
- `march_alloc` still writes the whole 16-byte header itself (rc=1, tag=0,
  pad=0). The contract is now: the PAYLOAD is the caller's, every word,
  before the object is published, read, or RC-walked.

## What used to lean on the zeroing, and the fix for each

1. **TRMC `EAllocHole`** (`lib/tir/llvm_emit_alloc.ml`, `emit_alloc_hole`).
   The hole slot "reads as 0 until written" was an allocator property; it
   is now an explicit `store ptr null` on BOTH fresh-allocation paths (the
   no-token path and the token path's shared fallback), the same store the
   reuse path already did. Without it, under mimalloc a fresh cell's hole
   slot typically holds the stale child pointer of a freed cons cell, and
   any drop/deep-drop in the window before the fill would walk into it.
   `tir.ml` and `llvm_emit.ml` comments updated; `trmc.ml` had no comment
   stating the property (checked).
2. **`march_task_spawn_thunk` / `march_task_spawn_with_cancel_thunk`**
   (`runtime/march_runtime.c`): the 48-byte task's four payload words (proc
   handle, result, done flag, in-scheduler waiter) started at 0 by calloc.
   Now stored explicitly, BEFORE `march_sched_spawn` publishes the object,
   so the TSan-confirmed post-spawn race the comment describes is untouched.
3. **`native_arr_alloc`**: only byte 24 of the 32-byte header (the element
   kind) was written; bytes 25..31 were calloc-zero padding. The whole word
   at 24 is now zeroed, then the kind byte stored.
4. **`ring_buf_make`**: the resource cell's `type_id@32` "stays 0" is now an
   explicit store.

## Per-caller audit (every `march_alloc(` outside the out-of-scope files)

Out of scope and untouched, as instructed: `march_reload.c`,
`march_remote_registry.c`, `march_monitor_registry.c`, `march_dispatch.c`
(none of them call `march_alloc`; their `calloc`s are their own).
`march_runtime_wasm.c` defines its own bump `march_alloc` over fresh
`memory.grow` pages and is untouched. `march_string_alloc` was already a
`malloc` (its NUL terminator is stored explicitly; `march_ffi.c`'s comment
on `march_str_new` is about that allocator, not this one).

Verdict key: "stored" = every payload word written before publish.

### LLVM emitter
- `llvm_data.ml:88 emit_heap_alloc` -- header written by `march_alloc`; type
  id stored iff nonzero (pad is 0 from the header init). Callers:
  - `llvm_emit_alloc.ml emit_alloc_ctor` (Boxed arm) -- all N ctor fields
    stored; fewer args than fields is a `failwith`.
  - `llvm_emit_alloc.ml emit_alloc_uniform` -- all N tuple slots stored.
  - `llvm_emit_alloc.ml emit_alloc_hole` -- filled fields stored, hole
    slot NULLED (fix 1).
- `llvm_ctx.ml:793` unboxed-aggregate boxing -- all N fields stored.
- `llvm_ctx.ml:757 march_simd_alloc` box -- the 16-byte payload stored.
- `llvm_emit.ml:467/599/657` 24-byte closure wrappers -- tag + fn ptr stored
  (header 16 + 8 = 24, nothing else).
- `llvm_toplevel.ml:1521` 16-byte enum cell -- tag only; no payload.
- `llvm_repl.ml:457` 24-byte REPL closure -- tag + fn ptr stored.
- `EStackAlloc` -- alloca, zeroed explicitly already; not march_alloc.

### runtime/march_runtime.c
- `march_alloc_float` -- tag + val (24 bytes) stored.
- `march_simd_alloc` -- header only here; the emitter stores the payload.
- `__try_call` / sibling (2032, 2107) -- tag + field stored on both branches.
- `march_actor_registered` 3640 -- Nil, no payload.
- `5757 reason_value` -- 24 bytes iff crash, and then field 0 stored; else 16.
- `5772 Down` -- 3 fields stored.
- `5906 unit_arg` -- 16 bytes, no payload.
- `7031/7098 Task` -- relied on zero: FIXED by explicit stores (fix 2).
- `7226/7253/7265 None` -- 16 bytes.
- `7361 timer token` -- cancelled field stored.
- `7542 reply_ref` 2 fields, `7549 call_msg` 1 field -- stored.
- `7720 reply env` -- 2 fields stored.
- `make_nil/make_cons/make_tuple2` (7806/7813/7899) -- all fields stored.
- `string_to_float` 8600/8611 -- None 16 / Some field stored.
- `mk_ok/mk_ok_unit/mk_err/mk_file_error` -- field 0 stored.
- `build_string_list` 8829/8832 -- Nil / cons fields stored.
- `file_stat` 8921/8924 -- kind no payload; FileStat 4 fields stored.
- `file_open` 8937 -- field 0 stored.
- `process_run` 9272 -- 3 fields; `9457 LiveProcess` 2; `9607 csv handle` 3;
  `9630/9632` list -- all stored.
- `10012 capability` -- w[2..4] stored.
- `typed_array_alloc` 10495 -- len/cap stored; every caller fills all `len`
  slots (from_list, set-copy memcpy, create, slice, map, filter memcpy).
- `native_arr_alloc` 10971 -- kind word: FIXED (fix 3). Element bodies: every
  caller writes all `len` elements, including the five `*_alloc_raw` entry
  points, which are not reachable from March source (no typecheck entry) and
  whose only consumers are the inline nmap loops (`llvm_emit_nmap.ml`), the
  SIMD `set` copy path (`llvm_emit_simd.ml`, memcpy of the whole body) and
  `march_extras.c:279` (memcpy of `len` bytes).
- cons builders 12090/12312/12431/12618 -- both fields stored.
- `ring_buf_make` 12805 -- type_id word: FIXED (fix 4).
- `logger_tuple2` 12963, `logger_add_field` 13206, `add_context` 13250,
  `appender_call` 13406 -- all fields stored.

### runtime/march_extras.c
- `bytes_wrap` 236, `make_ok` 308, `make_err_str` 316, `rec_box_*` 372/396,
  vault handle 1138, every `Unit`/`Nil` 16-byte cell, vault cons 1409/1592,
  chan/mpst endpoints and tuples 1938/1959/1991/2132/2179/2207, codepoint
  Some 2270, `rec_nil/rec_cons/rec_pair` 2520-2531 -- all fields stored.
- `march_record_put` 2676/2695, `from_list_k` 2780, `update_many` 2900 --
  all `nfields` slots stored in a full loop, pad (shape id) stored.

### runtime/march_http.c, march_http_evloop.c, march_http_internal.h
- Every Ok/Err/Nil/Unit/cons/Header/tuple4/Bytes builder, the 13-field
  `make_conn`, `make_int`, the WsSocket 24-byte cells, every WebSocket frame
  variant and the parse_response tuple -- all fields stored.

### runtime/march_ffi.c
- `mk_cell1` 113, `march_make_variant` 139 and `march_make_record` 146 (loop
  over `nfields`), `march_none_boxed` 186, `march_resource_new` 215 (3
  fields) -- all stored.

### runtime/march_compress.c, march_nacl.c, march_tls.c
- Bytes/Ok/Err wrappers -- the single field stored.

### Things checked that are not hazards
- No `march_alloc`-backed buffer is grown with `realloc` (none found).
- No whole-object `memcmp`/raw-byte hash reads padding: the only object
  `memcmp` is the 16-byte SIMD payload compare (fully written).
- SIMD element loads are bounds-checked (`i + lanes <= len`); the runtime's
  array loops are scalar per element; nothing reads past `len`.
- Actor records: codegen `EAlloc` stores every field; the shape id in the
  pad word is written by `emit_heap_alloc`/`march_alloc`'s header init.
- `march_alloc` is declared `noalias nonnull ... allocsize(0)` without an
  `allockind`, so LLVM does not assume anything about the contents.

## Measurements (2026-10-02, the box this landed on)

Apple Silicon Mac, shared (1-min load average ~7-8), `--compile --opt 2`,
origin/main (8ee63159c) toolchain copy vs this branch, interleaved runs with the
first round discarded, wall time of the whole process (`time.perf_counter` around
the run for the two short ones, `/usr/bin/time` for the rest):

| bench | main min / med | malloc min / med | n |
|---|---|---|---|
| binary_trees 15 (mimalloc, the default) | 118.3 / 123.6 ms | 117.1 / 124.2 ms (flat) | 10 |
| binary_trees 15 (`MARCH_MALLOC=libc`) | 216.0 / 219.0 ms | 211.6 / 217.0 ms (-2% / -1%, noise) | 10 |
| list_ops | 44.9 / 47.4 ms | 43.7 / 47.7 ms (flat) | 10 |
| tree_transform | 650 / 660 ms | 640 / 660 ms (flat) | 5 |
| par_fib | 200 / 220 ms | 180 / 220 ms (flat) | 5 |
| actor_ping | 1130 / 1140 ms | 1130 / 1130 ms (flat) | 5 |

So the todo's 11% (x86 Linux, glibc `calloc`, pre-mimalloc, idle box) does NOT
reproduce here with either allocator: on this machine the zeroing of 32-byte cells
is not a measurable cost. The change stays because it is the contract the todo
asked for and the audit found no caller that needed the zeroing, but the number to
quote for it is "flat on Apple Silicon; up to ~11% on x86 glibc per the 2026-08-04
ablation, unverified since mimalloc landed". Re-measure on the x86 host before
citing it.

## Tests

- `test/test_trmc.ml` "hole slot cleared at alloc, written once by fill"
  (was "written once by fill"): pins exactly one `store ptr null` and exactly
  one value store at the hole offset in the emitted IR. This is the
  perturbation-sensitive test: removing the fresh-path null store turns it
  red.
- `test/test_codegen.ml` `test_compiled_trmc_hole_fresh_after_churn`:
  end-to-end witness -- heap churn (40k dropped two-cell lists), then two
  TRMC copies of a SHARED list (forces the fresh path) with the shared
  scrutinee's decrc landing inside every hole's window; compiled output must
  equal the interpreter's. Note it is a parity witness, not a hazard
  detector: nothing in the generated code reads the hole before the fill
  (see the perturbation record in the commit message), so it stays green
  without the null store; the IR test is the one that catches it.
