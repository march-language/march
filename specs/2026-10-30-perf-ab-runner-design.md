# Perf A/B runner

**Status:** implemented 2026-10-30 (`scripts/perf-ab.sh`, `scripts/perf-ab-measure.py`,
`.github/workflows/perf-ab.yml`).
**Context:** road to 1.0 (`specs/plans/2026-09-28-road-to-1.0.md`), phases 2 and 3. The inline
small-string capacity (`MARCH_SSO_MAX`) is to be tuned and then frozen as the 1.0 ABI, chosen by a
same-box A/B: best median, no regression over 3% elsewhere. The Int overflow trap's cost is to be
measured the same way. Per-benchmark performance targets are still undecided; this runner's numbers
are meant to inform them.

## Problem

`specs/benchmarks.md` records the lesson ("Compute-benchmark sweep, 2026-07-31"): an absolute
millisecond figure is one machine on one day. `hash_map_bench` read 25-29% over its documented
baseline on 9 of 9 cases with tight variance and was in fact 13% *faster* than the baseline commit;
only building the old compiler and racing the two on the same box settled it. Doing that by hand
takes a worktree, a build, a private cache, an interleaving discipline and a statistic, and every
step has a known way to lie. This runner does all of it in one command.

## Usage

```bash
scripts/perf-ab.sh                         # last v* tag vs HEAD
scripts/perf-ab.sh v0.6.0 my-branch        # any two refs
scripts/perf-ab.sh --cand-dir .            # last tag vs this checkout, uncommitted edits included
scripts/perf-ab.sh --benches "fib list_ops" --runs 21
scripts/perf-ab.sh --self-test aa          # HEAD vs HEAD: must be all within noise
scripts/perf-ab.sh --self-test red         # HEAD vs HEAD + slowed runtime: must go red
```

Exit 0: nothing slower. 1: a regression (timing or counter). 2: the comparison is invalid (a build
failed, a benchmark crashed, the arms printed different answers). Writes `table.md` and
`results.json` (every sample) to `--out DIR`.

## Decisions

### Benchmark set

`fib tree_transform binary_trees list_ops string_build string_pipeline string_scan string_case
string_split_large string_slice_walk string_small_churn iolist_template json_stream
json_stream_strings`. Each is single-threaded and runs 20 ms to 1 s warm on an M3 Max.

| area | benchmarks | why |
|---|---|---|
| call/arith core | `fib` | the Int overflow trap's worst case: an add and a compare per call |
| Perceus/FBIP | `tree_transform` | `specs/benchmarks.md`'s mapping for RC changes |
| allocation | `binary_trees` | allocator and drop path |
| closures/HOFs | `list_ops` | defunctionalisation and the inline RC fast path |
| string ABI | the seven `string_*`, `iolist_template` | where the small-string capacity will be chosen; `string_small_churn` is the SSO-shaped one |
| application | `json_stream`, `json_stream_strings` | parse-heavy, many short strings |

Excluded on purpose:

- **Multi-threaded benchmarks** (`string_parallel_scan`, `par_*`, actors): core contention makes
  both the timing and the allocation counters nondeterministic, and they measure the scheduler more
  than the compiler.
- **HTTP** (`http_get*`): it needs a load generator and a peer, and `specs/benchmarks.md` Run 5
  showed macOS loopback caps it at ~30k req/s regardless of March. JSON is the application workload
  instead. An HTTP A/B belongs on the Linux droplet setup that Run 5 used.
- **`hash_map_bench`**: run-to-run spread around 30% on a loaded box, which would widen every CI.

The candidate's copy of each benchmark is compiled by **both** compilers, so the program under test
never varies; the runner prints a note when a benchmark's source differs between the two refs. A
benchmark the baseline compiler rejects is listed as "not compared" rather than failing the run.

### Isolation

- Each ref is built in its own detached `git worktree` under `--work` (default
  `$TMPDIR/march-perf-ab/tree-<sha>`), with `dune build --root . bin/main.exe`. A built tree is
  reused on the next run, keyed by commit.
