# Refinement inference: second evaluation run

Done 2026-10-29 on branch `claude/infer-eval-2026-10-29`:
- `origin/main` at `ec65443a2`;
- `claude/termination`: already an ancestor of main, so the merge was a no-op;
- `claude/record-element-slot-obligations` (`2c1a07981`), merged `--no-ff` cleanly with no conflicts.

The run follows the protocol of `specs/progress/2026-10-21-refinement-suggest-lite-evaluation.md`
(the "Oct-21" column below). Where `specs/progress/2026-10-25-refine-infer-vocab.md` measured
main at `bf49708ec`, its numbers are the "Oct-25" column.

It changes no compiler or stdlib code and wrote nothing into the corpus projects. One
diagnostic patch (it printed the errors the `--refine-infer` gate sees) was built, copied
out of `_build` and reverted at once. The rebuilt exe was `cmp`-identical to the measured one.

Setup:
- Every `march` ran with z3 on `PATH` and a fresh `HOME` and cwd per invocation.
- The worktree's `stdlib/` was passed as `MARCH_STDLIB`.
- The compiler was a copy of `_build/default/bin/main.exe`.
- Load average was 6-9 at the start and 20-22 for about 10 minutes of the `test/native`
  run, while the corpus-2 runs overlapped it. Absolute times are inflated; the ratios
  compare runs made under the same load.

## Corpus 1: `test/native/*.march` (418 files)

Each file got a cold `--check` and a cold `--check --refine-infer-json`, 4 files in parallel.
Each also got a `--refine-report` (skips by reason) and a `--termination-report`. Every file
with a proposal was applied with `--refine-infer-apply` on a copy, then re-checked.

