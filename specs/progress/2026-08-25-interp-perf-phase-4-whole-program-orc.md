# Phase 4 (Task 4.2): `jit` mode in the interp bench harness; whole-program ORC results and default-flip decision

Completed: 2026-08-25

## What changed

`bench/run_interp_bench.sh` gained a third file-benchmark mode, `jit`
(`"$MARCH" --jit "$src"`), alongside the existing `interp` and `compiled`
modes:

- default `--modes` is now `interp,jit,compiled,repl-clang,repl-orc`;
- the file-benchmark loop runs all three enabled file modes per iteration;
- the checksum cross-check was generalized from a two-way `interp` vs.
  `compiled` comparison to an N-way comparison across whichever modes are
  enabled and actually produced a checksum (`ok=true`). A mode that crashes
  (`ok=false`, e.g. a `--jit` SIGBUS) is reported as a `FAILED` row but is
  **excluded** from the mismatch comparison — it does not abort the run.
  Two modes that both produced a checksum and disagree is still a hard
  failure (`exit 1`), same as before for interp-vs-compiled.
- the table printer's `modes` list gained `jit`.

The runner stays bash-3.2-compatible (macOS default `/bin/bash`, no
associative arrays): the new cross-check uses plain per-mode variables
(`sum_interp`/`sum_jit`/`sum_compiled`, `ok_interp`/`ok_jit`/`ok_compiled`)
reset at the top of each benchmark's loop iteration, same idiom as the
existing two-mode code.

Verified before the full run: the `set -e` / `|| true` guard on the `jit` arm
correctly absorbs json_stream's rc=138 (SIGBUS) — confirmed by running that
one line without the guard (`rc=138`, would abort a `set -euo pipefail`
script) versus with it (`rc=0`, output captured, loop continues).

## Load conditions

`sysctl -n vm.loadavg` before the run: `{ 4.21 4.69 5.17 }` (load1 ≈ 4.2, just
under the 5.0 "note and proceed" threshold; box was moderately busy but not
flagged as unusable). This is a comparative table across modes taken in a
single run, not the committed timing baseline, so absolute ms should be read
as directional, not authoritative.

## Full matrix

`bash bench/run_interp_bench.sh --modes interp,jit,compiled --runs 3 --tag p4.2-b2c154bf`
(tag is `p4.2-` + `git rev-parse --short HEAD` at run time). Raw rows are
appended to `bench/results/2026-08-25-interp-arm64.jsonl` (committed).

| bench | interp min/median ms | jit min/median ms | compiled min/median ms | repl-clang min/median ms | repl-orc min/median ms |
|---|---:|---:|---:|---:|---:|
| actor_call_storm | 1857 / 1862 | 1875 / 1878 | 42 / 47 | – | – |
| actor_pingpong | 363 / 369 | 367 / 370 | 43 / 46 | – | – |
| binary_trees | 349 / 351 | 347 / 354 | 41 / 42 | – | – |
| fib | 407 / 408 | 348 / 349 | 42 / 43 | – | – |
| float_loop | 599 / 605 | 351 / 352 | 43 / 45 | – | – |
| http_server | 233 / 244 | – | 221 / 231 | – | – |
| json_stream | 9306 / 9307 | 445 / 449 | 60 / 64 | – | – |
| par_fib | 409 / 410 | 349 / 354 | 46 / 46 | – | – |
| par_map | 1561 / 1566 | 371 / 373 | 48 / 52 | – | – |
| string_pipeline | 380 / 384 | 377 / 387 | 42 / 47 | – | – |
| string_split | 916 / 919 | 412 / 419 | 76 / 78 | – | – |

3 FAILED rows (`ok=false`): `json_stream/jit` × 3 runs. `http_server` has no
`jit` row — it is a long-running server process, not a one-shot file program,
and the runner's `jit` arm is only wired into the file-benchmark loop, not
the separate http_server harness section (out of scope for this task; see
`docs/superpowers/plans/2026-08-23-interpreter-and-repl-jit-performance.md`
Task 4.2 scope, which only asks for the file-benchmark loop).

`jit` lands roughly 1.1–2.6× faster than `interp` on the programs that
actually JIT (par_map 1561→371ms ≈ 4.2×; string_split 916→412ms ≈ 2.2×;
float_loop 599→351ms ≈ 1.7×; json_stream would be the outlier at ~9.3s→crash),
and is consistently still several× slower than `--compile`'s ahead-of-time
pipeline (fib 348ms jit vs. 42ms compiled ≈ 8×) — expected, since ORC still
pays JIT compilation cost inside the timed run instead of amortizing it
ahead of time.

## Per-file status under `--jit`

- **JIT'd for real (7):** `fib`, `binary_trees`, `float_loop`,
  `string_pipeline`, `string_split`, `par_fib`, `par_map` — all print the
  same `checksum=` as `interp` and `compiled`.
