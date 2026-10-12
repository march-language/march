# Task destructor read a result its awaiter had already freed

**Fixed** 2026-10-12. Found by the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh`, Linux arm64): one run of
`tcp_recv_eagain_after_park` at `MARCH_NUM_SCHEDULERS=14` reported

```
ERROR: AddressSanitizer: heap-use-after-free ... READ of size 4 ... thread T4
  #0 march_run_resource_dtor_slow   march_runtime.c
  #1 march_decrc
  #2 march_thunk_trampoline         march_runtime.c
freed by thread T0 here:
  #1 List.fold_left$...$__lam2_main_apply_3_main     (the awaiter)
previously allocated by thread T4 here:
  #2 drain                                            (the task body)
```

Reproduced with the pre-sweep compiler: 1 of 800 runs under 8-way parallel
load, 0 of 100 idle.

## The bug

A Task owns its result only when it is a Float box (`task_await_unwrap` reads
the double out without consuming it); every other result belongs to the
awaiter. The Task's destructor (the `MARCH_TASK_TAG` case of
`march_run_resource_dtor_slow`) decided which case it was in by reading the
RESULT's header tag when the Task died. The trampoline holds its own reference
to the Task and drops it after publishing the result; when the awaiter has
already released a (non-Float) result and dropped its Task handle, that drop is
the last one, and the destructor reads the tag of freed memory. Had the freed
cell been reused as a Float box, it would have been released twice.

## The fix

The trampoline decides "Float box" when it stores the result, while it still
owns it, and records it in the Task's header pad
(`MARCH_TASK_OWNS_FLOAT_BOX`, `runtime/march_runtime.h`), published by the
seq_cst done store. The destructor reads only that flag and never dereferences
the result.

## Verification

- `test/native/task_result_released_before_task.march` (14 schedulers): 2,400
  tasks returning tuples that are awaited, released and dropped (the shape
  above), and a Float leg that keeps `live_allocs()` flat, proving a Float
  result is still released when its Task dies.
- ASAN: `tcp_recv_eagain_after_park` with the fix, 0 of 1,200 runs under the
  same 8-way load; the new fixture is clean under the ASAN and LSan passes.