| Metric | Oct-21 | Oct-25 (main) | now |
|---|---|---|---|
| Files that check | 416 / 416 | 417 / 417 | 418 / 418 |
| User skips before → after | 13 → 13 | 13 → 13 (5 files) | 18 → 18 (6 files): the 13 old ones plus 5 in the new `stdlib_step_guards.march` (#1030) |
| User skips by reason | solver-undecided 10, partial-conjunct 1, unconstrained-subject 1, unreflectable-subject 1 | same | solver-undecided 11, unconstrained-subject 4, unreflectable-subject 2, partial-conjunct 1 |
| Violations before → after | 0 → 0 | 0 → 0 | 0 → 0 |
| Accepted refinements, by kind | 1 precondition (vacuous) | 0 | **0** |
| Rejected: not-true / vacuous-branch | 3683 / 0 | 3625 / 5 | 3758 / 5 |
| not-true: return / element return / accumulator | 3099 / 391 / 193 | 3049 / 383 / 193 | 3112 / 391 / 255 |
| Refused | 11 caller-violation | 0 | 0 |
| Notes: scc-unsupported / vocabulary-truncated | 16 / 2 | 16 / 2 | 16 / 2 |
| Probes; max rounds | 11 778; 2 | 11 467 | 11 658; 1 |
| Infer ÷ cold check: median / p90 / aggregate | 1.35× / 1.66× / 1.44× | 1.38× / 1.83× / 1.73× | 1.46× / 2.07× / 1.80× (826 s → 1491 s) |
| Max ratio | 23.7× | 15.1× (`nativearr_fold_sum_fusion`) | 13.8× (same file) |
| Accepted `@[decreases]` metrics | — | — | **78** in 47 files (phase 5 reported 78) |
| Prediction mismatches (apply on a copy) | 0 of 1 | 0 (nothing applied) | **0 of 47 files** (78 metrics written; every re-check matched) |

**Where the probes go.** 412 of the 418 files have no unsettled user obligation, and those
files account for 11 273 of the 11 658 probes (96.7%). So nearly all of inference's cost
goes to candidates nobody asked for: `_ < 0`, `_ <= 0`, `_ > 0`, `_ != 0` and `_ >= 0` on
returns alone are 2662 of the 3758 not-true rejections.

**The 18 user skips are out of reach for user-side inference:**
- 7 `List.head` calls on `List.map(…)` / `Sort.mergesort_by(…)` results
  (`closure_scalar_abi`, `float_boxing`). They need a length-preserving postcondition on the
  stdlib callee, which `--refine-infer` does not target without `--refine-infer-stdlib`, and
  `len(_) == len(xs)` is not in the list-return vocabulary anyway.
- 4 `pvec_length` index or length preconditions (`array_trie_drop_leak_probe`), which are
  solver-undecided. The proposal that would close them makes the branch dead
  (`vacuous-branch`, 4 rejections).
- 5 deliberate zero-step or zero-size calls (`stdlib_step_guards`) and 1 deliberate
  out-of-range lane (`simd_lane_panic`). These are negative tests, and closing them would be
  wrong.
- 1 `Array.get` in `float_generic_field_abi` (solver-undecided).

**Quality of the accepted proposals.** None of the accepted proposals is a refinement. On
the metrics, see corpus 4.

## Corpus 2: depot, conduit, test_conduit_app (`forge refine --infer --diff`)

The projects were copied into the scratch area, and the originals were left untouched:
- `git status --short`: depot clean at `b8e8b40`. Conduit at `35e50ce` shows only its
  pre-existing `?? .worktrees/` and `?? specs/bastion-vault-refactor-guide.md`.
- `test_conduit_app` is not a git repo: `shasum` over all 16 files, before and after, is
  identical.

**None of the three projects has a single refinement.** depot has 739 `fn`/`pfn`
declarations in 32 files, conduit 421 in 45, test_conduit_app 79 in 7. None of them carries
a refinement type, an abstract refinement or an `@[decreases]`, and no type alias is refined.
The only obligations are the ones that stdlib callees impose on their call sites.

| Project | Oct-21 | now |
|---|---|---|
| depot (31 files) | 30 checked, 0 unsettled user obligations, 0 proposals; `cmd_depot.march` skipped | Same: 0 user skips, 0 refinement proposals, 17-20 probes per run. `cmd_depot.march` fails `cap_ceiling` (`IO.Clock`, `IO.FileRead`, `IO.FileWrite` used, only `IO.Console` declared), so the project does not check as one unit and forge falls back to per-file runs. **3 metrics proposed**: `Sqlite.collect_col_names` and `collect_row_cells` (`count - i`), and `Pool.warm_up` (`target - count`). 147 s. |
| conduit (45 files) | none checked: `cap_ceiling` plus the registry `depot 0.3.3` not fetched | **Unchanged under plain forge**: 45 of 45 "no inference". `forge.lock` still pins `depot 0.3.2` against `forge.toml`'s 0.3.3, and with a private HOME the registry dep is not fetched. |
| conduit, made to check (copy) | — | 1 user skip (`List.last` in `dashboard/pages/dead_letters.march:34`, solver-undecided) → 1. 29 probes, **0 refinement proposals**. 4 metrics (depot's 3, plus `Conduit.CronParser.pfind_next @[decreases(527040 - count + 1)]`). 80 s. |
| test_conduit_app (7 files) | not run | Does not parse with this compiler. Every file stops at the old record syntax `field = value` (`lib/test_conduit_app.march:25`), so the result is "no inference" ×7. |

**Why conduit still fails, and how it was made to check.** Three independent causes, all
still present:
1. **The depot dependency is not resolved** (`forge.lock` pins `depot 0.3.2`, and the 0.3.3
   registry tree is not fetched under a fresh HOME). Workaround: a `march` wrapper first on
   `PATH` that prepends the depot copy's `lib/` to the `MARCH_LIB_PATH` forge computes, so
   `forge refine --infer` itself runs unmodified. (A `forge.toml` path dependency would be the
   other route.)
2. **`cap_ceiling` errors in conduit's own source.** These are real omissions, not
   compiler bugs:
   - `Conduit.Dashboard` calls `HttpServer.listen` without `needs IO.NetListen`;
   - `Conduit.Storage.Postgres` calls `DateTime.now()` without `needs IO.Clock`;
   - `Forge.CmdConduit` uses file I/O without `needs IO.FileRead` / `IO.FileWrite`.

   The copy got those four `needs` lines.
3. **A compiler bug.** `Conduit.NodeInfo` (`lib/conduit.march:461`) shares its short name
   with `ClusterNode.NodeInfo`. `--check` passes, but the compile-path typecheck that
   `--refine-infer` gates on reports `stdlib/cluster_node.march:2747 expected NodeInfo but got
   NodeInfo`. That error is never printed, because it is in a stdlib file, so every run says
   only "skipped, the program has errors". Renaming the type to `ConduitNodeInfo` in the copy
   was enough. Filed: `specs/todos/2026-10-29-refine-infer-gates-on-hidden-stdlib-errors.md`.

With all three handled, the project checks as one unit and `forge refine --infer` finishes
in 80 s.

**Noise (filed).** In depot's per-file fallback, every one of the 30 runs loads the whole
project from `MARCH_LIB_PATH`. The output is 3585 lines:
- the same 3 metrics and their diff hunks, 30 times each;
- 1686 "no metric inferred" lines;
- 966 `scc-unsupported` notes.

The 966 notes are the number the 2026-10-21 noise todo quoted, and they are 30 copies of
about 32. Filed: `specs/todos/2026-10-29-forge-refine-infer-per-file-fallback-repeats-proposals.md`.
Conduit's one-unit run prints 35 `scc-unsupported` notes.

## Corpus 3: the stdlib, per module

The CLI has no per-module target. `--refine-infer-stdlib` targets every loaded stdlib
function, and that is the 48-minute run. Checking a copy of `stdlib/M.march` as the entry
shadows `M`, and hidden stdlib errors then make inference skip (the same todo as above).

What worked: a copy of each module with its top-level `mod M do` renamed to `mod EvalM do`
and its top-level `impl` blocks dropped (they overlap the real module's), checked with
`--stdlib-source`. Its functions are then user code, so they are the inference targets,
and the real stdlib stays loaded beside it. Callers in other stdlib modules are not seen.

The run was done twice. Run A used the module as shipped, with its refinements. Run B
("stripped") replaced every `{v : T | p}` / `{T | p}` with `T` and every `a[p]` / `Bool[p]`
with `a` / `Bool`. The table shows run A; run B differs only where noted.

| Module | check | infer | ratio | user obligations (proved / trusted / skipped) | probes | proposals | rejected | metrics |
|---|---|---|---|---|---|---|---|---|
| list | 1.82 s | 62.9 s | 34.6× | 36 / 0 / 0 | 470 | 0 | 185 (182 not-true, 1 opens-site) | `sort_by/merge/go (len(l), len(r))`, local |
| option | 1.69 s | 5.9 s | 3.5× | 1 / 0 / 0 | 5 | 0 | 2 | — |
| map | 1.69 s | 2.9 s | 1.7× | 0 / 13 / 0 | 2 | 0 | 2 | `make_branch/go (6 - lvl + 1)`, local |
| string | 1.70 s | 52.0 s | 30.6× | 0 / 0 / 0 | 71 | 0 | 24 | `decode_go (n - i)` |
| sort | 1.76 s | 29.8 s | 16.9× | 0 / 0 / 0 | 110 | 0 | 33 | `enforce_invariants (len(stack))`; `merge_sorted/go (len(l), len(r))`, local |
| seq | 1.74 s | 2.8 s | 1.6× | 1 / 0 / 0 | 0 | 0 | 0 | — |
| array | 1.76 s | 3.0 s | 1.7× | 0 / 6 / 1 (unreflectable) | 7 | 0 | 6 | — |
| hash_map | 1.60 s | 2.8 s | 1.8× | 0 / 1 / 0 | 0 | 0 | 0 | `make_branch/go`, local |
| flow | 1.71 s | 2.3 s | 1.3× | 1 / 0 / 0 | 0 | 0 | 0 | — |
| gen | 1.69 s | 42.5 s | 25.2× | 1 / 0 / 2 | 320 | 0 | 93 | `filter_attempt (tries)` |
| deque | 1.60 s | 9.0 s | 5.6× | 3 / 0 / 1 | 31 | 0 | 17 | — |
| enum | 1.60 s | 29.5 s | 18.4× | 7 / 0 / 0 | 180 | 0 | 74 | `frequencies/go (len(lst))`, local |

Per-module time ranges from 2.3 s to 63 s, against the 48-minute whole-stdlib run, and no
budget was exhausted. **No module got a refinement proposal, in either run.**
- **Run A.** A shipped module has 0-2 unsettled obligations of its own, so there is nothing
  to close. Gen's 2 skips are `List.nth(xs, idx)` where `idx` comes from `Random.range`,
  whose tuple result carries no bound. The array and deque skips are one unreflectable
  subject each.
- **Run B (stripped)** removed 21 refinements from `list`, 2 from `option`, 15 from `map`
  and 10 from `array`. With them gone the modules have 0 obligations of their own, so
  nothing demands the facts again. `filter`, `find` and `take_while` get no K6 probe at all
  (demand-gated), only `len(_) > 0` and `_.step != 0` return probes, all rejected. The K6
  probe on `partition` / `partition_go` is rejected `not-true`. Rediscovery happens only
  with a demanding caller, as in the unit fixtures.

Design §6 rows that the Oct-21 run never reached, reached here:
- `List.pfilter` and `List.drop_while`: K6 rejected `not-true`; `Enum.drop_while` the same.
- `List.find_index`: 7 element-return candidates, all rejected (row O1, as predicted).
- `Seq` and `Flow`: 0 probes (no demand).
- `HashMap.filter`: 0 probes.
- `Gen`: 320 probes, 0 proposals.
- `Deque.filter`: no proposal.

## Corpus 4: termination metrics

`--termination-report` (which also runs the metric search) was run per file. The `--refine-infer`
side used the `decreases` arrays: per file for `test/native`, and for the stdlib one whole-stdlib
entry with `--refine-infer --refine-infer-stdlib --refine-infer-kinds decreases` (20 s).

| | recursive units | certified without inference (structural + metric) | targets | certified by `--termination-report` inference | by `--refine-infer` (re-checked) |
|---|---|---|---|---|---|
| stdlib (135 files) | 783 | 446 (434 + 12) | 297 | 27 | 27 (18 writable, 9 local `fn`s) |
| test/native (418 files) | 525 | 318 (67 + 251) | 204 | 78 | 78 (all writable; 0 mismatches when applied) |

The two counts agree on both corpora. They also match phase 5's numbers (stdlib 27, native
78). Applying the native proposals took the 47 files from 86 unproved units to 8; the
remaining 8 are other units in the same files that inference did not certify.

By class (native / stdlib), inferred over total:
- B: 75/95 and 21/72;
- `?`: 3/18 and 2/107;
- D: 2/3 (stdlib only);
- A: 0/7 and 2/36;
- C: 0/79 and 0/51;
- E?: 0/5 and 0/18;
- F: 0/10 (stdlib only).

**Hand judgment, 16 proposals sampled:**
- **Native:**
  - `settle (tries)`;
  - `wait_depth (attempts)`;
  - `write_chunks (n)`;
  - `int_loop (n)`;
  - `tuples` and `sets (stop - i)`;
  - `passed_then_updated (n - i)`;
  - `spawn_batches (n_batches - batch)`;
  - `ordered_and_stable (len(xs))`;
  - `h_sigil all (7 - leg + 1)`.
- **Stdlib:**
  - `Regex.eclose_from (m - i + 1)`;
  - `Toml.reposition_go (j - k)`;
  - `Sort.enforce_invariants (len(stack))`;
  - `BigInt.add_digits/go (len(xs), len(ys))`;
  - `Hamt.make_branch/go (6 - lvl + 1)`;
  - `Toml.update_last_aot (len(path))`.
- **Depot/conduit:** `CronParser.pfind_next (527040 - count + 1)`.

All 16 are correct and are the measure a human would choose. In 4 of them the form is not
the one a human would write:
- 3 keep the guard's `+ 1` unsimplified (`7 - leg + 1` for `8 - leg`, `6 - lvl + 1`,
  `527040 - count + 1`);
- `BigInt` gets a lexicographic pair where `len(xs) + len(ys)` would also do.

None of the 16 is vacuous. 9 of the 27 stdlib proposals cannot be written, because a local
`fn` takes no attribute (existing todo `2026-10-28-termination-infer-gaps.md`).

## The bottleneck

The rejection reasons and a hand-read sample of 20 rejected candidates (`test/native`, seed
20261029) show that the checker is not what blocks acceptance:
- 16 of the 20 are false as stated, e.g. `_ > 0` on `n + 5`, `len(_) > 0` on a list that
  can be empty, or `_ >= 0` on an unconstrained accumulator.
- 3 are true (or likely true) at run time but need facts the checker has no access to, and
  no one needs them: `f64_acc_leg >= 0` (a float fold), `shown != 0` (a `to_string` length)
  and `round_trip > 0` (file I/O results).
- 1 is ill-sorted: `_.step != 0` on an `Int` accumulator.

No caller needed any of the 20. The tool does not fail to prove what is needed. **The corpora
contain almost nothing that needs proving:**
- 6 of 418 native files have an open user obligation;
- the 3 projects have 0 refinements and 0-1 open obligations;
- shipped stdlib modules have 0-2 each.

The obligations that do exist are of three kinds:
- stdlib postconditions the tool does not target by default, such as `List.map` or
  `mergesort_by` length, or `Random.range` bounds;
- solver-undecided `pvec_length` facts;
- deliberate negative tests.

Meanwhile 96.7% of the probes go to files with nothing open.

## New bugs (filed, with minimal repros)

- `specs/todos/2026-10-29-refine-infer-gates-on-hidden-stdlib-errors.md` (P2). A user record
  type named `NodeInfo` or `Member` makes `--refine-infer` skip a program that `--check`
  accepts, showing no error. This blocks conduit and the per-module stdlib route.
- `specs/todos/2026-10-29-forge-refine-infer-per-file-fallback-repeats-proposals.md` (P3).
  Forge's per-file fallback prints each proposal once per file (30× on depot).
- `specs/todos/2026-10-29-refine-infer-ill-sorted-house-candidate.md` (P4). The new
  `Range` refinement's `_.step != 0` is probed on `Int` slots: 79 probes in 33 native files,
  and it shows up in stripped `list` too.

## Verdict

**Does the tool add refinements a user would keep? Not on any of these corpora today.**
- The refinement half accepted 0 proposals on test/native (418 files), depot, conduit and 12
  stdlib modules, run both as shipped and stripped. On test/native that is 1 vacuous
  proposal on Oct-21, 0 on Oct-25 and 0 now.
- The termination half adds real value. It writes 78 `@[decreases]` on test/native, 27 in
  the stdlib (18 writable) and 4 on depot/conduit. All 16 sampled are correct and are what a
  human would write, apart from an unsimplified `+ 1` in 3 of them. Applying them caused 0
  prediction mismatches.

**Top three changes that would make it pay off:**
1. **Target the obligations that actually exist.** These are stdlib postconditions, so allow
   `--refine-infer-stdlib` per module, or for the callee of an open user site only (e.g.
   `List.map`'s length, `Random.range`'s bounds), and add `len(_) == len(xs)` to the list
   return vocabulary. Every non-deliberate user skip in test/native needs one of these.
2. **Spend probes only on demand.** Gate return and element candidates on a caller with an
   unsettled site, as `Arg` slots already are, and filter out ill-sorted candidates. About
   97% of probes today go to files with nothing open. On `list.march`, where nothing is
   open, inference costs 34.6× a cold check.
3. **Fix the silent skips.** `--refine-infer` should gate on user errors only, and forge
   should deduplicate per-file results. Real projects are where users would run this: on
   conduit it is a no-op without four source edits and a type rename. A trivial `+ 1`
   simplification of metric expressions would also help.
