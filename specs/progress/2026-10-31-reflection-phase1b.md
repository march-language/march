Refinement reflection, phase 1b: the D17 logic hash (proof cache, `--dump-impl-hashes`, LSP
key), the hot-reload refusal of a reflected body change (I9), the parity net (§9.2,
`reflect-parity`, `forge test --reflection-parity`), and the cheap gaps phase 1a left
(`specs/2026-10-29-refinement-reflection-design.md` §7.1, §7.2, §9.2, §12 I8/I9; phase 1a is
`specs/progress/2026-10-30-reflection-phase1a.md`, whose rulings bind here). This file replaces the
open todo `2026-10-30-reflection-phase1b.md`; what stays open is
`specs/todos/2026-10-31-reflection-encoder-gaps.md`.

## What landed

- **D17 logic hash (§7.1, I8).** `Refine_reflect.install` gives every reflected function with a
  logic symbol a BLAKE3 hash over: its source text (from its name to the end of its body, so a
  line inserted above moves nothing), its R-status (`reflected` and its unfolding guards), its
  definition (the template's cases and guard, with every logic symbol written as
  `<display name>@<file>` instead of its position), and the `==` reading (`structural` /
  `opaque`) of every type its body compares at. Tables in `Reflect_state` (`logic_hash`,
  `logic_by_name`, `sym_origin`).
- **D17 lines in each stage-2 query.** `Refine_encode.query_instance_preamble` prefixes
  `; reflect <symbol> blake3=<hash>` for each definition in the query's frontier (read off the
  unfolding facts). The preamble is part of the VC cache key, so the cached verdict and the
  cached unsat core (`<key>.core`, phase 1a) are keyed by the definitions they used. A query
  without an unfolding gets no line: stage 1 is byte-identical (`two_stage_identical` and the
  `d17_line` row assert it).
