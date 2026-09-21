# Plan: the remaining refinement backlog

**Date:** 2026-09-21
**Covers:** every open refinement todo on `main` as of `f3867e53d`, plus the
unfinished phases of `specs/2026-09-20-abstract-refinements-design.md`.
**Not covered:** `specs/todos/2026-07-11-p2-compiler-docs-perceus-rc-refinement-types-core-march-widening.md`,
which is blocked on compiler work that does not exist (an escape-analysis RC
pass, or an FBIP semantic-preservation theorem). Nothing to plan until one
lands. `2026-08-03-cap-sandbox-remaining.md` is the capability sandbox despite
its title, and is out of scope here.

## The order, and why

| # | Item | Todo | Effort | Gated on |
|---|---|---|---|---|
| 1 | Tier 2's induction hypothesis trusts component names | element-flow item 5 | ½ day | — (soundness-adjacent, do first) |
| 2 | Abstract refinements phase 2: the filter rule | design §3–§4 | 3–4 days | phase 1 (#543) |
| 3 | Non-linear arithmetic in an argument | `2026-09-18-refine-nonlinear-argument-reflection` | 1 day | — |
| 4 | Scalar demand on a single-element result | element-flow item 1 | 1 day | — |
| 5 | Abstract refinements phase 3: named callables, more stdlib | design §7 | 2 days | 2 |
| 6 | Relational element returns at a call site | element-flow item 4 | 1–2 days | — |
| 7 | A local `fn` with a container return | element-flow item 3 | 1–2 days | — |
| 8 | Domain facts for multi-parameter lambdas | element-flow item 2 | 2–3 days | 6 (shares the substitution) |
| 9 | `/` and `%` in predicates | `2026-09-16-refine-predicate-language-widening` | 2 days | — |
| 10 | Stdlib wrapper contracts | `2026-09-16-refine-stdlib-wrapper-contracts` | 1 day + sweep | **decision A** |
| 11 | Abstract refinements phase 4: `a[p]` / `Bool[p]` sugar | design §7 | 1–2 days | 2, 5 |
| 12 | Abstract refinements over multi-argument callbacks | `2026-09-20-abstract-refinements-multi-arg-callbacks` | own design | 2, 5, 11 |
| — | Annotated type variables are not rigid | `2026-09-18-typecheck-annotated-tyvars-flexible` | ½ day–2 days | **decision B** |

Item 1 leads because it is the one entry that can make a *wrong* proof rather
than a missing one. Items 2 and 5 are the headline capability. Items 3, 4, 6, 7
are each a bounded precision fix with an existing probe row. Items 10 and the
typecheck item are blocked on decisions, stated at the end.

## Standing protocol (every item below inherits this)

Stated once so each item's steps stay short. From the element-flow and
set-refinement plans, which established it:

- One PR per item; a phase of a design is a PR of its own.
- Every new rule lands with a fixture that **goes RED without it**, recorded in
  the progress note. Every new assumption gets a control that must *skip*;
  every new obligation gets a REJECT fixture. Assert ledger triples
  (`proved, violated, skipped`), not exit codes — a skip and a proof both exit 0.
- `scripts/refine-oracle.sh` against a baseline built at **that PR's base**,
  under a private `HOME`; explain every moved line. A green oracle on a corpus
  with no violations proves only "nothing else moved", so it never substitutes
  for a REJECT witness.
- Anything touching a stdlib signature: the full sweep (`stdlib/`,
  `test/native/`, `test/stdlib/`, the ecosystem repos), because a new fact can
  turn a skip into a violation.
- `--refine-report stdlib/list.march` on a cold `.march/cas/artifacts-v2`
  against the CI ratchet (`baseline=` in `.github/workflows/ci.yml`, currently
  42; the file currently measures 40). Regenerate `test/refine_audit/*.baseline`
  only when it moves, and explain the movement.
- `test_refinecheck.exe -e` full, plus `run-tests.sh -q compiler stdlib_march`.
  z3 4.8.12 is CI's Ubuntu leg only; say so rather than claiming local coverage.
- `git mv` the todo to `specs/progress/` and add the CHANGELOG bullet in the
  same commit; when an element-flow item closes, remove its bullet from "What
  element refinements do not do" in **both** `specs/lang/refinement-types.md`
  and `docs/refinement-types.md`.

---

## 1. Tier 2's induction hypothesis trusts component names

**Todo:** element-flow follow-ups, item 5.

`structural_subvars` (`refine_encode.ml`) collects pattern binders by name over
a whole body; `refine_post.ml`'s Tier 2 consumer uses the set as is. The
element-return hypothesis already drops every parameter name and every name
bound more than once (`Refine_param.ambiguous_names`), after review found
`match zs do Cons(_, t) -> h(t, t)` nested inside `match xs do Cons(_, t)`.
Tier 2 has no such filter.

**Steps**

1. Probe first: construct the shadowing shape against a Tier 2 *relational*
   postcondition and record what it proves today. If it proves something false,
   that is a soundness bug and the item's priority changes — say so in the
   progress note before fixing.
2. Apply `ambiguous_names` at the Tier 2 consumer, or track components per
   lexical scope if the probe shows the name filter is too blunt.
3. Fixtures: the shadowing shape must not prove; the ordinary structural shape
   must keep proving (the regression set is the existing Tier 2 group).

**Risk:** the filter is blunt and may cost existing proofs. The oracle is the
detector; a lost stdlib proof blocks the item until it is understood.

---

## 2. Abstract refinements, phase 2: the filter rule

**Design:** `specs/2026-09-20-abstract-refinements-design.md` §2–§4.
**Closes:** element-flow item 6, and the "`filter` does not produce a
refinement it was not given" bullet.

Phase 1 (#543) decides which names are abstract and checks the signature.
Phase 2 makes them mean something.

**Steps**

1. **SMT arm and declaration** (§2a). `smt_of_r_marked` translates a declared
   abstract refinement applied to a term into `Smt.App ("$abs_<name>", [t])`;
   register the declaration where measure instances are registered so
   `resolve_sorts_exact` sees its argument sort. Unit: the preamble contains the
   `declare-fun`, and a predicate mentioning `p` is no longer an
   `unreflectable-predicate` skip.
2. **Definition side** (§4). `List.filter`'s own body proves its declared
   `List({a | p(_)})` from the branch fact plus the callback's codomain. Fixture
   n5 proves, n6 (a body returning `xs` unchanged) does not.
3. **Instantiation** (§3.1) from an inline lambda: `q` is the lambda's body,
   declined on capture or an untranslatable body.
4. **Substitution and the produced entry** (§3.2), feeding the existing
   `contenv`/`demand_flow` path; P1/P2 still gate the type variable.
5. **Discharge** (§3.3): one implication query over a fresh constant. Row n
   proves; row n2 (`y >= 0` against `_ > 0`) is a skip **with a witness**, not a
   violation.
6. **Conjunction** with an incoming element fact (§3.4), row n1.
7. **The cache hazard** (design §8): the VC cache key must include the
   instantiated `q`. Test: two calls, different lambdas, the second must not
   inherit the first's verdict. This test is the reason to write step 7 before
   annotating the stdlib, not after.
8. `List.filter`'s signature, then the sweep and the oracle.

**Exit:** rows n, n1, n2, n4, n5, n6 as the design's table states; audit
baselines move by exactly the new contract; the skip ratchet does not rise.

---

## 3. Non-linear arithmetic in an argument

**Todo:** `2026-09-18-refine-nonlinear-argument-reflection`.

`need_pos(y * y + 1)` is `unreflectable-subject`: the 2026-09-16 widening
admitted a product of non-literals in a *predicate*, not in an *argument*, so
the two translators disagree. A postcondition over the same expression proves.

**Steps**

1. Admit `Smt.Mul` in the argument reflector, with the `nonlinear-goal` skip
   reason for a goal the solver cannot settle.
2. `Witness.eval_operand` must evaluate it (it handles `*` already) so a
   refutation still renders its example.
3. Fixtures: `need_pos(y * y + 1)` proves; a genuinely refutable non-linear
   argument reports with a witness; a goal z3 cannot settle skips as
   `nonlinear-goal`, not silently.
4. Row **l** of the element-flow table (`sum_pos(List.map(ys, fn y -> y * y + 1))`)
   moves from skip to proved — it is listed there as landed-as-skip precisely
   because of this gap. Update that row's note.

---

## 4. Scalar demand on a single-element result

**Todo:** element-flow follow-ups, item 1.

`need_pos(Option.unwrap_or(o, 1))` and a `fold_left` result come through
`check_call`, not `check_elements`, so `demand_flow` never sees them.

**Steps**

1. Give `check_call` the same entry point: when an argument is a call whose
   declared return is a bare type variable with sources, run the §4.2 polarity
   walk and discharge each source against the scalar demand.
2. Reuse `sources_of` unchanged; only the demand's shape differs.
3. Fixtures: `Option.unwrap_or(o, 1)` with a refined `o` and a positive literal
   proves; with `0` as the default it is a skip with a witness; an opaque source
   skips.

---

## 5. Abstract refinements, phase 3

Named callables as definers (`is_pos` with a proved `{Bool | _ == (n > 0)}`
return, row n3), then `List.take_while` and `Option.filter` — **not**
`Map.filter` (§9.3). Each stdlib signature attempts a proof from its body and
falls back to `@[assume]` **with a runtime property witness** only if the proof
does not land, stating which in the progress note.

---

## 6. Relational element returns at a call site

**Todo:** element-flow follow-ups, item 4.

`: List({Int | _ < n})` is not a fact at a call site because `entry_is_closed`
requires predicates mentioning nothing but their own binder. Substitute the
actuals as `postcond_of` already does for a scalar relational return.

**Steps**: extend the entry with a substitution map; apply at
`declared_elem_return`; reject (skip) when an actual does not reflect. Fixtures:
a call whose actual is a literal proves; one whose actual is opaque skips; a
shadowed name must not substitute (the fact channel's shadow discipline — the
regression class this file's own history keeps finding).

---

## 7. A local `fn` with a container return

**Todo:** element-flow follow-ups, item 3. `ret_elem_demand` is suspended
inside a local `fn`, so its tails are checked by nothing and it lends nothing at
its call sites. Give it a demand and a gate like `visit_fn`/`gate_elem_returns`.
Fixtures: a local `fn` whose tails satisfy the demand lends its entry; one whose
tails do not is reported at the definition, not at the call.

---

## 8. Domain facts for multi-parameter lambdas

**Todo:** element-flow follow-ups, item 2. `lambda_domain_params` admits one
parameter. `fold_left`'s accumulator is also where a demand on `b` acts as an
*invariant* through its negative occurrence — a separate soundness argument,
and the reason this sits behind item 6.

**Steps**: extend the pass-site machinery to n-ary domains first (mechanical,
but it is "single-parameter throughout" today); then the accumulator invariant
as its own design note, with an explicit argument for why assuming the demand
on a negative occurrence is sound, or the decision not to.

---

## 9. `/` and `%` in predicates

**Todo:** `2026-09-16-refine-predicate-language-widening`.

The semantics are the work: March truncates toward zero, SMT-LIB's `div`/`mod`
are Euclidean, and `(-7) / 2` differs (`-3` vs `-4`). Rendering one as the other
is unsound in the false-positive direction.

**Steps (the todo's two increments)**

1. **Restricted fragment**: admit `/` and `%` only with a non-zero integer
   literal divisor and a provably non-negative dividend, where the two agree.
   The `@[measure]` totality gate already implements the literal-divisor half;
   `Division_safety.syntactic_nonzero` is reusable for the divisor.
2. **Fixtures**: `_ / 2 > 3` with a non-negative subject proves; a negative or
   unknown-sign dividend **skips** (the control that the restriction is real);
   the existing `_ / 2` fixture in `test_refinecheck.ml` is rewritten by this
   item, as the todo says any implementation must.
3. Only then consider the general encoding (`ite`-guarded rewriting of
   truncating division), as a separate item with its own soundness argument.

---

## 10. Stdlib wrapper contracts — **needs decision A**

**Todo:** `2026-09-16-refine-stdlib-wrapper-contracts` (P2).

20 of 42 `unconstrained-subject` skips are one shape: a wrapper forwards a value
to a contracted callee without declaring the contract itself. `Stats.median`
calls `percentile(xs, 50.0)` whose parameter is `{List(Float) | len(_) > 0}`;
the doc string already says "Panics on empty list"; the signature does not.

This is an **API decision, not an encoder change**. Declaring the contract makes
a currently-accepted call a compile error wherever the caller cannot prove
non-emptiness. That is the point — it is how `DataFrame.col_describe`'s panic
would have been caught — but it is a breaking change to public signatures.

**Steps once decided**

1. `--refine-suggest <fn>` proposes these; start from its output rather than by
   hand.
2. Do `Stats` as one unit (`median`, `quantile`, `quantiles`, `variance`), then
   `seq`/`flow`/`gen`'s `batch`-shaped wrappers, then `aho_corasick`'s 11
   internal helpers — whose contract is relational (`_ < pvec_length(nodes)`)
   and therefore pushes the obligation out to their own callers: check those can
   discharge it **before** committing to that shape.
3. Re-run the census (`specs/progress/2026-09-16-refine-skip-census.md`): the
   expectation is these skips become PROVED at the wrapper and reappear at
   whichever caller genuinely cannot establish the precondition.
4. Full sweep: every ecosystem call of `Stats.median` on an unprovable list
   becomes an error, and each one is either a real latent panic or a caller that
   needs a guard.

---

## 11–12. Abstract refinements, phases 4 and beyond

Phase 4 is the `a[p]` / `Bool[p]` sugar, desugaring to phase 1's forms, holding
the menhir conflict count at 9 (and fixing the stale "11" comment at
`parser.mly:1092-1093` while there). Item 12 is the multi-argument callback gap,
which needs predicates of arity > 1 and a decision about what a partial demand
means; its todo says explicitly not to start it before the one-argument rule has
landed through phase 3 and the stdlib has used it.

---

## Decisions needed

**A. `Stats` and friends: declare the contracts?** (item 10)
Declaring them turns latent runtime panics into compile errors and is the
feature working as intended; it also breaks callers that cannot prove
non-emptiness, in the stdlib's public API. Recommendation: **yes, for the whole
`Stats` surface at once**, in a release where it can be called out, with the
sweep's error list in the PR so the blast radius is visible before merging.

**B. Annotated type variables are not rigid.** (`2026-09-18-typecheck-annotated-tyvars-flexible`)
`fn bad(xs : List(a)) : List(a) do [0 - 5] end` typechecks and callers see
`List(Int)`. Three options from the todo: (a) make annotation variables rigid —
an error at the definition, breaking any code relying on the current behaviour;
(b) warn when an annotated variable unifies with a concrete type; (c) document
the current semantics. OCaml behaves the same way, which argues for (c) or (b).
Recommendation: **(b)**, with the measurement the todo asks for (how much of the
stdlib and the ecosystem relies on it) done first — if that number is zero or
near it, (a) becomes viable and is the honest reading of `a`.

Both are cheap to reverse on paper and expensive to reverse after a release,
which is why they are listed rather than assumed.
