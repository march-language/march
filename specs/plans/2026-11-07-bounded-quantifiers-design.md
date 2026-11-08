# Bounded quantifiers: approved design

Status: approved; implementation in progress on `codex/verification-stage-b`. Focused controls and the integer insertion-sort fixture pass; full compatibility, performance, and integration validation remain pending.

## Intent and scope

Add bounded universal and existential predicates so a sorted-list insertion lemma can state and prove sortedness. This is Stage B's first feature in the verification ladder. Ghost state follows separately; external prover export, unbounded quantification, and proof scripts are outside this change.

Use the existing OCaml compiler, March predicate expressions, and Z3 bridge. Preserve warning-by-default and strict `cap verified` behavior. Unknown, unsupported, and timed-out queries must never export proof facts. The user approved implementation of this design.

## Surface and meaning

Allow `forall i in lo..hi, P` and `exists i in lo..hi, P` only in logical predicate positions. Ranges are integer, half-open: `lo <= i && i < hi`. If `hi <= lo`, universal predicates are true and existential predicates false. A negative bound is legal arithmetic; it does not make a negative list index valid. Nested quantifiers are permitted with lexical, capture-avoiding binders. Bounds are evaluated in the outer scope; the binder is in scope only in the body.

Also allow `forall x in elts(xs), P` and `forall k in keys(m), P`, and their existential forms. Infer binder sorts from the existing set measure. These forms range over membership, not over every value of the element sort. Reject unbounded forms and runtime quantifier expressions with source-located diagnostics.

Provide predicate-only `nth(xs, i)` at the list element sort. Its mathematical SMT function is total but unspecified outside the list; a March predicate may use it only after establishing `0 <= i && i < len(xs)`. Generate a definedness obligation under the applicable range and short-circuit guards. Definedness must hold for every member of a quantifier domain, for both universal and existential predicates, under short-circuit guards. Thus `exists i in 0..2, nth(xs, i) == 7` is rejected for a singleton list even if index zero is a successful witness. This keeps predicate definedness compositional under negation; existential candidate checks do not replace this domain-wide obligation. Never assume the guard merely because an access appears. Do not map an invalid index to zero or a fabricated element. Connect valid indices to Nil/Cons structure and existing length measures, independently of proof claims.

Sortedness is `forall i in 0..len(xs) - 1, nth(xs, i) <= nth(xs, i + 1)`. Parsing must give the range endpoint its full arithmetic expression and make the comma delimit the predicate body. Parenthesized forms permit use inside conjunctions. Keep `forall` and `exists` contextual if existing identifier compatibility permits it; document any unavoidable reservation before implementation.

## Proof rules and solver control

Encode universals as guarded implications and existentials as guarded conjunctions. Freshen every bound symbol, including substitution through reflected contracts and lemma applications. Universal goals can be checked through a fresh arbitrary counterexample constant by negation; existential assumptions use fresh scoped witnesses. These constants must not escape the obligation or enter shared proof-state caches as globally available facts.

For an existential goal, first try a deterministic bounded set of well-sorted terms already in scope or explicitly mentioned by successful proof assertions. Each candidate must satisfy both the bound and the body. Accept only a proved candidate obligation. If none succeeds, report that a witness is needed, including the instantiated bound and predicate for a proposed candidate when available. A suggested `assert P(k)` is insufficient unless membership/range validity is established too. Do not invent a new witness statement in this first design; a proof block can establish the candidate facts. Never silently turn an existential goal into a fresh unconstrained assumption.

For universal assumptions, prefer an actual indexing application containing the binder as the trigger. Set domains use membership/select terms containing the binder. Require patterns to cover every bound variable. For arithmetic-only ranges, where no admissible application exists, use direct arithmetic reasoning or report unsupported/unknown rather than emitting an invalid pattern. Trigger selection must be deterministic and tested with MBQI enabled and disabled; explicitly selected patterns do not by themselves guarantee completeness or stable timing. Do not manufacture arbitrary trigger functions that have no ground applications.

