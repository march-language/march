# Refinement precision: local-value facts and predicate-language widening

**Date:** 2026-09-16
**Scope:** two independent efforts, sharing no code. Part A widens what the
checker *knows* about local values; Part B widens what a predicate may *say*.
Either can land without the other.

Both follow the set-refinements convention: one PR per phase, every step keeps
`test_refinecheck.exe` green, and every step is proven by a test that fails on
the code before it.

## 0. Facts that shape the plan

Established by reading the tree at `c17a36361`, not assumed.

1. **There are two fact channels, and a name must retire from both.** The
   *scope* channel is `(string * (string * A.expr * string option)) list`
   (`lib/refinecheck/refine_scope.ml:494`) — name to binder/predicate/sort
   marker. The *path* channel is an unnamed `(A.expr * bool) list` threaded
   positionally through `visit`. The header at `refine_scope.ml:1-21` states the
   discipline: "A name retired from one but not the other is the shadowing bug
   this pass has had before." Six `*_shadow` functions implement retirement
   (`scope_shadow` `refine_scope.ml:904`, `path_shadow` `:948`, plus `launder`,
   `recenv`, `cbenv`, `contenv`).
2. **A plain `let` records almost nothing.** The block walker
   (`refine_check.ml:786-994`) gives the bound name a binder span in `ctx`
   (a declaration, not a fact) and, only for a narrow RHS shape, the path
   equality `n == rhs`. The admitted shapes are decided by `let_equality_rhs` /
   `let_equality_operand` (`refine_scope.ml:975-990`): int literals and
   `+`/`-`/`*` (literal-scaled) over variables and literals. **Calls, `if`,
   floats, and a bare variable alias are all excluded by construction**, each
   with a written reason at `refine_scope.ml:955-974`.
3. **A callee's proved return refinement *does* reach the binding**, through
   the scope channel — `scope_add_binding ~postcond` instantiates the
   postcondition in the caller's namespace (`refine_scope.ml:1234-1241`). What
   is missing is a fact for callees with *no* contract, and for RHS shapes
   outside rule 2.
4. **The four user-code skips on `stdlib/list.march` are not all one bug.**
   Sites 321/363/395 are `let t = pmap_threshold()` — `pmap_threshold` is a
   **builtin** (`lib/typecheck/typecheck_builtins.ml:764`, `Mono t_int`), so no
   `fn_def` exists and no postcondition can be computed. Let-forwarding alone
   cannot close them; they need a declared contract on the builtin. Only site
   344 (`let csize2 = if csize < 1 do 1 else csize end`) is a pure let-flow
   case, and it needs **`if`-RHS support specifically**, not the arithmetic
   widening the rule's name suggests.
5. **The alias exclusion is load-bearing and pinned.** `let u = o` with
   `o : Option(Int)` once mixed an integer-sorted equality with datatype-sorted
   tester facts, and the sort-conflict gate **drops the whole VC, including
   unrelated obligations in the same function**. Pinned by
   `let_equality_alias_suite` (`test/test_refinecheck.ml:11798`) asserting an
   exact `(1, 0, 1)` ledger and that `sort-conflict` never appears.
6. **The self-mention guards are load-bearing too.** `not (expr_mentions names rhs)`
   (`refine_check.ml:884`) blocks `let k = k - 100` collapsing two `k`s onto one
   constant; `self_mentioning` (`refine_scope.ml:1229`) blocks
   `let t = push2(t, u)` with `{Tree | size(_) > size(t) + size(u)}` collapsing
   to `0 > size(u)` — **a contradiction that discharges any goal**, i.e. a false
   proof.
7. **`Smt.Mul` already exists and is already emitted.** `division_safety.ml:83-93`
   reflects general products and carries the reversal note: refusing them "was a
   REGRESSION source, not a safety measure: `{v : Int | v * v > 0}` is exactly
   `v != 0` over the integers and z3 decides it instantly". Only the *predicate*
   translator restricts to a literal coefficient (`refine_scope.ml:209-213`).
8. **The `Nonlinear_goal` skip reason was written and deliberately cut**
   (`obligation.ml:71-81`) as "an improvement in checker PRECISION, out of scope
   for a task that only explains existing skips". Part B revives it.
9. **March's `/` and `%` truncate toward zero; SMT-LIB's `div`/`mod` are
   Euclidean.** Source of truth `specs/lang/core-march.md:1040-1058`, implemented
   by OCaml's native operators at `lib/eval/eval_builtins.ml:30-42` and mirrored
   in `runtime/march_runtime.mjs:326-340`. `(-7) / 2` is `-3` in March and `-4`
   in SMT-LIB. Rendering `/` as `div` is unsound in the false-positive direction.
   Separate Euclidean builtins already exist (`int_div_euclid`, `int_mod_euclid`).
