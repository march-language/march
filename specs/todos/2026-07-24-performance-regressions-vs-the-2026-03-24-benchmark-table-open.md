# Performance regressions vs the 2026-03-24 benchmark table (OPEN, 2026-07-24)


Measured with `RUNS=10 bash bench/run_benchmarks.sh` on the same machine
class, with OCaml/Rust as controls (both within noise of their 2026-03-24
figures, so the host is not the variable). See `bench/RESULTS.md`.

### ROOT-CAUSED AND FIXED 2026-07-24 — the per-call check was a TLS resolver call

**`66371f3b` (2026-03-25) "feat(sched): Phase 4 — reduction counting in
compiled code" landed the day AFTER the 2026-03-24 benchmark table was
recorded.** Every compiled function entry now emits a load / decrement /
store against the `@march_tls_reductions` global plus a conditional branch to
`@march_yield_from_compiled` (`Llvm_ctx.emit_reduction_check`, gated only on
`ctx.repl`). So the published table is a pre-preemption baseline and every
number since carries this cost. **This is the price of a deliberate feature,
not a regression to hunt** — but it was never re-baselined, so it has been
sitting in the table as an unexplained 2.2x.

A/B measured by gating the emission behind a temporary env var, **with
`.march/cas/artifacts` cleared between every build** (see the warning below):

| benchmark | TLS check (before) | plain-flag check (now) | no check at all | 2026-03-24 |
|---|---|---|---|---|
| `fib(40)` | 640 ms | **465 ms** | 360 ms | 288 ms |
| `tree_transform` | 852 ms | **579 ms** | 540 ms | 513 ms |
| `list_ops` | 67 ms | **64 ms** | 80 ms* | 68 ms |
| `binary_trees` | 177 ms | **165 ms** | 150 ms | 265 ms |

\* the allocation-bound benchmarks are within noise of each other; the check
cost falls almost entirely on call-dense code.

Removing it lands `fib` and `tree_transform` essentially back on their
historical figures, which closes both open items. Allocation-bound
benchmarks are unaffected — the cost is per *call*, so it falls entirely on
call-dense recursive code.

Ruled out along the way, so nobody re-walks them: the tag/untag round-trip
through the `case` result slot (`shl`/`or`/`inttoptr` on store, conditional
`ashr`+`select` on load — present today, a bare `inttoptr` in 2026-03; in
isolation the tagged form is *marginally faster*), March's clang flags
(`-fno-strict-aliasing -fwrapv -msse4.2` — no effect), and scheduler thread
count (`MARCH_NUM_SCHEDULERS=1` changes nothing).

- [ ] **Remaining `fib` gap vs 2026-03-24 (~390 vs 288 ms): the per-iteration
  volatile check plus call frame.** ~100 ms over ~165M loop iterations
  (post-TRE) ≈ 2 cycles/iteration — the price of staying preemptible. Any
  further recovery means checking less often (e.g. unrolling the TRE loop or
  a check-every-N scheme), which re-opens the counter-cost question; not
  obviously worth it.
- [ ] **Re-baseline `bench/RESULTS.md` against a post-preemption reference**
  so the table stops implying a regression that is actually a feature cost.

> ⚠️ **Benchmark A/B methodology — the CAS artifact cache will lie to you.**
> The first run of this experiment concluded "the reduction check costs
> nothing", because compiled artifacts are content-hash cached in
> `<project>/.march/cas/artifacts/` and the key covers compiler flags but
> **not environment variables**. Both arms of the A/B were served the same
> cached binary. Always `rm -rf .march/cas/artifacts` between arms and
> confirm the two outputs have *different* hashes before believing a null
> result. (Same class as the existing `cas_flags` note for CLI flags.)
- **Not a regression:** `binary-trees(15)` improved (265.4 → 176.6 ms) and
  `list-ops(1M)` is exactly restored (67.6 → 67.3 ms).