## Implementation boundaries

- `lib/ast/ast.ml`: predicate binder/domain representation with spans. Predicates currently use `expr`; there is no separate predicate AST to extend.
- `lib/parser/parser.mly`, lexer and tree-sitter: bounded syntax, precedence, contextual-keyword compatibility, and clear reject cases.
- `lib/refinecheck/refine_scope.ml`: binder-aware substitution, name collection, predicate printing, and scope checks.
- `lib/refinecheck/refine_encode.ml`: `classify_pred`, set-measure sort inference, `resolve_sorts_exact`, list measure instances, and per-query declarations. Existing `elts`/`keys` infrastructure supplies domains.
- `lib/refine/smt.ml`: binder-aware terms, rendering, free-symbol collection and traversal. The current term model has no quantifier nodes, although measure preambles already contain raw quantified axioms.
- Checker, reflection and termination consumers: preserve lexical scopes, definedness, and scratch-state isolation; audit every exhaustive AST/SMT visitor.
- Solver/cache integration: include quantified encoding changes in cache compatibility; emit no extra declarations, axioms or options for quantifier-free queries.

## Evidence so far and experiment gate

Disposable artifacts are in `/tmp/march-stage-b-spike/`, using local Z3 4.16.0. Forty-five fresh-process queries compare automatic, single-select, and two-select patterns over an array model. All three strategies agree: a contradictory adjacent pair under a sortedness assumption is unsatisfiable; the empty and negative-length model ranges satisfy universal sortedness vacuously; unconstrained two-element data can violate sortedness. End-to-end process times were 8.24–13.16 ms. These are basic encoding checks, not evidence for list induction, a trigger winner, or performance parity. Negative length is intentionally an arithmetic-domain test, not a permitted list length.

Before product changes, extend the disposable experiment to the actual list datatype and insertion induction step, membership, explicit witness success/failure, nested binders, invalid indexing, and deliberately under-budget/unknown queries. Compare fresh solver processes and repeated queries in a persistent push/pop session. The repository pins Z3 4.16.0 in `z3.version`, matching the local version; verify the pinned build as well as the installed local binary. Record solver options and distributions. If the insertion step cannot be made robust, revise the encoding before changing syntax.

## Acceptance and rollout

1. Grammar and scope tests: binder capture/shadowing, nested domains, empty/reversed/negative bounds, unbounded forms, runtime rejection, and all existing identifier uses.
2. Definedness and soundness tests: out-of-bounds `nth`, false sortedness, false membership, absent witnesses, mixed sorts, unknown results and verified-capability errors. Include positive controls for each rejection.
3. Prove integer sorted insertion by structural induction and provide a worked insertion-sort fixture whose result contract expresses sortedness. The TODO names `List.sort`, but the repository instead has `List.sort_by` and `Sort.sort`; this feature adds no new public sorting API and does not claim to verify the existing comparator-based merge sort. Update that TODO wording when implementing. Verification of the existing sort algorithms and comparator laws is separate follow-up work. Avoid introducing trusted assertions to meet this criterion.
4. Capture emitted SMT for the existing quantifier-free corpus before and after. Require byte-identical per-obligation queries, with a documented deterministic capture mechanism. IR equality alone cannot establish this.
5. Measure the existing refinement corpus on fixed solver/version/hardware, three paired cold runs and three paired warm runs. Proposed budget: median total solver time no more than 5% above baseline, with no new timeouts; repeat noisy measurements before attributing a regression.
6. Run relevant full suites and oracles, then full CI. Update the canonical language docs, generated pages, changelog, TODO/progress entries, and diagnostic goldens together.

Implementation proceeds in reviewable slices: solver experiment and SMT capture; binder representation and traversal; bounded universal ranges plus indexing; set domains; existential candidate obligations; sorted insertion proof and complete integration validation. A slice is not the completed feature until all acceptance criteria pass. Ghost-state implementation waits for this boundary and a separate design for erasure and runtime noninterference.
