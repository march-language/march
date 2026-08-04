# Steady-state tail-latency + flat-RSS demo (Phase 4 remainder) — landed

**Date:** 2026-08-04

Built the end-to-end steady-state demo that substantiates March's two headline
runtime claims under sustained load, with measurements. Full design, method,
numbers, and honest limitations live in
`specs/2026-08-04-steady-state-tail-latency-demo.md`; this is the one-line
progress record.

**Shipped:**
- `bench/steady_state_ring.march` — in-process steady-state request loop; hot
  kernel under `cap no_alloc`; latency histogram threaded as unboxed `Int`
  counters; CPU-bound sibling green threads as the scheduler stressor.
- `bench/gen_steady_state.py` — generator for the above (bucket count is a knob).
- `bench/run_steady_state.sh` — compiles, runs across sibling counts, samples
  RSS over time externally (`ps`), derives p50/p90/p99/p99.9 + min/max, emits
  human table + JSONL. Parameterised (`STEADY_OPS`, `SIBLINGS`, …) so
  publication numbers can be regenerated on an idle box.
- `bench/results/2026-08-04-steady-state-arm64-laptop.{jsonl,txt}` + `*.rss`
  traces — committed laptop/arm64 measurements.

**Result (measured, laptop/arm64):** RSS flat at ~2–3 MB across all contention
levels (claim 1 — RC reclaims per-op transients; no GC heap grows). p50/p90/p99
near-constant at single-µs as CPU-bound siblings scale 0→4× the scheduler count;
the extreme p99.9 tail grows *bounded* (tens of µs → low-ms), not unbounded —
i.e. no starvation (claim 2). The strong "p99.9 ≈ p50" form holds through CPU
saturation; under heavy oversubscription the extreme tail reaches ms, reported
rather than hidden. Committed numbers were taken under heavy concurrent-session
load; p50/p90/p99 and flat-RSS are robust to that, the p99.9/max magnitudes are
inflated and an idle-box run is the documented follow-up.

**Finding filed:** `specs/todos/2026-08-04-compiled-backend-nativearray-set-int-queue-retain-memory.md`
— `NativeArray.set_int` (copy-on-write) and the persistent `Queue` retain memory
under sustained per-op churn in the compiled backend, and `RingBuf` has no
compiled backend at all; the demo threads the histogram in registers to route
around this.

**Changelog:** entry added under `## [Unreleased]` → `### Added`.
