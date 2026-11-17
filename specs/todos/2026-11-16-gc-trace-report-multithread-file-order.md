# `gc-trace-report.py` reports phantom live objects for multi-threaded programs (2026-11-16)

Found in ocap phase 4 Task 6 (actors and tasks under a frame). Each scheduler thread
buffers its own trace events, so `trace/gc/gc.jsonl` is not in event order. The report
folds the file in file order, so when an address is freed on one thread and reallocated
on another, a late-flushed `dec_ref`/`free` of the old generation lands after the new
`alloc`: the old object shows as "allocated before tracing ... LIVE" and the report exits 1
although nothing leaked. A 10,000-cycle spawn/kill/task program under a frame reported
1-20 such objects per run, changing from run to run. The raw lines show each of those
addresses freed in the end.

Sorting by `ts_ns` does not fix it: timestamps have 1 µs resolution on macOS, and
events from different threads still interleave wrongly. Options:
- a per-thread sequence number plus a global happens-before event at alloc/free;
- or, cheaply, a per-address balance mode: allocs + incs - decs - frees per address is
  the final count in any order.

`test/test_cap_runtime_slot.ml` (`test_spawn_cycles_no_leak`) uses the per-address
balance for this reason.
