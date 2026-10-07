# Compile-time baseline 2 (B0 re-run), 2026-10-07

The second dated snapshot for `specs/plans/incremental-codegen-cas-plan.md` §13 (B0), read
against §3's go criterion 1. The first, `specs/plans/incremental-codegen-cas-baseline.md`
(2026-10-05), found a quadratic post-opt window and asked for a re-run once it was fixed. #807
fixed it. Do not update these numbers in place; re-run `scripts/compile-time-bench.sh` and
write a new dated file.

## Verdict on criterion 1: **pass**

> B0 shows a warm leaf-edit compile of `examples/topology_app` at `--opt 2` over ~10 s with the
> back-end bucket above 60% of it.

| topology leaf edit, `--opt 2`, median of 3 | value | threshold |
|---|---|---|
| wall | 14.5 s (cpu 14.1 s) | > ~10 s |
| back end = `llvm-emit` + `clang` | 11.1 s | |
| back end, share of wall | **76%** | > 60% |
| back end, share of stamped buckets | 77% | |

Both lines are cleared with margin, and the result does not hinge on the load. Load inflates
every bucket by roughly the same factor (see Conditions), which leaves the share alone. Deflating
the wall time by the ~1.2× this pass reads slow against the first baseline still leaves ~12 s.
The first baseline predicted ~12.5 s with emit plus clang at ~80%; this is that prediction, read
on a busier box.

Criteria 2 (does anyone sit in an edit-compile loop?) and 3 (A1 and A5 green in CI) are not
B0's to answer. B3–B5 now wait on those two only.

## Conditions

- **Date:** 2026-10-07, 10:05–10:15 EDT (`--opt 2` 10:05–10:11, then `--opt 0` 10:11–10:15,
  3 runs per cell). Hand-run compile 10:15–10:16.
- **Machine:** Apple M3 Max, 14 cores (10 performance + 4 efficiency), 36 GB, macOS 26.6.1
  (`Darwin 25.6.0 … RELEASE_ARM64_T6031 arm64`), Apple clang 17.0.0 (clang-1700.6.4.2). The
  same machine as the first baseline.