10. **The `@[measure]` gate already admits `/` and `%` with a non-zero integer
    literal divisor only** (`refine_encode.ml:3410-3414`). That is a written,
    tested precedent for the restriction Part B should adopt.
11. **The witness evaluator is hand-written, not the interpreter.** `eval_pred` /
    `eval_operand` (`witness.ml:289-400`) evaluate the *predicate*; its integer
    arithmetic arm (`witness.ml:350`) handles `+ - *` and **has no `/` or `%`**.
    An operator z3 can refute but `eval_operand` cannot evaluate yields an
    unconfirmable witness, which collapses to `Solver_undecided` — **silent
    outside `cap verified`**. Every new operator needs an arm here or the
    checker proves a violation and then reports nothing.
12. **The absorbing machinery for hard queries is already load-bearing.** z3 runs
    with `(set-option :timeout 3000)` (`lib/refine/solver.ml:68`) and no
    `(set-logic)`, and `unknown` becomes `Solver_undecided`, never an error
    outside `cap verified`.
13. **CI's z3 is unpinned and distro-supplied**: `apt-get install z3` on
    ubuntu-24.04 (4.8.12) and `brew install z3` on macOS
    (`.github/actions/march-setup/action.yml:42-44`). The 4.8.12 `par`-datatype
    segfault (`lib/refine/smt.ml:31-33`) is why parametric declarations are never
    emitted. Anything version-sensitive must be tested against 4.8.12
    specifically, and the unpinned install is itself a latent risk worth a
    separate todo.
14. **Ceilings that must not move the wrong way.** `--refine-audit
    stdlib/list.march` is 114 enforced / 0 inert / 0 unenforced, and
    `corpus_unenforced_ceiling = 0` is checked even under `UPDATE_SNAPSHOTS=1`
    (`test/test_refinecheck.ml:13485-13500`), so regeneration cannot launder a
    new unenforced site. `--refine-report stdlib/list.march` is 38 proved /
    31 trusted / 46 skipped, CI ceiling 46. Skips may only go **down**.

---

## Part A — carry facts from local bindings

**Goal:** an obligation whose subject is a local value gets decided instead of
skipped with `unconstrained-subject`.

**Honest sizing note.** The headline "42 of 46 skips are `unconstrained-subject`"
is a *whole-stdlib* figure and has not been attributed per site. The four
user-code cases are attributed (fact 4) and three of them are a builtin-contract
problem, not a let-flow problem. Phase A0 exists to replace the estimate with a
census before any encoder work is justified by it.

### A0. Census (no behaviour change)

Produce a per-site attribution of every `unconstrained-subject` skip in the
stdlib: the subject, the binding form that produced it, and which of the
following would close it — (i) an `if`-shaped RHS, (ii) a call RHS to a
contracted function, (iii) a builtin with no contract, (iv) a match-bound
variable, (v) something else. `--refine-report` prints the hint text but not a
machine-readable census; the cheapest route is a debug flag or a test-only
harness that dumps `(file, line, subject, reason)` rows.

**Exit:** a table in the progress entry. If category (i)+(ii) is a small
minority, Part A's later phases get re-scoped or dropped, and the effort moves
to whatever the census actually shows.

### A1. `if`-shaped RHS as a disjunctive fact

`let n = if g do a else b end` pushes
`(g && n == a) || (!g && n == b)` when both arms are admitted operands.
This closes `stdlib/list.march:344` (`csize2 >= 1` follows from both arms
without needing `csize`'s own definition, which contains `/` and is not
admitted).

- Extend `let_equality_rhs` (`refine_scope.ml:987`) with an `EIf`/`ECond` arm;
  keep `let_equality_operand` unchanged for the arms.
- Keep the self-mention guard (`refine_check.ml:884`) and the bare-alias
  exclusion (fact 5) intact for each arm.
- **Cost class to watch:** this introduces a *case split*, which is a different
  cost class from the existing conjunctive equalities. Measure a cold check
  before and after (fact 12's 3 s per-query timeout is the ceiling, but the
  regression that matters is aggregate compile time — see the 0.4 s → 20 s
  incident recorded at `refine_encode.ml:2130-2141`).

**Test:** `let-equality` suite (`test/test_refinecheck.ml:11683`), one ACCEPT
where both arms establish the bound and one REJECT-with-witness where one arm
violates it. Both must fail on today's code.

### A2. Contracts on value-returning builtins

