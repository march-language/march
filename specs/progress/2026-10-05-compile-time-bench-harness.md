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
carries `-- BENCH:*` marker lines the script's sed recipes match. `tree_transform` gets a body edit
through a known literal; `topology_app` gets cold/warm/comment. Unavailable scenarios print `n/a`.

Cold means a fresh `$HOME` **and** a fresh project directory, so it includes the stdlib AST/tcenv
caches, the C-runtime object cache and the CAS: what a new clone pays.

## Status

**Written but not yet run.** The authoring environment had no `dune`/`opam`, so neither the script
nor the probe program has been executed; the probe's syntax was modelled line by line on
`test/snapshots/src/record_update.march`, `closure_hof.march` and `stdlib/list.march`'s
signatures, but it has not been compiled. First run on a machine with a toolchain:

```
dune build --root . bin/main.exe
scripts/compile-time-bench.sh --corpus small --runs 1   # smoke: probe compiles, recipes apply
scripts/compile-time-bench.sh                            # the real thing, ~10–20 min
```

Commit the first full table once as `specs/plans/incremental-codegen-cas-baseline.md` (a dated
snapshot, not a running count). The plan's §3 gate reads off that table.