- **Compiler:** `c31ef539` (`origin/main` at branch point; includes #807, #805 and #818). The
  branch changes no compiler source.
  Harness: `scripts/compile-time-bench.sh` at `e54b31bc`, which changed the bucket definitions
  (next section).
- **Load:** 1-minute load average, sampled every 30 s: **11.6–22.4** during `--opt 2`,
  **18.6–25.2** during `--opt 0`. Other Claude sessions were running test suites throughout. The
  run was gated to start below 12 and did, but the load rose while it ran. This is busier than
  the first baseline's 9–15. Same-scenario buckets read ~1.2× the first baseline's on work
  neither PR touched: the small probe's `lower`…`opt` is 1.36 s against 1.15 s, and its front
  end is 1.42 s against 1.27 s cold. `cpu_ms` stays within ~4% of wall for the topology medians,
  so the slowdown is more likely efficiency-core placement than waiting for a core. One topology
  leaf run (19.1 s wall, 15.0 s cpu) caught a load spike; the median excludes it.
- **Rows:** `bench/results/2026-10-07-compile-time-arm64-opt2.tsv`,
  `bench/results/2026-10-07-compile-time-arm64-opt0.tsv`.
- `topology` is compiled as `forge run` compiles it (`--topology .forge/topology.json`), as in
  the first baseline.

## Bucket definitions changed

The first baseline's back bucket was `t[clang] − t[opt]`, which also held the post-opt window.
Since #807 that window has its own stamps (`alloc-contract`, `cas-hash`). Criterion 1 means LLVM
emission plus clang, so the harness now cuts at `cas-hash`:

| bucket | first baseline | this baseline |
|---|---|---|
| front end | parse … `typecheck` | unchanged |
| whole-program TIR | `lower` … `opt` | `lower` … `opt`, `alloc-contract`, `cas-hash` |
| back end | `t[clang] − t[opt]` | `t[clang] − t[cas-hash]` = `llvm-emit` + `clang` |

The TSVs carry `post_opt_ms` = `t[cas-hash] − t[opt]`, and the harness prints a second table in
the old buckets from the same runs. Compare that one with the first baseline. A `back%w` column
(back end over wall) now sits beside `back%` (back end over the stamped buckets).

## `--opt 2`

```
back end = llvm-emit + clang (t[clang] - t[cas-hash])
corpus    scenario status    n  total  front    tir   back  back%  back%w     cpu   (medians over runs, ms)
small     cold     miss      3   9207   1424   1550   6196     68%     67%    7920
small     warm     src-hit   3     79      -      -      -                      30
small     comment  miss      3   2397    384   1550    371     16%     15%    2310
small     leaf     miss      3   2473    387   1595    377     16%     15%    2340
small     sig      miss      3   2468    386   1568    382     16%     15%    2310
small     field    miss      3   2411    389   1539    384     17%     16%    2290
bench     cold     miss      3   8979   1416   1526   5949     67%     66%    7850
bench     warm     src-hit   3     77      -      -      -                      30
bench     comment  miss      3   2356    382   1548    345     15%     15%    2280
bench     leaf     miss      3   2436    385   1597    356     15%     15%    2320
bench     sig      n/a     
bench     field    n/a     
topology  cold     miss      3  21511   1533   2787  16945     80%     79%   19709
topology  warm     src-hit   3    176      -      -      -                      50
topology  comment  miss      3  15224    694   2915  11525     76%     76%   14399
topology  leaf     miss      3  14484    543   2764  11060     77%     76%   14090
topology  sig      n/a     
topology  field    n/a     

old buckets, same runs: back end = t[clang] - t[opt] (also holds alloc-contract + cas-hash)
corpus    scenario status    n  total  front    tir   back  back%  back%w     cpu   (medians over runs, ms)
small     cold     miss      3   9207   1424   1318   6410     70%     70%    7920
small     warm     src-hit   3     79      -      -      -                      30
small     comment  miss      3   2397    384   1330    595     26%     25%    2310
small     leaf     miss      3   2473    387   1362    599     26%     24%    2340
small     sig      miss      3   2468    386   1347    601     26%     24%    2310
small     field    miss      3   2411    389   1324    599     26%     25%    2290
bench     cold     miss      3   8979   1416   1309   6164     69%     69%    7850
bench     warm     src-hit   3     77      -      -      -                      30
bench     comment  miss      3   2356    382   1322    566     25%     24%    2280
bench     leaf     miss      3   2436    385   1358    578     25%     24%    2320
bench     sig      n/a     
bench     field    n/a     
topology  cold     miss      3  21511   1533   2171  17603     83%     82%   19709
topology  warm     src-hit   3    176      -      -      -                      50
topology  comment  miss      3  15224    694   2275  12166     80%     80%   14399
topology  leaf     miss      3  14484    543   2129  11695     81%     81%   14090
topology  sig      n/a     
topology  field    n/a     
```

## `--opt 0`

```
back end = llvm-emit + clang (t[clang] - t[cas-hash])
corpus    scenario status    n  total  front    tir   back  back%  back%w     cpu   (medians over runs, ms)
small     cold     miss      3   7327   1485   1580   4183     58%     57%    5780
small     warm     src-hit   3     92      -      -      -                      40
small     comment  miss      3   2643    421   1715    379     15%     14%    2450
small     leaf     miss      3   2598    409   1642    431     17%     17%    2390
small     sig      miss      3   2664    408   1732    394     16%     15%    2420
small     field    miss      3   2529    421   1655    357     15%     14%    2390
bench     cold     miss      3   8225   1969   1654   4452     55%     54%    6190
bench     warm     src-hit   3     94      -      -      -                      30
bench     comment  miss      3   2773    428   1785    364     14%     13%    2460
bench     leaf     miss      3   2624    417   1695    341     14%     13%    2420
bench     sig      n/a     
bench     field    n/a     
topology  cold     miss      3  13248   1702   2732   8728     66%     66%   11670
topology  warm     src-hit   3    109      -      -      -                      40
topology  comment  miss      3   8913    558   2976   5379     60%     60%    8270
topology  leaf     miss      3   8418    547   2791   4984     60%     59%    8090
topology  sig      n/a     
topology  field    n/a     

old buckets, same runs: back end = t[clang] - t[opt] (also holds alloc-contract + cas-hash)
corpus    scenario status    n  total  front    tir   back  back%  back%w     cpu   (medians over runs, ms)
small     cold     miss      3   7327   1485   1358   4407     61%     60%    5780
small     warm     src-hit   3     92      -      -      -                      40
small     comment  miss      3   2643    421   1485    609     24%     23%    2450
small     leaf     miss      3   2598    409   1411    662     27%     25%    2390
small     sig      miss      3   2664    408   1507    619     24%     23%    2420
small     field    miss      3   2529    421   1426    599     24%     24%    2390
bench     cold     miss      3   8225   1969   1430   4676     58%     57%    6190
bench     warm     src-hit   3     94      -      -      -                      30
bench     comment  miss      3   2773    428   1498    594     24%     21%    2460
bench     leaf     miss      3   2624    417   1467    589     24%     22%    2420
bench     sig      n/a     
bench     field    n/a     
topology  cold     miss      3  13248   1702   2061   9353     71%     71%   11670
topology  warm     src-hit   3    109      -      -      -                      40
topology  comment  miss      3   8913    558   2291   6074     68%     68%    8270
topology  leaf     miss      3   8418    547   2151   5622     68%     67%    8090
topology  sig      n/a     
topology  field    n/a     
```

`small` = `bench/compile_time_probe.march`, `bench` = `bench/tree_transform.march`,
`topology` = `examples/topology_app`.

## One topology leaf-edit compile, stamped

`--opt 2`, warm `$HOME`, a project primed by two compiles, then `{ factor: 77 }` edited in. Load
average 21 at the start, 23 at the end. Wall 15.71 s, user 13.90 s, sys 0.49 s.

| stamp window | s | share of 15.63 s | first baseline (18.2 s) |
|---|---|---|---|
| parse … `typecheck` | 0.70 | 4% | 0.6 |
| `lower` … `opt` | 2.26 | 14% | 1.7 |
| `alloc-contract` | 0.42 | 3% | } ~5.7 |
| `cas-hash` | 0.54 | 3% | } |
| `llvm-emit` | 3.48 | 22% | ~1.9 |
| `clang` | 8.23 | 53% | 8.3 |
| emit + clang | 11.72 | **75%** | ~10.2 (~55%) |

