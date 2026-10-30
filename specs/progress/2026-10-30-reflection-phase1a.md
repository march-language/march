Refinement reflection, phase 1a: single unfolding of automatically reflected first-order functions,
the two-stage discharge, the two equalities, the measure merge and `@[opaque]`
(`specs/2026-10-29-refinement-reflection-design.md` §10 phase 1, first half; phase 0 is
`specs/progress/2026-10-29-reflection-phase0.md`, whose rulings bind here).

## What landed

- **Reflection is active.** `Refine_check.check_module` runs `Refine_reflect.install` once per module
  (after the termination graph, before any obligation): the §2.1 fixpoint with the inputs available
  before the walk (ruling R2 below), a logic symbol per reflected function, its polymorphic signature
  and its body as guarded cases. `MARCH_REFLECT=0` turns it off; it is an A/B switch for the oracles,
  not a user setting.
- **Symbols (§3.1, I4).** `|r:<std|user>:<TERM display name>|`, a local also `#<line>:<col>`
  (`|r:user:f/go#3:5|`); one instance per sort tuple, `|r:…@Int|`, renamed by `resolve_sorts` and
  declared by `query_instance_preamble`. A symbol claimed by two units drops both and is an internal
  error. `sound_mangle` checks four `go`s (two functions, two in sequence in one) are four symbols.
- **Sorts (§3.2-3.3).** `Int`, `Bool`, registered data types at their instance, type variables as
  `SParam` (unified per call by `resolve_sorts`, `Elem` when open). A result `Bool` is a formula
  (`formula_wellsorted`), which is F5's fix for reflected functions.
- **`term_of_body` (§3.4).** `Refine_reflect.tr_case` / `tr_val`: one case per path, each guarded by
  its arm's tester/literal/guard conditions and the negation of every earlier arm; **no default arm**
  (C2). `if` splits in tail position, is `ite` in value position; `let x =` substitutes; a tuple
  scrutinee of a multi-head function is matched componentwise. Callees by resolved identity: the
  TERM site at the call span (a reflected unit, the stdlib `List.length` as `$len`, or a builtin of
  the §2.3 table); anything else declines and the function keeps an uninterpreted symbol with no
  equations (sound, weaker). Two parameters of one name decline (found by `abstract-multiarg-review`
  C3, below).
- **Guarded unfolding (§3.6, C1).** For each reflected call of the query (goal, then assumptions in
  order; the depth-0 frontier, §3.7) every case is asserted as `(pre_f(args) ∧ cond) ⇒ f(args) =
  result`, all behind one assumption literal `|$ru_<k>:<function>|`. A call the unfolding produces is
  not unfolded (D12) and marks the run `reflect-fuel`; more than 32 frontier calls marks
  `reflect-budget`.
- **Connecting facts (§3.7).** The predicate translator's reflected-call arm; a reflected call as a
  subject (`reflect_scalar`, `reflect_dt`, and `len` of one); `let r = f(x)` as the path fact
  `r == f(x)` (from the launder list). All of these exist only in stage 2.
- **Two-stage discharge (§4.4)** (`Reflect_stage.two_stage`, around `check_call` and `check_post`).
  Stage 1 is today's check. If it did not prove everything it filed and met a reflected call, its
  records and diagnostics are set aside and the check runs again with the arm on; stage 2's records
  stand only when some obligation improved (skip → proved/violated, violated → proved) and none got
  worse; a run that files nothing (the propagation pre-pass) is judged by its answer. A stage-1
  violation the witness interpreter confirmed and stage 2 proves is `reflect_inconsistent` (I7) and
  stays violated. Counters the check advances (`ret_ctr`, the hint throttle, promoted sites, the
  witness budget) are restored, so every later query is today's text.
- **Stage-2 queries** (`lib/refine`): `check-sat-assuming` over the literals, a 1 s timeout, the unsat
  core read back and cached beside the verdict (`<key>.core`), an in-process negative cache of
  `unknown`s keyed by VC text, z3 path and timeout (never on disk). Unsat cores are enabled lazily
  before the first stage-2 query. `Refine.well_formed` refuses a query that names an undeclared logic
  symbol (found by `z3-well-formed`, below).
