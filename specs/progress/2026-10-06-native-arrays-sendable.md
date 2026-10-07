# Native arrays are values, so they may be sent (Part C, Phase C1)

**Landed 2026-10-06.** Phase C1 of
`specs/plans/2026-09-25-send-data-race-freedom-plan.md`; semantics in
`specs/2026-10-06-linear-ringbuf-and-sendable-arrays-design.md` §2. Depends
on C0 (`2026-10-06-sole-ownership-checks-acquire-and-march-free-destructor.md`).
The todo `specs/todos/2026-09-25-send-marker-and-closure-capture-checks.md`
stays open until C5.

## What was wrong

The five `NativeArray` backing types (`NativeIntArr`, `NativeFloatArr`,
`NativeF32Arr`, `NativeI32Arr`, `NativeU8Arr`) were in `check_sendable`'s
denylist (`lib/typecheck/typecheck_exhaustive.ml`), added 2026-08-07 by
analogy with `RingBuf` ("structurally the same hazard"). The runtime says
otherwise: every in-place write to a native array is gated on sole ownership
and copies when the array is shared, and the interpreter always copies. No
program can tell the two apart, so a native array is a copy-on-write value
and the denylist entry only cost users the ability to send one.

## Audit (every in-place path, `runtime/march_runtime.c` at `384b070d`)

| Path | Gate |
|---|---|
| `set` at all five widths (`native_int_arr_set`, `native_float_arr_set`, `native_f32_arr_set`, and the `DEF_NARROW_INT_ARR` macro for i32/u8) | `IS_HEAP_PTR(arr) && march_rc_is_unique(arr)`, else copy + `march_decrc` |
| `sort` at all five widths, including the fast paths that landed after the plan (full-run scan, equal partition, two-run merge, the `n <= 32` network; `nsort_*`) | the gate is in the entry function (`native_*_arr_sort`); every `nsort_*` helper receives the payload pointer only after it, and writes scratch buffers otherwise |
| the SIMD vector store (`lib/tir/llvm_emit_simd.ml`, `"store"`) | emitted `IS_HEAP_PTR` test + `load atomic … acquire` == 1, else alloc/memcpy/decrc |
| `map`, `map2` (C bodies and the `Native_map_inline` fast path, `lib/tir/llvm_emit_nmap.ml`) | always allocate the output (`native_*_arr_alloc_raw`); the "reuse" in the test names is closure-shape reuse, not array reuse |
| `filter_mask`, the width conversions (`float_to_f32_arr`, `i32_to_int_arr`, …), `from_list`, `to_list`, `fold`, `sum` | allocate fresh or read only |
| interpreter (`lib/eval/eval_builtins.ml`) | always copies |

Nothing ungated was found, so nothing needed fixing before the flip.

## What changed

- `typecheck_exhaustive.ml`: the five names leave `non_sendable_types`
  (`["RingBuf"]` remains until C2); the doc comment states the rule for what
  belongs on the list.
- `specs/lang/types/`: `reject/t164`, `t165`, `t169`, `t170` are
  `accept/t164_native_int_arr_sendable` and companions, same ids (one
  numbering pool), headers rewritten; `INDEX.md` counts and the Result
  paragraph updated. **Two-repo rule:** `march-lean` must mirror the four
  verdict flips.
- New tests, interpreted and compiled: an actor that receives a native array
  and writes it while the sender writes its own reference, each side seeing
  only its own write (`test/stdlib/test_native_array_send.march`,
  `test/native/native_arr_send_cow.march`); `Parallel.pmap` reading a captured
  array (`native_arr_pmap_capture`); two tasks setting the same captured array
  for 300 rounds, the copy-on-write race C0 protects
  (`native_arr_task_set_race`, compiled at `--opt 2`).
- `stdlib/native_array.march` header: "Sharing and sending" (the cost model
  from the design spec §2.2) and the audit's conclusion.
