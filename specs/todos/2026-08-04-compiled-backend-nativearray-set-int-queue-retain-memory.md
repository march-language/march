# `[P2]` Compiled backend: `NativeArray.set_int` (and `Queue`) retain memory under sustained per-op churn

Found while building the steady-state flat-RSS demo
(`specs/2026-08-04-steady-state-tail-latency-demo.md`,
`bench/steady_state_ring.march`).

- [ ] **`NativeArray.set_int` copy-on-write is not promptly reclaimed under
  sustained churn (compiled).** `native_int_arr_set`
  (`runtime/march_runtime.c`) allocates a fresh backing array and `memcpy`s on
  every call (it is O(n) copy-on-write by contract — the docstring says "Return
  a new array"). In a hot loop that does one `set_int` per iteration and
  threads the result forward (last-use, RC=1), the old copies should be freed
  immediately (or the write done in place via FBIP). Measured instead: a 2M-op
  loop whose *only* per-op heap operation is `set_int` on an 8-element array
  ramps to **~258 MB RSS**; the same loop without it holds **~2.7 MB flat**.
  Isolated with `bench/` probes (mode-switched). Whether the right fix is
  FBIP in-place reuse when RC=1, a genuine in-place `set_int!`, or prompt
  reclamation of the old copy is open — but a copy-on-write array is currently
  unusable as a per-op accumulator in a flat-RSS hot path.

- [ ] **Persistent `Queue` (`stdlib/queue.march`) also retains memory under
  per-op churn (compiled).** A depth-1 `push_back`/`pop_front` per op ramps to
  **~38 MB** over 2M ops (vs ~2.7 MB without). Smaller than the array case and
  possibly the same root cause (transients not reclaimed promptly / allocator
  page retention rather than a true leak — RSS is bounded/sub-linear in ops,
  not monotonically linear), but it makes the stdlib functional queue a poor
  fit for a sustained hot path. Confirm true-leak vs. allocator-high-water with
  a longer run and `MARCH_SANITIZE=1`.

- [ ] **`RingBuf` has no compiled backend at all** (separate, smaller item).
  `ring_buf_make/push/pop/get/size/cap/clear/to_list` exist only as interpreter
  builtins (`lib/eval/eval.ml`); there is no C runtime symbol and no
  `lib/tir/llvm_builtins.ml` entry, so any compiled program using `RingBuf`
  fails to link (`Undefined symbols: _ring_buf_make …`). Either add the compiled
  backend (it is the natural in-place mutable ring the demo wanted) or mark the
  module interpreter-only in its docs so the gap is not a silent link failure.

**Why it matters:** the flat-RSS story (RC reclaims the live set, not the
allocation rate) is a headline runtime claim. The demo had to route around
these by threading the latency histogram as unboxed `Int` counters. The
demonstration would be cleaner — and stdlib containers would be safe in hot
paths — with these reclaimed promptly. **Regression guard:** re-run
`bash bench/run_steady_state.sh` and confirm the `RSS(KB) min/max` columns stay
flat (~1.5–3 MB) across all sibling counts.