Give builtins whose value is refinable a declared return refinement, so
`scope_add_binding ~postcond` has something to instantiate. `pmap_threshold`
(`typecheck_builtins.ml:764`) is the motivating case: `{Int | _ > 0}` closes
`stdlib/list.march:321`, `:363` and `:395`.

- Decide the mechanism first: a refinement on the builtin's `Mono` type changes
  its signature and therefore every caller's typecheck (`test/test_stdlib_suite.ml:5805`
  and `test/stdlib/test_list_parallel.march` reference `pmap_threshold`). A
  side table of builtin postconditions consulted by `postcond_of` may be the
  smaller blast radius. **This choice is the phase's real design decision** —
  make it explicitly and record why.
- Only builtins whose contract is *true by construction of the runtime* qualify.
  Each one is an `@[assume]`-class trust: it must appear in the trusted tally,
  not the proved one.

**Test:** `postcond-ledger` / `postcond-strict` suites; assert the three
`list.march` sites move from skipped to proved, and that the trusted count rises
by exactly the number of builtin contracts added.

### A3. Call RHS with a contracted callee — verify, don't extend

Fact 3 says this already works through the scope channel. A3 is therefore
**a verification phase, not an implementation one**: write the fixture that
proves it, and if it passes on unmodified code, say so in the progress entry and
close the phase. If it does not, the gap is in `scope_add_binding`'s sort-marker
admission (`refine_scope.ml:1310-1329`) — note `return_refine_sorted` has no
String arm (`refine_scope.ml:545`), documented at `:1284-1289`.

### A4. Re-measure and ratchet

Re-run the census from A0. Move the CI skip ceiling down to whatever the new
number is; a ceiling that is not tightened after a precision win silently
permits a future regression back to the old number.

### Explicitly out of scope for Part A

- **Substitution-into-the-rest** (the Tier 2 `inline_lets` approach,
  `refine_post.ml:900-1015`). Attractive because it declares no new symbol and so
  cannot cause a sort conflict, but it discards the `*_shadow` retirement
  discipline that fact 1 says is the historical bug source, and `subst_let`
  returns `None` for most nodes in a real function body. If A1–A4 stall, revisit
  this as a separate design, not as a patch.
- **Effectful RHS.** Calls are excluded from `let_equality_rhs` today on purity
  grounds. A value equation `n == f(...)` is sound for an effectful `f` *only*
  while the call is single-use and the equation is not duplicated; there is no
  purity predicate in `refinecheck/` to enforce that. `task_spawn` appears in the
  very functions being fixed (`stdlib/list.march:322`). Leave excluded.

---

## Part B — predicate-language widening

Three candidates, ranked. B1 is nearly free; B2 is real but bounded; B3 is
recommended **against** on the evidence.

### Shared plumbing (any new operator)

1. `predicate_operators` (`refine_encode.ml:902-909`) — omitting it makes
   `warn_predicate_expr` (`refine_check.ml:1486`, gate `:1503`) emit a spurious
   "no effect" warning, **and** makes `refine_call.ml:2413` / `refine_post.ml:1355`
   reflect the term as an opaque uninterpreted constant instead.
2. `smt_of_r_marked` (`refine_scope.ml:79-213`).
3. `Smt.term` + `children` + `render` (`lib/refine/smt.ml:88-160`, `:263-320`).
4. Roughly a dozen `Smt.term` traversals, several fail-closed: `wellsorted`,
   `formula_wellsorted` (`refine_encode.ml:251-401`), `pin_set_sorts` (`:1014`),
   the instance-sort solver (`:2718`), `term_sorts` (`:2932`), `undecided.ml:23-42`,
   `division_safety.ml:118-123`, `return_infer.ml:164`.
5. `witness.ml:350` (fact 11) — **the silent-failure trap**.
6. The vocabulary sync test, `test/test_refinecheck.ml:1954-1966`, whose
   hardcoded operator list is a lower bound, not a mirror.

### B1. Non-linear multiplication — do it

Replace the `| _ -> Error e` at `refine_scope.ml:212` with a general
`Smt.Mul`. Every downstream arm already exists (fact 7), `witness.ml:350`
already handles `*`, `"*"` is already in `predicate_operators`, and `unknown`
already absorbs what z3 cannot decide (fact 12).

- Revive `Nonlinear_goal` (`obligation.ml:71-81`) as a distinguishable skip
  reason so a nonlinear timeout reads differently from a generic
  `solver-undecided`. Slug at `obligation.ml:256`, prose at `:280`.
