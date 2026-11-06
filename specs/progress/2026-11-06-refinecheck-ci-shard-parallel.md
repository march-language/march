# refinecheck CI shard: groups in parallel processes, stdlib verdicts seeded

**Problem.** The `test (ubuntu-24.04, refinecheck)` shard's Test step took 50-77 min on
`main` in the first week of November 2026, against its 75-minute limit, and was the
workflow's long pole. It was ~10 min in mid-October, ~21-27 min on 2026-11-02/03, and
51+ min from the first `main` run after merge trains #1074/#1075 (the bundled-z3 work).

**Cause.** Profiled locally, each of the 203 alcotest groups run alone with
`MARCH_REFINE_RLIMIT_LOG` and `MARCH_REFINE_Z3_LOG`:

- The suite is one alcotest process, run serially on a 4-vCPU runner.
- It sent 209,935 z3 queries, of which 96% were byte-identical repeats. About 530 cases
  run the real compiler in a fresh directory (so no other test's verdict is reused), and
  each such `--check` re-proves the stdlib's own ~370 obligations from a cold
  `.march/cas/vc`. Groups with 1,000+ queries were 78% of the wall time.
- 133 queries exhaust the 3,000,000-step rlimit, which replaced the 3 s timeout on
  2026-11-03; they are 74% of all z3 steps (1.3-28 s each on this Mac).
- The doubling on 2026-11-03 coincides with CI's z3 changing from apt's 4.8.12 to a
  static musl build of 4.16.0, while the rlimit measurement
  (`2026-11-02-z3-rlimit-measurement.md`) found the suite 5% faster on macOS, where the
  binary did not change. Not confirmed on Linux; left as a follow-up.

**Fix.**

- `Test_helpers.run_groups` replaces `Alcotest.run` in `test_refinecheck`. With
  `MARCH_TEST_PROCS=N` it runs each group in a child process (the same executable with
  `MARCH_TEST_GROUP=<group>`), N at a time, handed out in list order to whichever child is
  free: with the measured group times that is within 5% of the best split, so there is no
  weight table. Each child's output prints whole; a summary names the slowest groups and
  every failed one, and the parent exits 1 if any child exited non-zero, died, or printed
  no alcotest summary. Without the variable, or with arguments other than -e/-q/-c, it is
  `Alcotest.run` as before. CI's refinecheck shard sets `MARCH_TEST_PROCS=$(nproc)`;
  `scripts/run-tests.sh refinecheck` defaults it to 4.
- `Test_helpers.seed_vc_cache dir` writes the stdlib's verdicts, computed once per process
  by the compiler under test (`--check` of an empty module in a private directory and
  HOME), into a fresh project's `.march/cas/vc`. The generic fresh-directory helpers call
  it (`Test_refine_unfold.run`/`run_lib`, `Test_refine_reflect.run`/`pinned`,
  `Test_refine_lemma.in_dir`, the infer fixtures in `test_refinecheck.ml`); the tests about
  warm and cold caches build their own directories and are unchanged. A seeded run reaches
  the verdicts a cold one would (the key is the query text, z3 version, limits and
  platform; z3 under a step limit is deterministic); only the test's own obligations are
  solved. `MARCH_TEST_VC_SEED=0` turns it off.
- `Vc_cache.store` and `store_core` write a temp file and rename it into place. Parallel
  processes share the test cwd's cache (in-process tests use `~root:(Sys.getcwd ())`), and
  an in-place write let a concurrent reader parse half a `sat` model. Same for two user
  compiles of one project. Unit test: `test_refine`, "store replaces an entry and leaves no
  temp file".

**Measured** (14-core M-series Mac shared with other sessions, so wall times are noisy;
load average in brackets):

| Run | Wall | Result |
|---|---|---|
| Profile, each group alone, 6 at a time, no seed (sum of group times) | 3,322 s [25-60] | 203/203 pass |
| `MARCH_TEST_PROCS=4`, seeded | 662 s [44 → 16] | 203 groups, 2,347 tests, all pass |
| `MARCH_TEST_PROCS=4`, `MARCH_TEST_VC_SEED=0` | 556 s [16] | 203 groups, 2,347 tests, all pass |

Seeding alone, interleaved seeded/cold runs of one group, CPU time of the process tree:
`reflect-ctor` 44.1 / 43.4 s seeded vs 59.1 / 60.1 s cold (−27%); `law-coverage` 75.5 /
88.0 s vs 108.7 s (−19 to −31%). `reflect-ctor` sends 610 z3 queries seeded, 13,289 cold.
On this Mac z3 answers the stdlib's 370 queries in ~0.6 s, so most of a cold run's extra
cost is building and encoding them; on CI's slower z3 the saving should be larger. The CI
number is not measured yet: the first CI run of this change gives it.

The first parallel run also showed the failure path: a concurrent `dune build` in the same
tree deleted `_build/default/test/_build/_tests` (dune removes files it does not own there;
the serial suite logs to the same place), three children died with exit 125, and the
summary listed them and the parent exited 1. Each passed when re-run alone.

**Not done.**

- Measure glibc vs static-musl z3 4.16.0 on a Linux runner, on the same queries.
- `run_codegen` and `run_compiler` are single alcotest processes too; `run_groups` applies
  to them unchanged, once their groups are checked for shared state.
- Infer-cli cases still run with `HOME=<fresh dir>`, so each rebuilds the stdlib
  typecheck caches (~2 s per run).
