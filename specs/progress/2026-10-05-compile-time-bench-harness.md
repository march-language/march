# Compile-time measurement harness (B0 of the observability/incremental plan)

`scripts/compile-time-bench.sh` plus its edit target `bench/compile_time_probe.march`.
This is phase B0 of `specs/plans/incremental-codegen-cas-plan.md`: the measurement that
decides whether the plan's incremental-compilation phases (B3–B5) are worth their risk.
Nothing in the plan had been timed; the ordering rested on reading the code.

## What it does

Drives `march --compile --timings` over three programs (the probe, `bench/tree_transform.march`,
`examples/topology_app`) under six scenarios — cold caches, warm no-change, comment-only edit,
leaf body edit, signature edit (rename at definition and all call sites), record layout edit — and
folds the `[timings]` stamps into three buckets: front end (through `typecheck`), whole-program TIR
(`lower` through `opt`), back end (`llvm-emit` + `clang`). Medians over `--runs` (default 3). Every
run of an edit scenario applies a *different* edit so each is a fresh cache miss rather than a hit on
the previous run's artifact.

Signature and layout edits must leave the program compilable, so they run only on the probe, which
carries `-- BENCH:*` marker lines the script's sed recipes match. `tree_transform` and `topology_app` get a
body edit through a known literal. Unavailable scenarios print `n/a`.

Cold means a fresh `$HOME` **and** a fresh project directory, so it includes the stdlib AST/tcenv
caches, the C-runtime object cache and the CAS: what a new clone pays.

## Status

**Run for the first time on 2026-10-04/05** (Apple M3 Max, toolchain at `a047aa7f` + this branch).
The baseline is `specs/plans/incremental-codegen-cas-baseline.md`; the per-run rows are under
`bench/results/`. The first run needed four fixes (the probe in one commit, the script in another):

- **The probe compiled first try, but `sig` was a post-TIR hit.** The TIR hash includes function
  names, yet renaming `sig_target` changed nothing because its `x * 2` body was inlined into both
  callers and the function dropped by `opt`. It is now tail-recursive, so it survives `opt` and a
  rename changes the callers. All edited variants verified by hand to miss and print the right value.
- **`topology_app` has no `main`.** `forge run` generates it from `topology.toml` through the digest
  `forge topology check` writes; the script now stages the whole project, writes the digest once and
  passes `--topology .forge/topology.json`. Compiling the bare entry emitted invalid LLVM IR (filed
  separately). It also gained a leaf edit, since the plan's gate is stated on topology's leaf edit.
- **The first compile in a fresh `$HOME` gets a different post-TIR key** than every later compile of
  the same source (a compiler determinism bug, filed separately), so priming in a fresh `$HOME` made
  topology's comment edit a miss. An untimed warm-up compile now runs first.
- **The machine was heavily loaded** (load average 100–270 on 14 cores from other sessions), so a
  `cpu_ms` column (user+sys including clang) was added; at that load one compile took 945 s wall for
  0.9 s of CPU.

**Result (§3 criterion 1): borderline, and the reason is a quick fix.** A topology leaf edit at
`--opt 2` takes 18.8 s, 88% in the harness's back bucket. But ~5.7 s of that is
`lib/cas/scc.ml`'s O(references × definitions) `List.mem` scan, which runs before the post-TIR
cache lookup. LLVM emission plus clang alone is ~10.2 s, ~55%. Fix the scan, then re-run B0.
The baseline file has the reading in full.
