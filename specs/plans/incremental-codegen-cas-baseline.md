# Compile-time baseline (B0 of the incremental-codegen plan), 2026-10-05

The one dated snapshot that `specs/plans/incremental-codegen-cas-plan.md` §13 (B0) asks for,
read against §3's go criterion 1. (When this was written the plan lived on the
`plan/incremental-codegen-cas` branch, not yet on `main`.) Do not update these numbers in place; re-run
`scripts/compile-time-bench.sh` and write a new dated file if a later decision needs fresh ones.

## Conditions

- **Date:** 2026-10-05, 11:18–11:27 EDT (`--opt 2` then `--opt 0`, 3 runs per cell).
- **Machine:** Apple M3 Max, 14 cores (10 performance + 4 efficiency), 36 GB, macOS 26.6.1
  (`Darwin 25.6.0 … RELEASE_ARM64_T6031 arm64`), Apple clang 17.0.0 (clang-1700.6.4.2).
- **Compiler:** `a047aa7f` (`origin/main` at branch point). The branch changes no compiler source.
  Harness: `scripts/compile-time-bench.sh` at `14fdbb64`.
- **Load:** 1-minute load average 9–15 during both passes. Other Claude sessions were still
  running on the box, so this is "quiet", not idle. The previous 18 hours ran at load
  100–320 (other sessions' test suites and a Virtualization VM). Two earlier full passes were
  discarded: one at load ~250 (a ~1 s compile took 945 s wall), and one at load 9–22 that read
  ~1.6× slow across the board, with `cpu_ms` inflated by the same factor (probably
  efficiency-core placement). The numbers below agree to within ~3% with a separate topology-only
  rerun and with a hand-run compile taken in the same window.
- **Rows:** `bench/results/2026-10-05-compile-time-arm64-opt2.tsv`,
  `bench/results/2026-10-05-compile-time-arm64-opt0.tsv`.

## `--opt 2`

```
corpus    scenario status    n  total  front    tir   back  back%     cpu   (medians over runs, ms)
small     cold     miss      3   8714   1271   1114   6206     72%    7430
small     warm     src-hit   3     88      -      -      -              30
small     comment  tir-hit   3   1939    383   1145      -            1870
small     leaf     miss      3   2181    379   1154    542     26%    2060
small     sig      miss      3   2174    383   1143    547     26%    2060
small     field    miss      3   2156    377   1137    552     27%    2060
bench     cold     miss      3   8816   1238   1114   6373     73%    7430
bench     warm     src-hit   3     90      -      -      -              30
bench     comment  tir-hit   3   1946    381   1144      -            1880
bench     leaf     miss      3   2127    378   1141    518     25%    2030
bench     sig      n/a
bench     field    n/a
topology  cold     miss      3  25232   1352   1723  22028     88%   23750
topology  warm     src-hit   3     91      -      -      -              30
topology  comment  tir-hit   3   8043    521   1737      -            7950
topology  leaf     miss      3  18759    513   1736  16350     88%   18480
topology  sig      n/a
topology  field    n/a
```

## `--opt 0`

```
corpus    scenario status    n  total  front    tir   back  back%     cpu   (medians over runs, ms)
small     cold     miss      3   6425   1284   1119   3882     62%    5199
small     warm     src-hit   3     92      -      -      -              30
small     comment  tir-hit   3   2179    384   1354      -            1980
small     leaf     miss      3   2219    385   1202    527     25%    2110
small     sig      miss      3   2137    384   1153    505     25%    2050
small     field    miss      3   2136    378   1134    528     26%    2030
bench     cold     miss      3   6043   1249   1092   3613     61%    4930
bench     warm     src-hit   3     84      -      -      -              30
bench     comment  tir-hit   3   1920    371   1135      -            1860
bench     leaf     miss      3   2098    366   1121    505     25%    2000
bench     sig      n/a
bench     field    n/a
topology  cold     miss      3  16080   1338   1682  12925     81%   14870
topology  warm     src-hit   3     81      -      -      -              30
topology  comment  tir-hit   3   7907    499   1705      -            7790
topology  leaf     miss      3  12081    496   1693   9754     82%   11970
topology  sig      n/a
topology  field    n/a
```

`small` = `bench/compile_time_probe.march`, `bench` = `bench/tree_transform.march`,
`topology` = `examples/topology_app`, compiled as `forge run` compiles it
(`--topology .forge/topology.json`).

## What "back" contains

The harness's back bucket is `t[clang] − t[opt]`. Nothing is stamped between `opt` and
`llvm-emit`, so the bucket also holds the alloc-contract analyses and the CAS SCC build and
hashing that run before the post-TIR cache lookup. A tir-hit isolates that work, since the
lookup succeeds before any emission: topology's comment edit is 8.0 s wall against 2.3 s of
stamped buckets. A hand-run topology compile in the same window, stamped:

| `--opt 2`, warm `$HOME`, fresh project (miss) | s | share of 18.2 s |
|---|---|---|
| parse … typecheck | 0.6 | 3% |
| lower … opt (whole-program TIR) | 1.7 | 9% |
| post-opt, pre-lookup (SCC build, hashing, contracts) | ~5.7 | ~31% |
| llvm-emit | ~1.9 | ~10% |
| clang | 8.3 | 45% |

At `--opt 0` the same compile is 12.1 s, and clang drops to 2.1 s while everything before it is
unchanged. A macOS `sample` of the post-opt window attributes it almost entirely to
`lib/cas/scc.ml`'s `refs_in_expr`. It runs `List.mem` against the list of every definition name
for each variable reference in the whole program (stdlib included), which is
O(references × definitions). Blake3 and serialisation barely register. A post-TIR cache **hit**
pays this cost too: most of topology's 8.0 s comment edit is this scan.

## Reading against §3, criterion 1

> B0 shows a warm leaf-edit compile of `examples/topology_app` at `--opt 2` over ~10 s with the
> back-end bucket above 60% of it.

**As the harness measures it: yes.** The leaf edit takes 18.8 s, with 88% in the back bucket.
**As the criterion means it (LLVM emission plus clang): borderline.** Emit plus clang is
~10.2 s, ~55% of the compile: just over the 10 s line and just under the 60% line. The other
~31% is a quadratic list scan in the CAS SCC build. It is neither front-end nor back-end work,
and it is a small, local fix (a hash set; filed separately). With it removed, the same edit
would take ~12.5 s, ~80% of it emit plus clang, and the criterion would pass cleanly. clang at
`-O2` over the whole program (8.3 s) would then be the single largest cost, and it is exactly
what B3–B5 split up.

Recommendation, in order:
1. Fix the `Scc.refs_in_expr` scan first. It is cheaper than any part of B3–B5 and takes ~30%
   off every compile that reaches the post-TIR stage, cache hits included.
2. Then re-run B0. If the result holds (~12.5 s, back end ~80%), criterion 1 is met. §3's
   "borderline" branch, the two-object stdlib/user seam (B3-lite), is the proportionate next
   step, because the probe and `tree_transform` show a whole-program floor of ~2 s that
   per-function units would not remove.
3. Criteria 2 (does anyone sit in an edit-compile loop?) and 3 (A1 and A5 green in CI) are not
   B0's to answer. B3–B5 need all three.

Other readings:
- **Small programs:** leaf, sig and field edits all cost ~2.1–2.2 s at either opt level, of
  which ~1.1 s is whole-program TIR work over the stdlib and ~0.5 s is back end. The
  incremental back end has nothing to win there.
- **Cold:** a fresh clone pays ~6.5 s on top of an edit for small programs (C runtime and stdlib
  caches) and ~6.5 s for topology. The runtime object cache already does its job.
- **Caching works as designed:** no-change rebuilds are source-level hits (~0.1 s), and
  comment-only edits are post-TIR hits on every corpus. The probe's `sig` edit needed a fix
  before it measured a miss: a non-recursive function is inlined away, so a rename of it
  never reaches the post-TIR key.
- **Found along the way** (each filed separately): the first compile in a fresh `$HOME` gets a
  different post-TIR key than every later compile of the same source; and compiling
  `topology_app` without its `--topology` digest emits invalid LLVM IR.