- **Invalidated fixture:** `test/test_refinecheck.ml:10786-10796` asserts a
  spurious-model case whose *premise* is that `x * x` is unreflectable. Rewrite
  it, don't delete it.
- **Measure latency.** Nonlinear goals that neither prove nor refute burn the
  full 3 s each and there is no per-module solver budget. Time
  `test_refinecheck.exe` and a cold check before/after.

### B2. `/` and `%`, restricted fragment — do it, semantics first

Adopt the `@[measure]` gate's existing rule (fact 10): admit `/` and `%` **only
with a non-zero integer literal divisor**, and additionally only where the
dividend is provably non-negative — truncating and Euclidean agree there, so
rendering as SMT `div`/`mod` is sound. Outside that fragment, keep returning
`Error e`.

- `syntactic_nonzero` (`division_safety.ml:32-60`) is directly reusable for the
  divisor side: it already takes `(binder, pred)` and answers "does this
  refinement imply non-zero".
- The non-negative-dividend condition needs reflection to be **assumption-aware**,
  which `smt_of_r_marked` is not today. That plumbing is the phase's main cost.
  Starting with literal-divisor-and-syntactically-non-negative-dividend avoids it
  for the first increment.
- **Add the `witness.ml:350` arms** implementing OCaml's *truncating* `/` and
  `mod` to match `eval_builtins.ml:31`/`:41`, guarding `y = 0` by returning
  `None` — an unguarded arm crashes the checker on a division-by-zero exception.
- **Rewrite the pinned fixture** at `test/test_refinecheck.ml:4979-4989`, which
  currently asserts that `_ / 2` is `unreflectable-predicate` with that exact
  message. It is the regression lock on the current behaviour.
- General truncation via `ite(a >= 0, div a b, -(div (-a) b))` needs an `Ite`
  node that `smt.ml` does not have, plus an arm in `formula_wellsorted`'s
  Bool-vs-Int structure. **Second increment, separate PR.**

### B3. Real string reasoning — don't, yet

The demand is not there: `grep '{String' stdlib/*.march` returns **nothing**, and
all 53 occurrences in `test_refinecheck.ml` are length comparisons
(`len(_) > 0`, `<= 3`) and empty-literal equality — exactly what the
uninterpreted `$Str` + `$strlen` encoding (`refine_encode.ml:78-112`) already
covers. The one documented gap is that `s == ""` manufactures no length fact
(pinned at `test/test_refinecheck.ml:1922-1932`), and that is closable with a
**single ground axiom** inside the existing fragment
(`(= (= s "") (= ($strlen s) 0))`) rather than a sort swap.

The full swap means a new `SStr` sort through `smt.ml`, retiring the
`mentions_str` / `wellsorted` apparatus threaded through ~20 call sites in
`refine_call.ml`, building a `Str_sort_gate` on the `Float_sort_gate` pattern,
and exposing an unpinned distro z3 4.8.12 (fact 13) to its weakest theory — on a
**shared long-lived `z3 -in` process where a crash poisons every subsequent VC in
the run** (`refine_encode.ml:95-102`). Not a bounded extension.

**Do instead:** the empty-literal ground axiom, as a one-phase change with the
existing `string-refinements` suite (`test/test_refinecheck.ml:16335`) as its home.

---

## Sequencing

| Order | Phase | Why here |
|---|---|---|
| 1 | B1 (nonlinear `Mul`) | Cheapest, pre-argued twice in-tree, no new soundness surface |
| 2 | A0 (census) | Replaces the headline estimate with attributed data before A1–A2 are justified by it |
| 3 | A1 (`if` RHS) / A2 (builtin contracts) | Ordered by what A0 shows; A2 is the one that closes three of the four known sites |
| 4 | B3′ (empty-string ground axiom) | One axiom, closes the only documented string gap |
| 5 | B2 (`/` and `%`, restricted) | Semantics work dominates; wants B1's fixture churn already settled |
| — | A3 | Verification only; fold into whichever phase runs first |

## Per-phase checklist

- `dune build --root .`; `scripts/run-tests.sh`; `./_build/default/test/test_refinecheck.exe`
  directly (~5 min, not in run-tests.sh's default selection).
- `rm -rf .march/cas/artifacts-v2` before every `--refine-report` / `--refine-audit`
  run, or it prints nothing.
- Audit stays at 0 unenforced; report skips go **down**, never up; tighten the CI
  ceiling in the same PR that earns the win.
- Cold-check timing on a trivial file before/after (baseline ~0.4 s).
- Verify against z3 4.8.12, not only the local 4.16.
- `specs/todos` → `specs/progress` and a `CHANGELOG.md` bullet in the same commit.