- **Actor fallback (2):** `actor_pingpong`, `actor_call_storm` — both print
  `march: --jit does not support actor programs yet; running interpreted` to
  stderr and then run through the interpreter, producing the correct
  checksum. **Their `jit` column in the table above is measuring the
  interpreter fallback, not an actual JIT compilation** — the timings
  (367ms, 1875ms) are close to the `interp` column for the same reason. This
  caveat is also called out in `bench/interp/README.md`.
- **SIGBUS (1):** `json_stream` — rc=138 under `--jit` on both
  `MARCH_JIT_BACKEND=orc` (default) and `=clang`. `--compile` of the exact
  same file is green. Filed as
  `specs/todos/2026-08-25-jit-whole-program-json-stream-sigbus.md` with
  repro, and the hint that this is specific to the fragment/whole-program-JIT
  path (`Repl_jit.run_program`), not to TIR lowering or codegen shared with
  `--compile` (which is exonerated by `--compile` being clean on the same
  source).
- **Not exercised under `--jit` (1):** `http_server` — the runner's `jit`
  mode is only wired into the file-benchmark loop (see above); the
  server-process harness section still only supports `interp`/`compiled`.

This matches the known corpus state carried over from Task 4.1 (7 truly
JIT'd + 2 actor-fallback + 1 SIGBUS), reverified here rather than assumed.

## Default-flip criteria (verbatim from the plan)

From `docs/superpowers/plans/2026-08-23-interpreter-and-repl-jit-performance.md`,
Task 4.2 Step 3:

> The default flips only when: every `bench/interp` program passes under
> `--jit`, the `run_eval` suite is made to run under `--jit` for its
> non-debugger cases with zero diffs, and the interpreter-only flags
> (`--debug`, `--coverage`, `MARCH_REPL_INTERP`) explicitly select the
> interpreter. That is its own plan.

### Per-criterion status

| Criterion | Status |
|---|---|
| Every `bench/interp` program passes under `--jit` | **NOT MET** — `json_stream` SIGBUSes (rc=138); `actor_pingpong`/`actor_call_storm` only pass via silent interpreter fallback, not an actual JIT run, so "passes under `--jit`" is arguably not met for those two either even though their checksums are correct |
| `run_eval` suite runs under `--jit` for non-debugger cases with zero diffs | **NOT MET / NOT ATTEMPTED** — no wiring exists yet to run `run_eval`'s cases through `--jit` instead of the tree-walking interpreter; this is unstarted work, scoped as "its own plan" per the plan doc itself |
| `--debug`, `--coverage`, `MARCH_REPL_INTERP` explicitly select the interpreter | **MET** — `--coverage` is a `march test` subcommand flag that never reaches the `--jit`/compile/interpret dispatch in `bin/main.ml`, and `MARCH_REPL_INTERP` is REPL-only — both are structurally safe (there is no code path where `--jit` could observe or override them). `--debug`/`--debug-tui` is now routed back too (fixed 2026-08-25): the `jit_run` guard in `bin/main.ml` (~2889) gained a `!debug_mode \|\| !debug_tui_mode` arm, checked first (before the shadowing/actor arms) so the user's explicit `--debug` request takes precedence, printing `march: --jit does not support the debugger; running interpreted` to stderr and falling back to the tree-walking interpreter, which then installs the debugger exactly as it does with no `--jit` flag. Verified: `--jit --debug` now prints the fallback notice, the `[debug] Trace recording enabled (buffer: N frames)` banner, and the correct checksum. Regression test: `test_jit_file_debug_falls_back` in `test/test_jit.ml` (`jit_file` group), pinning both the stderr notice and the program output; proven to fail against the pre-fix binary via a file-copy swap (never `git stash`). |

### Recommendation

**Do not flip the default yet.** One SIGBUS (`json_stream`, filed above) is
alone disqualifying under the plan's own "every `bench/interp` program
passes" bar. On top of that: the actor fallback means two programs only
"pass" by silently not using the JIT at all (the argv/whole-program feature
gap referenced in the plan — actors stay interpreted), and the `run_eval`
suite has not been run under `--jit` at all, which is a separate, larger
piece of work the plan explicitly defers ("That is its own plan"). The
combination — one crash, one feature gap (actors) falling back silently
rather than erroring, and an entire test suite not yet exercised under the
new backend — means the whole-program ORC JIT is not yet a safe default;
`--jit` remains opt-in, `--compile` remains the AOT default,
plain-interpreted remains the no-flag default.

## Files

- `bench/run_interp_bench.sh` — `jit` mode wiring + N-way tolerant checksum
  cross-check
- `bench/interp/README.md` — documents the `jit` mode, the actor-fallback
  caveat, and the json_stream exclusion
- `bench/results/2026-08-25-interp-arm64.jsonl` — raw JSONL rows for this run
  (tag `p4.2-b2c154bf`)
- `specs/todos/2026-08-25-jit-whole-program-json-stream-sigbus.md` — new
  open item for the SIGBUS