Raw stamps (cumulative):

```
[timings]  0.000s  parse
[timings]  0.002s  desugar
[timings]  0.003s  resolve-imports
[timings]  0.041s  stdlib-load
[timings]  0.696s  typecheck
[timings]  0.947s  lower
[timings]  1.115s  mono
[timings]  1.138s  fusion
[timings]  1.212s  defun
[timings]  1.553s  perceus
[timings]  1.704s  drop
[timings]  1.788s  escape
[timings]  2.957s  opt
[timings]  3.381s  alloc-contract
[timings]  3.916s  cas-hash
[timings]  7.398s  llvm-emit
[timings] 15.631s  clang
```

Two more hand-runs right after this one hit load 26–40. Wall ran 23–26 s against 16 s of CPU,
so they are discarded.

## Reading it

- **#807 did what it said.** The post-opt window (`alloc-contract` + `cas-hash`) is ~0.96 s on
  topology, down from ~5.7 s. On the small corpora it is ~0.22 s.
- **clang at `-O2` over the whole program is the single largest cost**, ~8.2 s and unchanged.
  This is what B3–B5 split up.
- **`llvm-emit` looks larger than in the first baseline:** ~3.5 s against ~1.9 s in one hand-run
  each, at different loads. The harness's back bucket agrees in direction: 11.1 s here against
  ~10.2 s for emit plus clang then. Since `a047aa7f` the emit window gained `finish_ir`, with the
  rc-trace rewrite off by default, and whatever #805/#818 and the shell and observe work added
  to the module. This is not attributed. A same-box A/B of `a047aa7f` against `c31ef539` at low
  load would settle it. It does not change the verdict; it only makes the back end a larger
  share.
- **At `--opt 0`** the topology leaf edit is 8.4 s with the back end at 60%. Criterion 1 is
  stated at `--opt 2`, so this is context, not the gate.
- **Small programs** still pay a ~2.4 s whole-program floor on every edit. Of that, ~1.55 s is
  whole-program TIR work over the stdlib and only ~0.37 s is emit plus clang. Per-function units
  would not touch it. This is why the first baseline's recommendation of **B3-lite** (the
  two-object stdlib/user seam, plan §3 and §16) over the full N-unit split still stands.

### Comment edits now miss: a driver bug, not a cache-key change

Every `comment` row was a `tir-hit` on 2026-10-05 and is a `miss` here. The post-TIR key is
unchanged by a comment: `MARCH_DEBUG_CASFLAGS=1` prints the same `src=` digest, and the compiler
prints `compiled out (cached)`. Then it emits and links anyway. In `bin/main.ml` a statement
added after `else` without `begin … end` ends the `if` early, so every compile that reaches the
lookup runs `llvm-emit` and `clang`. It came in with `21a0dd568` (`--rc-trace` site ids).
Misses run the pipeline once, so the leaf, sig and field rows, and the verdict, are unaffected.
The comment rows here measure the bug, not the cache. Filed as
`specs/todos/2026-10-07-post-tir-cache-hit-still-emits-and-links.md`. Once it is fixed, the
topology comment edit should fall to about the middle bucket's ~3.6 s plus process overhead.

### Cold and warm `$HOME` agree

The harness still primes `$HOME` with a throwaway compile before priming the project's CAS, as
it did for the first baseline. A by-hand check on the probe now gives the same post-TIR key for
the first compile in a fresh `$HOME` and for every later one, which confirms #805/#818.