- Each arm compiles with `MARCH_STDLIB` and `MARCH_RUNTIME_DIR` pointing at its own tree (so the
  compilers never share a stdlib or a staged runtime copy), a private `HOME` (so neither the global
  CAS `~/.march/cas` nor `~/.cache/march` can serve one arm's artifact to the other) and its own
  cwd (the project CAS is `<cwd>/.march/cas`). Both env vars exist in v0.6.0.
- Always `--compile --opt 2`.

### Measurement

- **Warmup.** Each binary runs three times untimed before measuring (one counter run, two plain).
  Measured while building this: the first exec of a freshly written binary on macOS costs 300-600 ms
  (a 30 ms `list_ops` read 381 ms), which would swamp everything.
- **Interleaving.** Rounds are the outer loop and benchmarks the inner one; within each, A and B run
  back to back and the order alternates with `(round + benchmark index) % 2`. A load spike or
  thermal drift therefore lands on both arms, and neither arm always takes the first slot
  (`project_bench_first_position_warmup`: a ~25% first-slot penalty on byte-identical code).
- **Run count.** 15 rounds by default. About 3 s per arm per round for the whole set, so roughly
  90 s of measurement.
- **Two clocks.** Wall time per run, and the child's user+sys CPU time (the `RUSAGE_CHILDREN` delta
  around each run, exact because runs are sequential). The verdict is on CPU time by default
  (`--metric cpu|wall`): every benchmark in the set is single-threaded compute, and on a shared box
  CPU time excludes the time spent descheduled, which is most of the load contamination. Both are
  always reported.
- **Statistic.** Median per arm; ratio = median(B)/median(A); a 95% percentile-bootstrap CI of that
  ratio (2000 resamples, arms resampled independently, fixed seed so identical samples give
  identical CIs).
- **Verdict.** `slower` only when the CI's lower bound is above 1.00 **and** the ratio exceeds
  1 + threshold (default 3%, the owner's "no regression over 3%"); `faster` symmetrically;
  otherwise `~`. A real but tiny change (tight CI around 1.005) and a large but unproven one (1.06
  with a CI straddling 1.0) are both "within noise", which is what a gate wants.
- **Output check.** The arms' stdout must match after masking printed timings (`ms=88`,
  `12 ms`, `TIME_MS 10.1`). A candidate that got faster by computing something else is not faster.
- **Load.** Load average is recorded at start and end and a warning printed when it exceeds half the
  core count; the run is not refused, because the interleaved ratios stay comparable and the
  counters are unaffected.

### Noise-free gates: allocation counters

One untimed run per arm with `MARCH_STRING_STATS=1` collects the runtime's exact counters
(`runtime/march_runtime.c`, `str_stats_dump`): string `allocs`, `alloc_bytes`, `copy_bytes`,
`peak_live_bytes`, non-string `obj_allocs` / `obj_alloc_bytes`, and `live_objs` (the
`live_allocs()` gauge at exit, the leak signal). These do not move with load, so for single-threaded
benchmarks any increase is a real change in the work done. An increase in a gated counter is a
regression unless `--no-counter-gate` (use that when the change is *meant* to alter allocation, as
the small-string tuning is). `peak_live_bytes` is reported but not gated. Byte counters get 64 bytes
of slack: the A/A self-test caught `json_stream` allocating two more bytes in one run than another,
because it prints its own elapsed time and `ms=100` is one digit longer than `ms=88`.

### Self-tests

The runner is only trustworthy if it is shown to go green when it should and red when it should
(CLAUDE.md: prove an oracle goes RED before trusting a GREEN).

- `--self-test aa`: HEAD against HEAD, the benchmarks compiled twice into separate binaries. Passes
  iff every verdict is `~`, every counter is identical and the comparison is valid.
- `--self-test red`: HEAD against a copy of HEAD whose `runtime/march_runtime.c` spins 200
  iterations of a volatile loop at the top of `march_alloc`. The work and the allocation counts are
  unchanged, only slower. Passes iff `binary_trees`, `tree_transform` and `list_ops` are reported
  `slower` and no counter is flagged. `fib` allocates nothing and is not asserted either way.

Results on the development box are in `specs/progress/2026-10-30-perf-ab-runner.md`.

### CI

`.github/workflows/perf-ab.yml`: nightly at 03:00 UTC and on dispatch (inputs: `base`, `cand`,
`runs`, `metric`, `self_test`, `fail_on_regression`). One `ubuntu-24.04` job, full history
(`fetch-depth: 0`) for the tag. The table goes to the job summary and, with `results.json`, to the
`perf-ab` artifact. Not per-PR: it needs a quiet runner and the org has 20 shared Linux slots. A
hosted runner is a shared VM, so its absolute times mean nothing; its ratios are still sound. The
job is red on an invalid comparison or a failed self-test; on a regression only when dispatched
with `fail_on_regression`, since the nightly is a report while per-benchmark targets are undecided.

## Not done

- Per-benchmark targets: still an open decision; the nightly's tables are the input to it.
- Measuring the Int overflow trap: the runner is ready (`fib`, `list_ops`, and an index-loop
  benchmark if that session adds one); the measurement waits for that change.
- An HTTP A/B on a quiet Linux box, as above.
