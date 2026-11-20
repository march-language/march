`[P2]` Every checked capability operation allocates one `Result` cell per call

Filed 2026-11-19 from the ocap phase 4 PR B perf check.

`Authority.must(System.now_ms())` costs about 9.6 ns more per read than the raw
`unix_time_ms()` builtin it replaced (+49% on `bench/clock_loop.march`, 10M reads, 21
alternating runs, load average about 6). Attribution, each arm compiled from the same
compiler and runtime:

| arm | median cpu ms | per read vs raw |
|---|---:|---:|
| raw builtin only | 197.0 | 0 |
| fast-path check only, no `Result` | 211 | +1.4 ns |
| `Result` value only, no check | 268 | +7.1 ns |
| `now_ms` with the raw check inlined | 279.4 | +8.2 ns |
| `Authority.must(System.now_ms())` (ships) | 293.0 | +9.6 ns |

About 7 ns is one 24-byte `Result` cell (malloc plus free): `Authority.check` allocates
`Ok(())`, the cell is reused for `Ok(ms)`, and `must`'s match frees it. About 1.4 ns is the
check and about 1.3 ns the call into `Authority.check`, which is not inlined (the general
inliner takes only pure functions, and `println` in `main` is a second caller). `println`
and every other checked operation compile to the same shape; the clock only shows it
because a clock read is about 20 ns.

The cell survives because the known-constructor fold runs once, before RC insertion, and
cross-function inlining runs after it, so `must(Ok(x))` is never adjacent while the fold
runs. A comment in `lib/tir/opt.ml` records why running the fold later exposes a
variable-capture bug.

Options:
- Inline tiny wrappers (`Authority.must`, `Authority.check`, `System.now_ms`, the other
  checked entry points) before RC insertion so the existing fold removes the `Result`.
  Expected about -8 ns per call. Costs a new or moved pass, IR-oracle churn across the
  corpus, and the capture-bug risk above.
- A faster allocator for 24-byte cells (the mimalloc build). Runtime-wide decision.
- Not worth doing alone: calling the raw check inline in each entry point saves about
  1.4 ns and makes every entry point a second caller of the raw check.

Done when `bench/clock_loop.march` through the checked entry point is within noise of
the raw builtin plus the 1.4 ns check, with `scripts/ir-oracle.sh` reviewed.
