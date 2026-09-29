# `signal_term_suppress` is back on `runtest` (2026-09-28)

This closes the last open bullet of `specs/todos/2026-07-23-ci-infra-2026-07-23.md`.
That file is reproduced below and moved here, since it has no open items left.

**What the quarantine saw, re-examined.** Two failure shapes appeared at about 2-5%:
- TORN output, e.g. `survived termterm handler`;
- a clean reordering, with `term handler` before `survived term`.

The tear has since been explained and fixed. On 2026-08-21 it was measured
falling between `march_println`'s two iovecs, which raced another thread's
`writev`, and `march_stdout_mu` now serializes them
(`specs/progress/2026-08-21-println-writev-not-atomic-across-threads.md`). The
quarantine's "pre-write allocator/GC race" guess was superseded by that
finding, and the same fix brought `node_discovery` back on 2026-09-14.

The reordering is not a bug. `Signal.raise`'s documented contract says delivery
is asynchronous and the watcher runs "from the next scheduler drain". Any
scheduler OS thread may perform that drain, so the handler can print before
`main`'s next line.

**Soak (2026-09-28, macOS arm64, binary run directly, host load 10-21):**

| Binary | Runs | Parallel | Outputs compared | Result |
|---|---|---|---|---|
| compiled once | 1000 | 4 | exact | 994 exact; 6 clean reorderings; 0 torn lines; 0 non-zero exits |
| same binary | 800 | 8 | sorted | 0 mismatches |
| built by the dune rule | 200 | 4 | exact | 0 mismatches |

**Change (`test/dune`).**
- The rule's hand-listed runtime file deps, which no longer covered the
  runtime (for example `march_blake3.c`), are replaced by
  `(source_tree ../runtime)`.
- A new `native_signal_term_suppress.sorted.out` target sorts the output, and
  the diff moves from the `signal_term_suppress_quarantined` alias back to
  `runtest`. This mirrors `node_discovery`.
- The diff tolerates the documented reordering. A torn or missing line, or a
  process killed by the SIGTERM, still fails it. The `.expected` is already in
  sorted order.

**No quarantined test at all is a new state, and two scripts could not
handle it.** Both derive the alias set with a `grep` that finds nothing and
exits 1:
- `scripts/check-docs.sh` Check E runs under `set -euo pipefail`, so that
  exit killed the whole lint with no message.
- The nightly's quarantine step (`.github/workflows/nightly.yml`, bash
  `-eo pipefail`) also ended before printing its "(none quarantined)"
  summary.

Both now tolerate the empty set (`|| true`). A copy of the old nightly loop
exits 1 on today's tree; the patched copy runs to the end. Check E reports
`ok — 0 quarantine alias(es)`.

The quarantine inventory
(`specs/todos/2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026.md`)
strikes its last live row. It stays in `specs/todos/` as the list
`check-docs.sh` Check E compares the dune aliases against, which is now empty
on both sides.

---

Original file (the one open bullet it still carried):

# CI infra (2026-07-23)

Trimmed 2026-09-09: this file originally carried three bullets. Two were
already marked `[x] RESOLVED 2026-08-08` inline (the runtime-object
system-header cache-key fix, and the property-tests coverage-guard union
fix) — removed here since they're done and the detail was self-contained.
The third, below, is still genuinely open.

- [ ] **QUARANTINED (2026-07-24): `test/native/signal_term_suppress` golden fails on a signal-dispatch race — NOT a simple ordering issue, sorting the golden does not fix it.** Reddened `test (ubuntu-24.04)` on 2026-07-24; the expected golden is `before term / survived term / term handler` (the handler is deferred to the scheduler drain after main's body). **Reproduced locally by looping the compiled binary hundreds to thousands of times: ~2-5% of runs fail**, and characterized the failure shape precisely (1000-run sample): only 9/1000 were a clean 3-line permutation (what a sorted diff, `node_discovery`'s approach, could tolerate) — the other 43/1000 were **TORN output**, e.g. `survived termterm handler` (the newline between the two lines is simply gone, not reordered elsewhere). A sorted-diff golden was considered and rejected: it would silently pass the torn-output majority right through as a "different sort order" mismatch (still failing, just for the wrong reason) and, worse, would validate the reordering minority as fine when this test's own doc comment asserts the order is supposed to be deterministic — sorting would mask a real ordering bug, not just tolerate benign nondeterminism. **Investigated the likely mechanism**: `march_println`/`march_print` (`runtime/march_runtime.c`) discard `writev`/`write`'s return value; `march_scheduler.c`'s own "Limitations / known EINTR exposure" comment documents that its SIGUSR1 preemption tick can EINTR a blocking syscall and that "on macOS SA_RESTART does not cover all syscalls" — a plausible short-write mechanism. **Implemented and tested a retry-on-short-write fix** (a `write`/`writev` retry loop in `march_print`/`march_println`) — it did NOT reduce the flake rate (28/500 with a guaranteed-fresh compile, `MARCH_NO_RUNTIME_CACHE=1` + caches cleared, so the runtime-object cache wasn't a confound). **Reverted that fix** (no measured benefit, and changing the hot-path print builtins without proof of effect isn't worth the risk) rather than ship unproven runtime code. Conclusion: the corruption happens **before** the write syscall — most likely the deferred `Signal.watch` dispatch (fired by whichever scheduler OS thread's per-iteration `march_signal_drain()` call happens to notice the pending flag first, not necessarily after the raising thread's own subsequent code has run) racing with the main green thread over something shared (allocator/GC), not a pure I/O interleaving issue. Same general bug *class* as the open scheduler-deadlock P0 below (heisenbug, not yet isolated to an exact missing sync edge) but a distinct symptom/repro — tracked separately here rather than folded in. **Quarantined** (`test/dune`, own alias `signal_term_suppress_quarantined`, matching the four scheduler-deadlock tests' pattern) rather than chased further, since isolating the actual race is a scheduler-level investigation out of scope for the CI-speedup work it surfaced during. Un-quarantine once the dispatch race is understood and fixed.
