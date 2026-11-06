# `--refine-infer`: the six open inference items (2026-11-06)

Closes six todos filed by the inference-lite evaluations
(`2026-10-21-refinement-suggest-lite-evaluation.md`, `2026-10-25-refine-infer-vocab.md`,
`2026-10-29-refine-infer-evaluation-2.md`):

| Todo | Priority | Fix |
|---|---|---|
| `2026-10-29-refine-infer-gates-on-hidden-stdlib-errors` | P2 | gate on the errors `--check` rejects on |
| `2026-10-29-forge-refine-infer-per-file-fallback-repeats-proposals` | P3 | the fallback infers once, over the files that check |
| `2026-10-21-refine-infer-stdlib-sweep-too-slow` | P3 | `--refine-infer-module`, progress lines, a parallel sweep script |
| `2026-10-21-refine-infer-notes-noise` | P4 | `scc-unsupported` only near an open site |
| `2026-10-29-refine-infer-ill-sorted-house-candidate` | P4 | a field projection is ill-sorted on a scalar or list slot |
| `2026-10-25-refine-infer-joint-relational-param-return` | P4 | a joint parameter + return candidate (`bump`) |

## What changed

- **The gate (`bin/main.ml`).** Inference was gated on every typecheck error of the compile
  path, including errors located in stdlib files that `--check` never prints. A user record
  named like a `ClusterNode` record (`type NodeInfo = …`, `type Member = …`) leaves one in
  `stdlib/cluster_node.march`, so `--check` exited 0 and `--refine-infer` printed only
  "skipped, the program has errors". The gate now reads `--check`'s condition: an error in a
  user file. With `--refine-infer-stdlib` or `--refine-infer-module` the stdlib is a target,
  so its errors gate too. A skip now names the first three errors it gated on
  (`file:line: message`). The collision itself, a user type breaking the stdlib's own
  typecheck, is the open `2026-10-13-same-short-name-nested-types-unify` (one global type
  namespace); `--compile` of such a program already succeeded.
- **forge's fallback (`forge/lib/cmd_refine.ml`).** When the project does not check as one
  unit, forge used to run every file as its own entry. Each run loads the modules its entry
  names, so every run inferred over most of the project: depot printed each of its 3 metric
  proposals 30 times. Now each file is `--check`ed on its own (no inference, so nothing is
  printed), the ones that fail are reported, and ONE inference run covers a generated entry
  naming the modules of the files that check. A file that checks names only modules that
  check, so the broken ones stay out. Only if that unit still fails does forge go back to one
  run per file, and then an identical report is printed once.
- **Stdlib sweep.** `--refine-infer --refine-infer-stdlib` targets every stdlib function in
  one run with one global budget: 48 minutes, and the budget ran out before most modules.
  New: `--refine-infer-module M` (repeatable) targets only the file(s) declaring module `M`,
  stdlib or not; a run with stdlib or module targets prints one progress line per round on
  stderr (`round N done, S slot(s), P probe(s) used, L left, Ts`). New
  `scripts/refine-infer-stdlib-sweep.sh [OUT] [M …]` runs one module per process, in
  parallel, each with its own budget (`SWEEP_BUDGET`, default 300) and timeout, under a
  private HOME, and writes one JSON report per module. A module target can make a stdlib
  function a target but never a file to write: under `--refine-infer-apply` a stdlib
  proposal is withheld (`stdlib-needs-refine-infer-stdlib`) unless `--refine-infer-stdlib`
  is also given (design §4.3).
- **Notes noise (`lib/refinecheck/refine_infer.ml`).** `scc-unsupported` is noted for an SCC
  only when an unsettled user site lies inside a member or inside a function that calls a
  member (a demand on a member's return sits in its caller). An SCC with nothing near it had
  nothing to infer.
- **Ill-sorted candidates (`lib/refinecheck/infer_vocab.ml`).** `sorted_for` now rejects a
  projection of the value itself (`_.step`, mined from `Range.new`'s
  `{v : IntRange | v.step != 0}`) on an Int, Float, String or List slot, before it is probed.
- **Joint relational candidate (`lib/refinecheck/infer_oracle.ml`, `refine_infer.ml`).**
  `bump : Assoc(Int, Int) -> Assoc(Int, Int)` keeps `y > x` from its parameter to its return,
  but the return alone is not TRUE without the parameter's relation and the parameter alone
  closes nothing. When a relational return demand finds no single-slot proposal,
  `Infer_oracle.best_joint` installs the demanded type on the return AND on each parameter of
  the same base, one atomic probe: TRUE through the element-return gate under the parameter
  hypothesis; a new violation at a caller refuses it (`caller-violation`, unless
  `--allow-caller-violations`); USEFUL as for any return. The proposal carries
  `joint_param` and is written as two edits (parameter, then return). The text report adds
  `(with parameter a)`; the JSON adds `"joint_param": "a"` on that proposal only, so every
  other line is unchanged.

## Verification

| Check | Result |
|---|---|
| `infer-apply` (test_refinecheck): `NodeInfo` program not skipped and its proposal made; a user-file error still skips and names `file:line` | RED (both) → GREEN, 17/17 |
| `infer-apply`: no `_.step` candidate for the todo's `Range` repro | RED → GREEN |
| `infer-fixpoint`: an ev/od SCC with no open site near it is not noted (and the existing noted case still is) | RED → GREEN, 10/10 |
| `infer-cli`: `--refine-infer-module Option` probes only `Option.*` functions | RED (unknown option) → GREEN |
| `infer-cli`: `--refine-infer-module Decimal --refine-infer-apply --apply-public` leaves the staged `stdlib/decimal.march` unchanged | RED without the guard (the file was written) → GREEN |
| `infer-vocab-oct`: `bump` proposed jointly with `joint_param = a`; `v - 1` control not proposed; a caller passing `ACons(5, 2, ANil)` refuses it; `--refine-infer-apply` writes both annotations and the re-check matches | RED → GREEN, 4/4 |
| forge `refine --infer`: a 4-file project with one broken file prints the proposal once and reports only the broken file | RED (printed 3 times) → GREEN, 8/8 |
| `scripts/refine-infer-stdlib-sweep.sh` over the whole stdlib | 133 modules, 98 s, every run exit 0 (was 48 minutes for one run). `Gen.filter` is probed; `HashMap`, `Seq` and `Flow` have no candidate to probe from a trivial entry, so the per-module run reports 0 probes |
| `scripts/affected.sh --run --full`: doc-lint; compiler 1515, codegen 724, errors 411, test_jit 43, test_reports 12, refinecheck 2357 (twice: both suite names); `@forge/test/runtest`; refine oracle | all pass; refine oracle IDENTICAL to main's merge-base (8261 lines, 574 fixtures) |