- **`--dump-impl-hashes`** gains a fourth column, `logic_hash` (`-` when not reflected; a
  specialisation `f$T` of a polymorphic reflected `f` carries `f`'s hash). **`--reflect-deps`**
  prints `reflect-def` (each reflected user function) and `reflect-dep` (every reflected
  function in the frontier of any stage-2 query the check ran) lines; both bypass the early CAS.
- **Hot reload (I9).** `March_cas.Hash.hcr_slot_sig_hash` folds a reflected function's logic
  hash into its slot sig_hash (unchanged for an unreflected function, so no HCR ABI bump); the
  `.hcr_manifest` line carries `logic=`. `forge deploy hot` refuses a patch whose reflected logic
  changed (`Cmd_deploy_hot.logic_changes`, checked right after the borrow-mode gate): "a hot deploy
  cannot change a reflected function: the body of `f` is part of its callers' proofs; redeploy,
  or mark it `@[opaque]`".
- **LSP (§7.2).** The language server never ran the refinement checker (the design's F10 says it
  re-checks a file; it only typechecks). `lsp/lib/refine_diag.ml` runs `march --check
  --check-json --reflect-deps` on a saved file, publishes its refinement diagnostics, and keys the
  file on its `reflect-dep` lines (the frontier, not the core). Saving a file (or a watched
  on-disk change) re-checks it and every open file whose key holds a hash of a function of it
  that no reflected function of it has any more. Opt-in: `MARCH_LSP_REFINE=1` (ruling 4).
  `Refine_diag.lemma_key` is the phase-2 hook for dependency lemmas (always empty).
- **Parity net (§9.2, D16).** `lib/refinecheck/reflect_parity.ml`, `march --check
  --reflect-parity`, `forge test --reflection-parity` (after the tests pass, each `lib/`/`src/`
  file). Inputs: each Int parameter at 0, ±1, max/min 63-bit Int and neighbours, then 100 draws
  (seed 20261031, recorded in the summary line); generators for Int, Bool, type variables (as
  Int) and data types whose constructor names are unique. Logic side: the template evaluated on
  the ground input (exact, unbounded-Int semantics; callees through their own templates, step cap
  10 000). Program side: `Witness.call_fn_classified` (the witness interpreter's fuel and effect
  veto, new: it tells an overflow, a panic, a match failure and fuel-out apart). Verdicts:
  `agree`, `MISMATCH` (RED), `INTERPRETER-FAILURE` (RED, inside `pre_f`, whatever the logic
  says), `overflow?` (the interpreter overflowed, #1042, D8), `not-compared` (an opaque `==`, no
  definition, the step cap, an input no case covers, a blocked effect; or only the evaluator's
  own 63-bit intermediates overflowed while the program returned). Exit 1 on RED.
- **Gaps.** (a) A `refinement_unverified` hint whose skip stage 2 re-labels `reflect-fuel` /
  `reflect-budget` now carries the new reason (closes 1a ruling 8). (c) A parameter refinement
  calling a function the termination graph resolved AT THAT SITE to a unit translates through its
  logic symbol (`pre_of` runs with the arm on), and the callee is a fixpoint dependency; an
  ambiguous or unresolved site is R8 as before. This closes 1a ruling 9 (`pos_nat` guards) and
  changes four §0 probe expectations and `report_sort` (R8 -> reflected, reviewed).

## Rulings

1. **5b (constructors by the scrutinee's type) is not done; filed as `[P1]`.** The field registry
   is keyed by constructor name, so a user `Some(Int)` overwrites `Option`'s `Some(a)` for the
   whole program: the z3 log of `ctor2.march` declares every `Option` instance with an `Int`
   payload (`M_Option$M_Supervision ... (Some (Some_0 Int))`), stage-1 queries included.
   Resolving a body's `Some` to `Option` by type would build terms against the user type's
   fields: a guess. Ambiguity still declines; REJECT rows for colliding constructors in two
   modules and a user `Some`/`None` were added (green before and after). Cost if wrong: stdlib
   `Option` functions stay unfolded-less in programs declaring `Some`/`None`.
2. **Logic hash = source text + status + canonical template + `==` readings, non-transitive.** A
   caller's proof unfolds only depth 0 (D12), so a callee's callee's body never enters it; its
   identity is in the template as `name@file`. Cost if wrong: two functions of one display name in
   one file collide in `name@file` (the C-A shapes are already undecidable sites and decline).
3. **HCR: refuse outright, like a borrow-mode change, not the coordinated-upgrade path.** A caller
   frame already running was proved against the old body. Without the running build's manifest,
   a reflected function whose slot hash changed for a reason other than its modes is refused
   (cannot be told apart from a type change: conservative); with it, the `logic=` fields are
   compared. Without it, a function counts as a logic change when it is reflected in the patch,
   or when the running slot hash is not the plain `hcr_sig_hash` of the patch's type and modes
   (an unreflected slot publishes exactly that, so a different hash means it WAS reflected: now
   `@[opaque]`, effectful, or unreflectable through a callee). Review round 1 closed the gap the
   first version left here (that shape reached the coordinated-upgrade gate, which accepts it
   with only a warning once `hcr_epoch > 0`). Cost: with no running manifest, a type change of an
   unreflected function reads the same and is refused too (redeploy, or deploy with the running
   build's manifest, which `forge deploy` always passes when it has it). If the refinement check
   did not run in the compiling process, no logic hash exists and the gate sees `-` (the compile
   pipeline always runs it before TIR, `MARCH_REFLECT=0` aside).
4. **LSP refinement diagnostics are opt-in and on save.** Each check is a whole `march --check` of
   the file on disk (seconds), and an unsaved buffer is not what the compiler reads; on by
   default, existing LSP suites that read "the next publishDiagnostics" would see extra
   notifications. Cost: no refinement squiggles unless the editor sets `MARCH_LSP_REFINE=1`.
5. **The parity logic side evaluates the encoded term, not z3** (allowed by the brief). Exact on
   ground inputs; OCaml-int intermediates that overflow make the input undecided, never
   `overflow?` (that word is kept for the program overflowing).
6. **`overflow?` wins over agreement in a function's row**, so `inc` reads `overflow?` although
   100 inputs agreed: the overflow phase's list is the point (§9.2).
7. **`forge test --reflection-parity` checks each `lib/` and `src/` file** (as entries, with the
   project's MARCH_LIB_PATH), not the test entry, so a module no test reaches is still covered.

## Tests

Group `reflect-1b` (`test/test_refine_reflect1b.ml`, 11 cases), `reflect-parity` (4),
`lsp` group `refine-diagnostics` (`lsp/test/test_lsp_refine.ml`, 4), forge
`test_reconcile` `identity` case 5. RED -> GREEN (RED measured on a build of `0adbf4418` where the
row is a behaviour change):

| Row | RED | GREEN |
|---|---|---|
| 5a hint text | hint says `reason: solver-undecided` | names `reflect-fuel` and `cat` |
| 5c guard calls a reflected fn | `f` is `R8:… is_small is not predicate vocabulary`, `need_eq` skipped | `f` reflected, `need_eq` proved `uses: f` |
| 5c REJECT noisy guard / ambiguous guard | (new rules) | `f` not reflected |
| 5b REJECT ×2 | not proved | not proved |
| `d17_line` | no `; reflect` line | stage-2 query names `is_small`'s hash; no stage-1 query has one |
| `d17_eq_status` | (new) | `derive Eq` -> `impl Eq` changes `same`'s hash; a moved line does not |
| `sound_cache` second half | (new) | `small` losing reflectability (callee gains `println`) removes its D17 line |
| `sound_hcr` | slot sig unchanged on a reflected body edit | changes; `@[opaque]`: unchanged, no `logic=` |
| `dump_impl_hashes` | three columns | fourth column follows the body; `-` for `main`/`@[opaque]` |
| `parity` (fixtures) | (new) | 0 mismatch, 0 interpreter failure on all 26 phase fixtures + the parity program |
| `parity` overflow | (new) | `inc` at max Int is `overflow?` |
| `lsp_invalidate` | (no refinement diagnostics in the LSP) | before: no diagnostic; after `is_small` `n < 10` -> `n < 20`: app.march re-checked, `refinement_unverified`; an edit moving no frontier hash re-checks nothing |

### Perturbations (`MARCH_REFLECT_PERTURB=…`)

| Perturbation | Goes RED |
|---|---|
| `guard-no-dep` (a guard's callee is not a dependency) | both 5c REJECT rows |
| `hash-text-only` (the hash is the source text alone) | `d17_eq_status` |
| `hcr-no-logic` (the slot hash ignores the logic hash) | `sound_hcr`, forge `test_logic_changes` |
| `swap-arms` (first two cases exchange results) | `parity` swap row: `absv`, `get_or`, `first_or`, `len2`, `sign` MISMATCH |
| `r5-guarded` (R5 admits a guarded match) | `parity` C2 row: `guarded` INTERPRETER-FAILURE (match failure), RED, not "not compared" |
| `deps-core` (LSP keys on `uses:` cores) | `lsp_invalidate` frontier-vs-core row (a skip that would become a proof is not re-checked) |
| `ctor-guess` (an ambiguous constructor picks one datatype) | nothing: both 5b REJECT rows stay green (z3 rejects the ill-sorted query downstream); the rows are not perturbation-sensitive |

## Gates and oracles (private HOME; z3 4.16.0 locally, CI 4.8.12 not run)

- `scripts/run-tests.sh refinecheck`: 2,067 tests green (`reflect-1b` 11, `reflect-parity` 4).
- `scripts/run-tests.sh lsp`: 399 green (`refine-diagnostics` 4). Forge `test_reconcile`
  `identity`: 6 green.
- `scripts/run-tests.sh -q`: every suite green (run_errors 301 among them).
- `scripts/check-docs.sh`, `scripts/check-tree-sitter.sh`: green.
- Full `scripts/run-tests.sh` on `ff01ee663`: every suite green (compiler 1,454, eval 289,
  codegen 723, stdlib 899, refinecheck 2,067, lsp 399, errors 301, and the rest).
- Oracles, baselines recorded FIRST from a `git archive` build of `0adbf4418` (the record half of
  `scripts/oracle-base.sh`, cached), checked on the branch head:
  - `ir-oracle`: **IR IDENTICAL across 511 programs.** (The HCR fold changes only `--hot-reload`
    builds, which the corpus does not use.)
  - `refine-oracle check`: **IDENTICAL, 7,926 lines over 566 fixtures.**
  - `refine-oracle monotone`: **GREEN over 124,570 sites: RED 0, new proofs 0, new violations 0,
    withdrawn 0.** The three lists are empty; no corpus fixture has a guard that calls a reflected
    function, so 5c moves no corpus site.

## Review round 1

A soundness review found no false proof and four problems; each fixed test-first (RED measured on
the unfixed build, then GREEN):

1. **LSP staleness missed contracts.** A dependant was keyed only on the reflected bodies in its
   frontier, so `Util.need`'s parameter refinement going `v > 1` -> `v > 100` left
   `Util.need(3)` clean in the editor, and a callee going from blocked to reflected re-checked
   nothing. `--reflect-deps` now also prints `reflect-cdef` (a CONTRACT hash for every user
   function: BLAKE3 over its attributes, its head's text up to its last clause's body, and
   whether it is reflected, with its guards; `RS.contract_defs`, lazy) and `reflect-cdep` (the
   contract of every function of another user file the entry REACHES through the termination
   graph's edges, `RS.contract_reach`: a callee's reflectability rests on its own callees).
   `Refine_diag` keys on both and marks a dependant stale when any file the changed file's check
   reported (not only the changed file) no longer has one of its hashes. Rows in
   `refine-diagnostics`: contract edit (RED: 0 files re-checked), blocked -> reflected (RED: 0),
   a third file's effect unreflecting a callee (RED with direct callees only: 0; GREEN with
   reach). `deps-core` still turns the frontier-vs-core row RED.
2. **HCR: reflected -> unreflected with no running manifest** fell through to the
   coordinated-upgrade gate (`now = "-"`). Ruling 3 above is amended; `test_logic_changes`
   gains the `logic=""`/`"-"` rows (RED: 0 changes, GREEN: 1).
3. **`overflow?` with zero inputs compared** is now `not-compared` (the logic decided no input;
   the overflow is in the reason), and an `overflow?` row says `N inputs compared`.
4. **The parity net dropped reflected functions with no template** (and with no logic symbol at
   all, e.g. a `Float` parameter: `p1.march` printed `parity: 0 functions`). They are listed
   `not-compared` with the reason (`Refine_reflect.reflected_fns` supplies the ones without a
   symbol). `forge test --reflection-parity` runs each file once and reports a nonzero exit as
   parity RED only when the net printed `parity: RED`; otherwise "the check failed (no parity
   verdict)" with the check's diagnostics. Tests: `reflect-parity` rows 2-3 (RED: `overflow?`;
   no row for `f`), `test_build_check` "forge test" rows 3-5 (RED: a refinement violation read
   "reflection parity RED").

Gates after the round (private HOME where the suite sets one): `scripts/run-tests.sh -q` all
suites green; `lsp incremental jsonrpc` green (lsp 402, `refine-diagnostics` 7); `refinecheck`
2,069 green (`reflect-parity` 6); forge `test_reconcile` 23, `test_build_check` "forge test" 6,
`test_deploy_plan` 35, `test_hcr_manifest_diff` 3 green.

## Review round 2

A re-review of round 1 found three Important problems and one Minor; the three fixed test-first:

1. **Twin heads shared a hash.** `Util.A.need` and `Util.B.need` with the same text had one
   contract (and logic) hash, since both hash source text from the bare name; `stale_dependents`
   matched on (file, hash), so editing only A left B "carrying" app's key. `--reflect-deps` now
   prints every row under its QUALIFIED name (the entry module's own functions get its name
   back, so `A.need` in util's check is `Util.A.need`, as in a dependant's); `Refine_diag`
   matches (file, name, hash). The printed hash stays the D17 hash a query's `; reflect` line
   carries (folding the name in as well was tried and broke that link, `d17_line`). The `reflect-def`/`reflect-dep`
   logic-hash rows had the same exposure and get the same treatment; the proof-cache hashes
   (`RS.logic_hash`, `--dump-impl-hashes`) are unchanged.
2. **A function named in a callee's refinement was not keyed.** `need(n : {Int | _ < size()})`:
   `size`'s cdef covered only its head. Predicate-reference edges (every name in a parameter or
   return refinement, resolved by last component, same file first) now join `contract_reach`,
   and a unit a predicate names (and everything its body reaches) has its WHOLE source in its
   contract hash (`march-contract-v2`). Covers a `@[measure]` named in a refinement.
3. **The parity net was green when it compared nothing.** A run whose compared-input total is 0
   (and nothing RED) prints `parity: NOTHING COMPARED`; `march --check --reflect-parity` still
   exits 0 (nothing disagreed). Ruling: `forge test --reflection-parity` FAILS ("compared
   nothing") when every checked file compared nothing (the flag asked for evidence); a file
   with nothing to compare among files that did compare is fine.
4. **(Minor)** `plain_running` could never hold, so with no running manifest every non-mode
   slot change was refused with a misleading message. Not changed here: superseded by
   `cb1e4c26a` (the HCR rule is now "refuse only if a proof used the body"; slot hashes use the
   frontier-restricted `used_logic_hash_of_name`, and the no-manifest refusal branch became the
   `logic_unknowns` warning).

RED -> GREEN: `refine-diagnostics` twin, size-in-refinement, measure-in-refinement rows (RED:
"got 0 files"); `reflect-parity` row 3 (RED: no `NOTHING COMPARED`); `test_build_check`
"comparing nothing fails" (RED: Ok).
A refinement type alias in a head (`type Big = {Int | _ > 1}`) does not parse, so that shape
needs no key.

Gates after round 2: `scripts/run-tests.sh -q` all suites green; `lsp incremental jsonrpc` green
(lsp 405, `refine-diagnostics` 10); `refinecheck` 2,069 green; forge `test_reconcile` 23,
`test_build_check` 26, `test_deploy_plan` 35 green.

## CI round 1 (PR #1050): refuse only a proof-used body

CI failed four hot-reload tests from main (`observe_which_source`, adversarial regression 48
"running frames retain old ABI", and the ssh `deploy-e2e` acceptance): each hot-patches an ordinary
function (`Billing.price`, `count`, `Back.scale`) that automatic reflection (D1) reflects, and I9
refused every such patch. With D1 that blocks most business-logic hot patches. User decision
(2026-11-02): **refuse only if a proof used the body.**

- `Reflect_state.used_logic_hash_of_name`: the logic hash restricted to definitions some stage-2
  query of the build unfolded (`check_frontier`, the frontier, so a superset of the unsat cores).
  The slot hash (`bin/main.ml`, `hr_abi_sigs`) and the manifest's `logic=` use it;
  `--dump-impl-hashes` keeps the full logic hash (an identity column).
- **Ruling 3, amended again.** Review round 1 refused, with no running manifest, any slot change the
  modes did not explain. That also refused a coordinated type change (adversarial regression 48), and
  the two cannot be told apart without the manifest (the server has no query for its embedded one).
  Now: no running manifest and no logic hash in the patch is a warning
  (`Cmd_deploy_hot.logic_unknowns`), not a refusal. The patch build re-checks every caller against
  the new code; the residual gap is a running caller frame proved against an old body, deployed with
  no manifest. Cost if wrong: that gap. With the manifest, `logic=` is compared as before.
- Tests: `sound_hcr` now builds a proof-used `inc` (a caller `need_big(inc(1))`) and an unused one;
  the unused half was RED (the slot carried `logic=`), GREEN after. `test_logic_changes`: the two
  no-manifest cases flip to "not refused" and a `logic_unknowns` block covers the warning (RED: did not
  build). Locally green: reflect-1b 11, reflect-parity 6, reflect-report 28, reflect-unfold 49,
  forge reconcile 23, adversarial regression 48, `observe_which_source`. The ssh e2e needs Docker
  (not running locally); `Back.scale` is used by no refinement there, so its slot hash is plain.

## Not done, deferred or unverified

- 5b (ruling 1) and everything in `specs/todos/2026-10-31-reflection-encoder-gaps.md`.
- `lemma_in_body` and the lemma half of `lsp_invalidate` need `@[lemma]` (phase 2); the LSP key
  has the hook (`Refine_diag.lemma_key`), untested beyond "empty".
- The server wiring of `Refine_diag` (publish on open/save/watched change, merge with the
  analysis's diagnostics) is built but not driven by a JSON-RPC test; `Refine_diag` itself is.
- `forge test --reflection-parity`'s project walk is not driven by a test; its per-file runner
  (`Cmd_test.run_reflection_parity`) is, in `test_build_check` (review round 1).
- §9.2's always-in-CI corpus sweep (every reflected function of `test/native` and the stdlib) and
  `--reflect-report`'s `overflow?` mark are not built: the net runs on the phase fixtures in
  `reflect-parity`, and `overflow?` is printed by the net itself. The axiom-tier measures are in
  the net only when they also have a template.
- CI's z3 4.8.12 was not run; nothing new depends on unsat-core text (the D17 lines are comments
  the cache key reads).
- Timing was not re-measured: stage-1 text is unchanged and stage 2 gains one comment line per
  frontier function.
