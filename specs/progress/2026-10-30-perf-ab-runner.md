# Perf A/B runner (2026-10-30)

`scripts/perf-ab.sh BASE CAND` builds both compilers in their own detached worktrees, compiles the
fixed benchmark set with each (`--compile --opt 2`, private `HOME`, per-arm `MARCH_STDLIB` /
`MARCH_RUNTIME_DIR` / cwd), runs the binaries interleaved with alternating order after three untimed
warmups, and prints median times, the B/A ratio with a bootstrap 95% CI for wall and CPU time, a
verdict (CI excludes 1.00 and |ratio-1| > 3%), and the `MARCH_STRING_STATS` allocation counters,
which are gated. Measurement core: `scripts/perf-ab-measure.py`. CI: `.github/workflows/perf-ab.yml`
(nightly 03:00 UTC + dispatch). Design: `specs/2026-10-30-perf-ab-runner-design.md`.

No benchmark was added, so `test/test_bench_gate.ml` is unchanged.

## Evidence (M3 Max, 14 cores, 10 rounds, heavily loaded box)

- **`--self-test aa`** (HEAD 5d78b341b against itself, load 19 → 14): PASS. 14/14 within noise,
  all counters identical. CPU-time CIs were about ±3% (e.g. fib 1.010 [0.993, 1.026]); wall-time
  CIs reached ±20% on the 20 ms benchmarks, which is why the verdict defaults to CPU time.
- **`--self-test red`** (HEAD against HEAD with a 200-iteration spin in `march_alloc`, load 27 → 31):
  PASS, exit 1 from the comparison as intended. 9 slower (binary_trees 19.97×, list_ops 17.5×,
  tree_transform 2.02×, string_split_large 12.3×, iolist_template 12.0×, json_stream 5.5×, …), counters
  unchanged. fib, string_scan, string_case, string_slice_walk and string_small_churn stayed `~`:
  they do not allocate through `march_alloc` in their hot loops, which is itself useful to know for
  the string-ABI work.
- **v0.6.0 against HEAD** (load 15 → 17): exit 0. 0 slower, 5 faster (binary_trees 0.943,
  list_ops 0.926, string_pipeline 0.916, string_scan 0.788, json_stream_strings 0.817, CPU), 9
  within noise, counters identical on all 14.

## Found while building it

- The first exec of a freshly written binary on macOS costs 300-600 ms (a 30 ms `list_ops` read
  381 ms cold). Any harness that times a binary's first run measures code-signing, not March.
- The first A/A run failed on purpose-built strictness: `json_stream` and `json_stream_strings` print
  their own elapsed time, so `alloc_bytes`/`copy_bytes` vary by a few bytes between identical
  binaries (`ms=88` vs `ms=100`). Byte counters now get 64 bytes of slack; object counts get none.
- A `\s*` in the timing mask let `checksum=280000\nms=88` swallow the checksum; the mask is
  horizontal-whitespace only.

## Follow-ups

- Measure the Int overflow trap with it once that lands (`fib`, `list_ops`, an index loop).
- Choose `MARCH_SSO_MAX` with it (`--no-counter-gate`, since that change is meant to alter
  allocation).
- First CI run: dispatch `perf-ab.yml` with `self_test: aa` once merged, to see the hosted
  runner's noise band.
