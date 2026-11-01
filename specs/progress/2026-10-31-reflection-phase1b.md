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
   compared. Gap: a function that WAS reflected and is not in the patch (e.g. newly `@[opaque]`),
   with no prior manifest and every caller in the deploy, reaches the ordinary signature gate. If
   the refinement check did not run in the compiling process, no logic hash exists and the gate
   sees `-` (the compile pipeline always runs it before TIR, `MARCH_REFLECT=0` aside).
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
- Oracles, baselines recorded FIRST from a `git archive` build of `0adbf4418` (the record half of
  `scripts/oracle-base.sh`, cached), checked on the branch head:
  - `ir-oracle`: **IR IDENTICAL across 511 programs.** (The HCR fold changes only `--hot-reload`
    builds, which the corpus does not use.)
  - `refine-oracle check`: **IDENTICAL, 7,926 lines over 566 fixtures.**
  - `refine-oracle monotone`: **GREEN over 124,570 sites: RED 0, new proofs 0, new violations 0,
    withdrawn 0.** The three lists are empty; no corpus fixture has a guard that calls a reflected
    function, so 5c moves no corpus site.

## Not done, deferred or unverified

- 5b (ruling 1) and everything in `specs/todos/2026-10-31-reflection-encoder-gaps.md`.
- `lemma_in_body` and the lemma half of `lsp_invalidate` need `@[lemma]` (phase 2); the LSP key
  has the hook (`Refine_diag.lemma_key`), untested beyond "empty".
- The server wiring of `Refine_diag` (publish on open/save/watched change, merge with the
  analysis's diagnostics) is built but not driven by a JSON-RPC test; `Refine_diag` itself is.
- `forge test --reflection-parity` was run by hand on a scratch project (agree/overflow? green;
  under `swap-arms` it exits 1 naming the file); no automated forge test.
- §9.2's always-in-CI corpus sweep (every reflected function of `test/native` and the stdlib) and
  `--reflect-report`'s `overflow?` mark are not built: the net runs on the phase fixtures in
  `reflect-parity`, and `overflow?` is printed by the net itself. The axiom-tier measures are in
  the net only when they also have a template.
- CI's z3 4.8.12 was not run; nothing new depends on unsat-core text (the D17 lines are comments
  the cache key reads).
- Timing was not re-measured: stage-1 text is unchanged and stage 2 gains one comment line per
  frontier function.