- **Reporting.** Skip reasons `reflect-fuel` (naming the function left unfolded) and
  `reflect-budget`; `--refine-report-sites=all` prints `uses: f, g` on a stage-2 proof (the core's
  literals; the whole frontier when the core names none, congruence, I8); `refine-oracle.sh
  monotone` ignores that column. The vocabulary warning is silent for a reflected function and, for
  one that exists but is not reflected, names its first blocker (§2.4).
- **Equality (§3.5).** In a predicate, unchanged: structural. In a reflected body, the program's
  `==`: SMT `=` at `Int`, `Bool`, `String` and a type whose `Eq` is derived all the way down with no
  `Float`; otherwise the opaque `|r:eq@T|` (Bool-valued, per instance). R6 already blocks `==` over an
  `eq` that fails R2-R7 (C4, phase 0). `predicate_eq_structural` (new code, page, corpus case
  `predicate_eq_structural_1`) warns at a predicate `==` whose operand is the binder or a
  constructor of a type with a hand-written `Eq`.
- **Measures (§5, option A).** A one-parameter `@[measure]` with an `Int`/`Set` (or unannotated)
  result keeps the axiom tier, exactly as before, and its predicate symbol never reaches stage 2
  (I10). Several parameters (F2's error removed), a `Bool` (F5) or data-type (F6) result: the
  unfolding tier, not registered as a measure. Either tier must be reflected, else `invalid_measure`
  naming the first blocker; the axiom tier's syntactic gate keeps its wording and the structural
  wording where R2 blocks.
- **`@[opaque]` (§2.5).** `AT LBRACKET OPAQUE RBRACKET` in `parser.mly`; `grammar.js`'s attribute takes
  `'opaque'` beside `$.identifier`, with a corpus case; `known_fn_attributes`; with `@[measure]`
  `reflect_conflict`; on a function not reflected anyway `attribute_no_effect`.
- **The stdlib** is reflected under the same rules. No stdlib function is marked `@[opaque]`: none
  was measured to slow checking (timing below), and no stdlib body change is pending.

## Rulings

1. **Phase 1 is split; this is 1a.** 1b (`specs/todos/2026-10-30-reflection-phase1b.md`): §7.1 D17
   hash lines and the core in the proof cache keyed by them, §7.2 LSP invalidation and `logic_hash`,
   the HCR refusal (I9), §9.2's parity net; RED rows `lsp_invalidate`, `parity`, and `lemma_in_body`
   (needs `@[lemma]`, phase 2; not tested here, a lemma-shaped call cannot be built without the
   attribute). Cost if wrong: until 1b, a reflected body edit can change a caller's proof without
   the D17 line saying so (the VC text still changes, so no stale cache verdict: `sound_cache`), the
   LSP may show a stale proof until the file is re-checked, and a hot patch to a reflected body is
   admitted.
2. **The encoder's R2 and R4 are the pre-walk halves.** Metric certificates and `Division` verdicts
   are decided by the walk and by `Division_safety`, after the encoder must exist, so the encoder
   reflects structural / non-recursive functions only and blocks every division by a non-literal.
   `--reflect-report` is unchanged (it re-runs the check for certificates). Cost: metric-certified
   functions (probe r1's `p`, so `sound_domain` exercises the guard with a non-recursive refined `pos`
   instead) and the ~8 stdlib dividers are not unfolded. Never unsound: it only removes functions.
3. **Stage 2 re-runs the whole check, not just the query.** Unfoldings must enter before sort
   resolution, and the translations that produce the frontier (subject, path, lets) are interleaved
   with the rest of `check_call`; re-running it with the arm on, then choosing per call, is what keeps
   stage 1 byte-identical by construction. Cost: a stage-2 run repeats the obligation's non-solver
   work; measured below.
4. **Per-call choice, never worse.** Stage 2 replaces stage 1 for a whole call only when no
   obligation of that call got worse. A `proved → skipped` move is therefore impossible by
   construction, not only by the gate.
5. **Float and String are not encoded.** A function whose signature mentions either has no logic
   symbol (§2.3's opaque Float operators and distinct `$Str` literals are 1b work). `sound_eq_float`
   passes because no such function is reflected into the logic; the `eq-structural` perturbation
   therefore cannot turn it RED (it does turn `sound_eq` RED). Cost: fewer proofs; no Float or NaN
   reasoning can go wrong.
6. **`budget` tests the cap where 1a can reach it.** The design's `s40(0)` needs 41 unfoldings along a
   chain, which single unfolding never reaches (it is `reflect-fuel`). The test puts the 40 calls in
   the predicate itself: 40 frontier calls is `reflect-budget`, 20 prove.
7. **`stage2_timeout` asserts the negative cache, not a measured second.** A query that takes over
   1 s is not reproducible across z3 versions; the test uses a non-linear goal (`cube`), checks it
   is not proved, and that the second identical stage-2 query is an in-process hit
   (`stage2_unknown_hits >= 1`). The 1 s is the option sent; not separately timed.
8. **Hints keep stage 1's text.** When stage 1 stands and its skip is re-labelled `reflect-fuel` /
   `reflect-budget`, the ledger and `--refine-report` carry the new reason, but a
   `refinement_unverified` hint already emitted names stage 1's reason. Cost: a cosmetic mismatch in
   one diagnostic.
9. **Unfolding-tier measures are not predicate vocabulary for R8.** A function refined by
   `pos_nat(_)` is now `R8:… pos_nat is not predicate vocabulary` in the report (it was reflected with
   that guard in phase 0, when `pos_nat` was a registered measure). Cost: such functions are not
   unfolded; filed in the 1b todo.
10. **Existing fixtures that need an opaque helper say `@[opaque]`.** Fourteen test-program helpers
    (`small`×2, `two100`, `h`×2, `f`, `abs1`, `inc`×5, `dec`, `add`) and the corpus fixture
    `test/native/simd_lane_panic.march`'s `lane` exist to be untranslatable or to make inference
    propose a contract; reflection would see through them. Marking them `@[opaque]` keeps each test's
    point; one expectation changed instead (`demand-chains` G1, `inc(h(n))` with a proved `h` now
    proves through `inc`'s body).
11. **`check-tree-sitter.sh` lists regular files only.** A cache directory named `.march/` under
    `test/` or `examples/` matched `-name '*.march'`, and parsing it shifted tree-sitter's batch
    state so a known failure parsed "clean": the gate went red for a reason unrelated to the grammar.

## Tests

Group `reflect-unfold` (`test/test_refine_unfold.ml`, 36 cases, all through the real driver,
asserting obligation rows): the phase-1 RED table (`guard_pred`, `pred_call`, `subject_call`,
`let_result`, `one_step`, `no_second_step`, `two_arg`, `list_result`, `bool_measure`,
`measure_alias_ok`, `measure_alias_err`, `measure_tier`, `stage2_timeout`, `eq_handwritten`,
`eq_derived`, `opaque`, `opaque_no_effect`, `opaque_conflict`, `two_stage_identical`,
`spurious_refutation`, `budget`) and the §9.1 rows phase 1 closes (`sound_diverge`, `sound_partial`,
`sound_eq` with the transitive `Q(P)` and the derived control, `sound_eq_float` with an `Int`
positive control, `sound_eq_effect`, `sound_fnvalue`, `sound_dispatch`, `sound_domain`,
`sound_guarded`, `sound_shadow`, `sound_mangle` ×2, `sound_inconsistent`, `sound_uses_warm`,
`sound_cache`). `two_stage_identical` checks every a*/b*/c* probe: every query a reflection-off run
sends z3 is sent byte for byte by a reflection-on run.

Two regressions the existing suites caught, both fixed before this note:
- `z3-well-formed`: a reflected symbol reached a discharge path that never declares it (13 malformed
  queries); now refused (`Refine.well_formed`).
- `abstract-multiarg-review` C3: `fn two(a : Int, a : Int)` was reflected reading the first `a`; the
  program reads the second, so `if two(y, 1)` "proved" `y > 0`. Unsound; now no definition.

### RED perturbations

| Perturbation (`MARCH_REFLECT_PERTURB=…`) | Goes RED |
|---|---|
| `no-guard` (unfoldings lose `pre_f`, C1) | `sound_domain` |
| `eq-structural` (body `==` is SMT `=` at every type, D7) | `sound_eq` |
| `budget-64` (cap raised) | `budget` |
| `no-negcache` | `stage2_timeout` |
| `false-unfold` (every unfolding asserts `false`) | `sound_inconsistent` asserts `reflect_inconsistent` under it; over the corpus, 3,344 `skip → proved` lines at 38 distinct sites (below) |
| duplicate-parameter decline removed (the pre-fix code) | `abstract-multiarg-review` C3 |
| `Refine.well_formed` removed (the pre-fix code) | `z3-well-formed` |

Not separately perturbable: the no-default-arm rule (R5 already bars a match that can fall through,
so no reflected body has an input that matches no arm); resolution by identity (a spelling-based
resolver has no switch; `sound_shadow` and `sound_mangle` (user `mod List`) pin the behaviour).

## Oracles (private HOME; z3 4.16.0 locally, CI 4.8.12)

Baselines from `da209e9d2` extracted with `git archive` and built there (`dune build --root .
bin/main.exe @bin/warm-cache`, staging that commit's stdlib), before any edit.

- `scripts/refine-oracle.sh monotone`: **GREEN over 121,704 sites (553 fixtures): RED 0, new proofs 0,
  new violations 0, withdrawn violations 0.** The three lists are empty, so there is nothing to
  explain line by line. That is not the oracle being blind: the same sweep under `false-unfold`
  lists 3,344 new proofs at 38 distinct sites (stdlib `Stats`, `List.nth`-shaped bounds and similar
  sites whose frontier holds a reflected stdlib call), so stage 2 runs on the corpus and the gate
  sees its verdicts; with the real definitions, none of those queries closes. The one corpus change
  is `test/native/simd_lane_panic.march` (ruling 10). Before it, the fixture had a **new violation**
  (`lane(1)` is 6, outside `Simd.extract_i32x4`'s `0 <= _ && _ < 4`), seen by `run_codegen`'s IR
  validity gate, which compiles every native fixture and so stopped at the error: a true finding
  about a fixture written to panic at run time. It was resolved by marking `lane` opaque on its own
  line (no line shift) before the sweep, so the sweep does not list it.
- `scripts/ir-oracle.sh check`: **IR IDENTICAL across 498 programs.**
- Error corpus: `run_errors` 301 cases green (one new, `predicate_eq_structural_1`).

## Timing (§6.3)

Interleaved A (base `da209e9d2`) / B (this branch), five runs, median, `--check --refine-report`
(which bypasses the early source CAS), private HOME per side, `.march/cas/vc` cleared once per side
before the first run; load average 4.3-6.3.

| | A median | B median | B/A | Budget |
|---|---|---|---|---|
| `stdlib/list.march` | 1.266 s | 1.307 s | 103.2% | ≤ 105% |
| `stdlib/json.march` | 1.270 s | 1.329 s | 104.6% | ≤ 105% |

Corpus sweep (the 553 refine-oracle fixtures, `--check --refine-report --refine-report-sites=all`,
A and B interleaved per fixture, one pass, private HOME and VC cache per side; load 3.4-6.3): **A
426.4 s, B 457.2 s, 107.2%** (budget ≤ 110%). Per fixture: the largest ratio is 116.4%
(`let_shadow_rebind`), so no fixture is over 150% and every fixture is within the 120% row for
callers of reflected stdlib functions; none crossed 3 s. (`simd_lane_panic` is excluded: the base
compiler stops at its new `@[opaque]` with a parse error in 0.03 s.) The sweep was one pass, not
five: a deviation from §6.3's protocol for the sweep row only.

## Not done, deferred or unverified

- Everything in ruling 1 and in `specs/todos/2026-10-30-reflection-phase1b.md`.
- The todo "predicate vocabulary shadows user functions" stays open: R11 blocks the user function
  from reflection and resolution is by identity, but no warning at the declaration exists yet.
- CI's z3 4.8.12 was not run. Its unsat cores may differ from 4.16's; the `uses:` tests assert
  containment of one function, which both versions should give.
- Each commit was not built on its own; the branch head is.
