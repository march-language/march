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
  stand only when some obligation improved (skip → proved/violated; since the third review, never violated → proved) and none got
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

12. **A measure whose sort the encoding cannot model is not an error.** The final full run found
    three suites (`measures-p1b`, `const-fn-predicate`) pinning a `@[measure]` over an undeclared
    `Tree(a)` that falls back to symbolic reasoning; under option A it was `invalid_measure` (R8).
    The reference has always said such a measure is not an error, so the gate ignores an R8
    blocker, in both tiers. Same run: a `/ -2` divisor (`negate(2)`) was R4 in the analysis while the
    gate and predicate translator treat it as the literal it is; R4 and `term_of_body` now use
    `Refine_encode.nonzero_int_literal` too (`gate-mb`). And `const-fn-predicate`'s "two-parameter
    `@[measure]` is an error" is now "accepted (F2 lifted)", as the design says.

13. **A stage-1 violation is never withdrawn in phase 1a** (coordinator's ruling after the third
    review, I1). Stage 2 proving an obligation stage 1 found violated keeps the violation and its
    error, and `MARCH_REFLECT_DEBUG` prints a `reflect-disagree` line; a witness-confirmed one is
    still `reflect_inconsistent`. Why: the witness rarely confirms a violation in a function with
    parameters, so an encoding mistake (the third review's `lx/m9`) turned into a silently vanished
    error. Cost if wrong: a few violations found on a model the program never reaches (the
    `spurious_refutation` row: a call under `if n > 20` and `if is_small(n)`) stay reported. Restore
    the withdrawal when stage 2 can show such a path dead from path facts alone.

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
- The oracles and timings above were measured on `07b186292`, before ruling 12's fix. That fix only
  removes errors (R8) and admits `/ -k` divisors into reflection; the monotone and IR oracles were
  not re-run after it.

## Review fixes (fresh-context review of `835ab1e6f`)

Three ways to prove an obligation that is false at run time, each a REJECT row in `reflect-unfold`
(group `review`), written first and run against a build of `835ab1e6f` (RED), then against the fix
(GREEN). The probes are the reviewer's, with their interpreter output in each row's comment.

| Row | `835ab1e6f` (RED) | Fix (GREEN) |
|---|---|---|
| C-1 `clo`: a parameter `inc`, a local lambda `inc`, a path condition `if inc(y) == 2` | `need2 at line 7 must NOT be proved` (`proved … uses: inc`; runs `51`) | not proved (4 sites) |
| C-2 `nest2`: inside `B`, `A.f` is `Top.B.A.f` | `B.need2 at line 13 must NOT be proved` (runs `3`) | violated (3 sites) |
| C-2 `nest3`: a predicate in `Inner` naming `f` | `Inner.needf at line 7 must NOT be proved` | `needf(2)` violated, `needf(3)` proved through `Inner.f` |
| C-3 `neg`: user `negate`, `n / negate(2)` and `n / -2` | `needm12 at line 7 must NOT be proved` (runs `2 3`) | not proved |
| C-3 `neg2`: `negate(n) = 0 * n` | `need_neg at line 8 must NOT be proved` (runs `0`); `h` reflected as dividing by -2, panics at run time | `need_neg(-12)` not proved; `h` is `no R4` |

- **C-1, C-2: one resolution rule, by site.** `Reflect_state.resolve` (spelling: display name, then
  the enclosing module's prefix) is gone. Every channel (the predicate translator's arm, path
  conditions, `let` facts, the scalar and datatype subjects, `len` of a call) now asks
  `Reflect_state.resolve_site span`: the termination graph's own lexical resolution of THAT
  application node (locals, parameters and lambda binders shadow; nested modules innermost first;
  and, since the second review, a name two declarations could supply is not resolved at all; see
  below), the identity `term_of_body` already used. Calls inside a signature's
  refinement predicates were not in the graph; `Refine_term.build_graph` now walks them too
  (`graph.pred_sites`), in the function's scope with its parameters and the predicate's binder
  shadowing, recording a resolution and no edge. A site the graph did not resolve to a reflected
  unit (a `let` annotation, a lambda's type, a parameter, an unresolved name) is not unfolded.
- **C-3: `negate` by identity.** `Reflect_state.negate_builtin_at` answers, per application node,
  whether its `negate` is the builtin, from the same graph (`sites` and `pred_sites`); a node the
  graph never saw counts as the builtin only when no `negate` is defined outside the stdlib nor in
  that file. Every spelled `negate` arm checks it: `nonzero_int_literal` (R4, `term_of_body`, the
  measure gate, the predicate translator's divisor), constant folding, `int_lit_of`,
  `known_nonneg`'s literal, float folding, the predicate translator's `Neg`, and the witness
  interpreter's evaluation. The predicate-side half (`need_neg(-12)` proved while the program
  passes `0`) predates this branch; it is fixed by the same change. Under a user `negate`,
  `needm12(-12)` may still prove: a predicate's `-12` is the user's `negate(12)` there too, exactly
  as program code, so `0 == 0` holds and the row asserts the proof goes through the user's function.
- **Constructor and sort lookups by name (audit).** `term_of_body` built constructor terms with
  `Refine_encode.sort_of_ctor` (the FIRST datatype declaring the name), and testers and selectors
  are keyed by the constructor name in SMT. With two datatypes declaring `None`/`Some` (the
  reviewer's `ctor.march`) every probe was skipped before, but only because z3 rejected or the sort
  resolution dropped the ill-sorted equation, not by rule. Now `term_of_body`, its patterns and the
  unfolding guard decline when a constructor name belongs to more than one registered datatype,
  and a signature declines when a type's short name has two declarations (`adt_decl_paths`); such a
  function keeps an uninterpreted symbol. `ctor.march` re-run: all six sites skip.
- **Honest rows.** `sound_eq_float` is renamed a control (no Float function is reflected in 1a);
  `sound_domain`'s `need_t` row says it passes because `p` is metric-certified and not reflected;
  `sound_mangle`'s two `not_proved` rows say they are `reflect-fuel`, the mangling being checked
  by the symbol names.
- **`R7:names not as a value`** in `c2b_bool_measure.expected` was the documented parser todo (`not
  even_len(t)` at a block start parses as two statements, `not` and the call). The fixture now
  writes `not(even_len(t))`, so it tests the recursive Bool measure it means: `even_len` is
  `reflected`, its two calls `reflect-fuel`. `r1_dom1` keeps the spelling, since it is the spec's
  probe r1 as written and the phase-0 note pins that reading.

### Second review (of `71f112f4a`): names two declarations could supply

`resolve_site` was right, but the termination graph's name table under it was not. Each probe is a
REJECT row in `reflect-unfold` (group `review2`), RED on a build of `71f112f4a`, GREEN on the fix:

| Row | `71f112f4a` (RED) | Fix (GREEN) |
|---|---|---|
| C-A `sl/` (lib `Y` calls `List.sum_int`; entry `M` has a nested `mod List`) and `slist2` | `need42` in `y.march` proved (both backends print 3) | skip |
| C-A `ml/` (lib `Y` calls `X.g`; lib `X` and nested `M.X`) | `need51` in `y.march` proved (both backends give 2) | skip |
| C-A `ml/` with both `X.g` reflectable | `internal error: the logic symbol \|r:user:X.g\| would name two definitions`: a valid program failed to check | checks; both sites skip |
| C-B `al1/m`, `al1/m2` (`alias A as B` beside a `mod B`) | `need51` proved (both backends give 2; m2 interpreted 51) | skip |
| `sound_mangle`'s user `mod List` (an existing row) | asserted `proved … uses: List.append` | not proved: that call is ambiguous too (the old assertion pinned exactly the C-A shape) |

- **Cause.** The entry module's declarations register at path `""` (and `M.`), so its nested
  `mod List` writes the key `List.sum_int` that the stdlib's `List` also writes, and a library `X`
  meets a nested `M.X` at `X.g`; `Hashtbl.replace` kept the last. `lookup` tried lexical module
  paths before aliases, while the typechecker lets `alias` rebind the short name.
- **Fix: ambiguity is unresolved.** `build_graph` now records every declaration position under
  each key (`reg_pos`) and every module path. A lookup whose key has two declarations, whose level
  also gets the name from a `use`, or whose dotted head is both an `alias` in scope and a visible
  module sets an ambiguity flag; the site lands in `graph.ambiguous`, and reflection never
  unfolds it (program code and predicates alike). The graph's own pick, and so every termination
  certificate and the phase-0 report, is unchanged. No backend precedence is copied: the
  interpreter and the compiled build disagree on these very shapes (filed `[P1]`,
  `specs/todos/2026-10-30-interpreter-compiler-name-resolution-diverge.md`; it predates
  reflection).
- **Symbols carry the declaration's position**, `|r:user:X.g#x.march:2:5|`, so two definitions can
  never share one; the duplicate guard drops both silently instead of reporting an internal error.
- **`ctor2.march` (minor).** With a user `type Mb = Some(Int) | None`, the stdlib-`Option` function
  `o` is not unfolded (`need(o(Some(99)))` skips); the control without the user type proves it
  (`uses: o`). Cause confirmed: `term_of_body` declines a constructor name two datatypes declare.
  Sound, an over-refusal; resolving constructors by the scrutinee's type is left for 1b (in the 1b
  todo).
- `ml/src/m.march` alone (no reference to `Y`) loads no `y.march` obligation, so the `ml/` row uses
  `m5.march` as its entry.

After the second fixes: `dune build --root .` clean; `scripts/run-tests.sh refinecheck` 2,048 tests
green (`reflect-unfold` 45 cases); `run_errors` 301, `check-docs.sh`, `check-tree-sitter.sh` green.
The coordinator's full `scripts/run-tests.sh` on `71f112f4a` passed every suite; it was not re-run
after these fixes.

### Third review (of `0d526d1e2`): a reflected wrapper around an ambiguous name

| Row | `0d526d1e2` (RED) | Fix (GREEN) |
|---|---|---|
| C1 `lx/m7` (lib `Y.w(n) = X.g(n)`, entry `k(n) = M.X.g(n)` with a nested `mod X`) | `need0(Y.w(1) - k(1))` proved (runs `2` and `51`) | skip |
| C1 `ly/` (lib `Y.w(xs) = List.length(xs)`, entry nested `mod List`) | `Y.w` reported `reflected`; `need42` was already a skip (the graph's guess happened to be the stdlib `List.length`, which agrees with the run) | `Y.w` is `no R6:calls List.length, a name more than one declaration could denote`; skip |
| C1/I1 `lx/m9` | stage 1 `violated`, stage 2 `proved`, withdrawn as Better | violated, error kept |
| `spurious_refutation` (existing row) | asserted `proved` (withdrawn) | asserts `violated`, error kept (ruling 13) |

- **C1.** `term_of_body` read callees from the raw site table and never consulted
  `graph.ambiguous` (only the frontier's `note` did), so the graph's guess became a wrapper's
  definition. Now an ambiguous call site in a body is an R6 blocker in the §2.1 analysis
  (`calls X.g, a name more than one declaration could denote`), so the function, and through the
  fixpoint every caller, is not reflected and the report says why; `tr_val` also declines on the
  same predicate (`c_ambiguous`), in every branch, as a second guard. The `reflect_state.ml`
  docstring now says so.
- **I1.** Ruling 13 above.
- **M1.** `install`'s hand-written-`Eq` set and type table are keyed by bare name over the whole
  module (entry, libraries and stdlib alike); a bare type name declared more than once now counts
  as non-structural, so a library type with a hand-written `Eq` can never lend its name to a
  structural entry type (or the reverse). Not reproduced by the reviewer's `heq/m4.march`; fixed
  because it was cheap.
- **M2** (a qualified library constructor declines) is left as is: an over-refusal.

`report_len_shadow_module` (phase 0) now names the new, more precise reason for its `f` (the user
`mod List` makes `List.length` ambiguous). After the third fixes: `dune build --root .` clean;
`scripts/run-tests.sh refinecheck` 2,051 tests with that one expectation failing, then the
`reflect-report` group re-run green after the update (28); `reflect-unfold` 48 green; `run_errors`
301, `check-docs.sh`, `check-tree-sitter.sh` green. The full refinecheck suite was not re-run after
that one-line test update.

**Oracles were not re-run after these fixes** (coordinator's instruction): the monotone and IR
results above are from `07b186292`.

After the fixes (branch head): `dune build --root .` clean; `scripts/run-tests.sh refinecheck` 2,044
tests green (`reflect-unfold` is 41 cases); `run_errors` 301 green; `check-docs.sh` and
`check-tree-sitter.sh` green. The full `scripts/run-tests.sh` was not re-run after the fixes.

## Final test runs (before the review fixes)

`scripts/run-tests.sh` on `07b186292`: every suite green except `test_refinecheck` (6 failures, ruling
12); after the fix, `scripts/run-tests.sh refinecheck`: 2,039 tests green. `run_errors`: 301 green.
`scripts/check-docs.sh` and `scripts/check-tree-sitter.sh`: green.
