# Verification Ladder: Initial Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking. This is an initial planning proposal, not authorization to implement every roadmap item.

**Goal:** Make existing March proofs easier to compose safely, then use bounded quantifiers and ghost state to verify real data structures.

**Architecture:** Preserve the current refinement checker and lemma erasure pipeline. Introduce a scoped proof operation that exports only a proved conclusion; build calculation chains and local unfolding controls on that boundary. Keep external proof checking and Lean export as separately scoped projects.

**Tech Stack:** OCaml, Menhir/ocamllex, Z3, March, tree-sitter, Alcotest.

**Spec:** `specs/todos/2026-11-06-verification-ladder-roadmap.md` and its thirteen linked TODOs. The first implementation slice is `2026-11-06-proof-assert-by.md`.

## Global constraints

- Preserve HM inference; full dependent function types are out of scope.
- Preserve warning-by-default and strict `cap verified` behavior. Failed erased proofs export no facts, even when compilation continues.
- Proof hints must be pure and terminating; erasing them cannot remove observable program behavior.
- Keep ordinary runtime `assert` semantics unchanged.
- Edit language documentation in `specs/lang/`, then regenerate with `scripts/gen-lang-docs.py`.
- Update tree-sitter with parser/lexer changes; follow the exception procedure in `CLAUDE.md` only if necessary.
- Move a TODO to `specs/progress/` only when its acceptance criteria are met. The umbrella roadmap stays open until items 1–9 land.
- Run Dune with `--root .` in this worktree; prefer repository test scripts.

## Scope and delivery order

| Stage | Roadmap items | Exit criterion |
|---|---|---|
| A1 | 1: scoped assertions | A helper proves a goal without proving an unrelated later obligation; erased code has no runtime effect. |
| A2 | 2: calculation chains | Each step is independently checked and located; only a fully proved chain exports its conclusion. |
| A3 | 4: reveal and local fuel | Valid hidden definitions and extra fuel are usable within the designated scope, with defaults restored afterwards. |
| B | 5 and 6: bounded quantifiers and ghost code | Sorted insertion proof plus a tree proof using a ghost set; existing quantifier-free obligations retain their encoding. |
| C | 11: Map/Set contracts | Remove assumptions one contract at a time: Set membership/insertion, deletion, then Map. |
| Separate tracks | 8 and 9: Lean export, checked solver proofs | First prove feasibility on a small representative corpus, then write separate implementation plans. |
| Demand-driven | 3 and 7: indexed aliases, two-state specs | A concrete vector/actor use case determines the required surface and semantics. |
| Later | 10, 12, 13 | Unbounded quantifiers after bounded forms; capability specs after two-state/model work; scripts after repeated proof patterns appear. |

This order follows the roadmap. Recommendation: finish A1 as one reviewable feature before committing to A2/A3 internals. No calendar estimates until A1 establishes the cost of threading proof syntax through the compiler.

## Findings from the current checkout

- `lib/ast/ast.ml` represents plain assertions as `EAssert of expr * span`.
- `lib/parser/parser.mly` constructs assertions in more than one grammar position; both need coverage.
- The block walk in `lib/refinecheck/refine_check.ml` proves assertions in lemma mode before adding them to the path. Ordinary assertions are added as facts because they execute at runtime. The new erased form must always use the former rule.
- `lib/desugar/lemma_erase.ml` runs after checking; the refinement checker needs the original proof expressions. “Desugar to erased code” cannot mean deleting hints before verification.
- `lib/refinecheck/refine_reflect.ml` excludes `opaque`, `assume`, and `trusted` definitions from reflection eligibility. Reveal must not simply bypass that validation.
- Reflection templates carry fuel, currently defaulting to 2, with attribute values accepted from 1 through 8. Local fuel must not leak through shared templates or cache state.

## Review focus

1. Failed, unknown, or timed-out proof scopes must not export their goal (A1).
2. Hint-local names, shadowing, branch facts, and nested scopes must not change outer name resolution or assumptions (A1).
3. Effects, nontermination, and non-reflectable calls in erased hints must be rejected (A1).
4. A wrong middle calculation step must not allow a chain conclusion to be admitted (A2).
5. Hidden-definition/fuel settings must restore correctly after nested scopes, failed checks, and subsequent files in the same process (A3).

## A1: scoped assertions — first implementation slice

### Proposed semantics

`assert P by do hints end` has type Unit. Resolve `P` in the enclosing environment; hint-local bindings cannot capture names in it. Hints see enclosing facts, and their facts are available while proving P. Afterwards, only P may be added to the enclosing facts, and only if the proof and required hint obligations succeed. Hint locals never escape. The entire construct is erased after checking.

Use a dedicated AST constructor, proposed `EAssertBy of expr * expr * span`, rather than an ordinary runtime assertion plus a block. Preserve it through desugaring and checking. This is a proposed implementation choice, not an existing API.

### Task 1: surface, typing, and preservation

**Files:** `lib/ast/ast.ml`, `lib/parser/parser.mly`, `lib/lexer/lexer.mll`, `lib/desugar/desugar.ml`, `lib/format/format.ml`, `lib/typecheck/`, `tree-sitter-march/grammar.js`; compiler tests in `test/test_compiler.ml`.

**Interface:** parser produces `EAssertBy(goal, hints, span)`; downstream checking receives the intact node. Goal is Bool, result is Unit, and hint bindings have a nested lexical scope.

- [x] Add parse/type/format cases for a multiline hint, nested scopes, a non-Bool goal, and a hint-local name referenced after the block. Assert successful round trips for valid cases and diagnostics for invalid cases.
- [x] Confirm the new focused compiler surface tests initially fail at `by` (completed before implementation).
- [x] Add the AST node and syntax; inventory every expression visitor with `rg -n 'EAssert' lib` and update traversal/preservation deliberately. Keep buildable coverage of all consumers within this task.
- [x] Extend tree-sitter and formatter support, including identifier compatibility for any new contextual words.
- [x] Build the compiler and all affected consumers; run compiler and tree-sitter checks. Keep surface and proof enforcement in one atomic feature commit.

### Task 2: scoped proof admission and erasure

**Files:** `lib/refinecheck/refine_check.ml`, supporting scope/encoding modules as required, `lib/desugar/lemma_erase.ml`; tests in `test/test_refine_lemma.ml` and interpreter/codegen suites.

**Interface:** the checker consumes `EAssertBy`; only its proved goal is returned to the outer fact path. The erasure pass replaces it with Unit at the original span. Use existing lemma proof diagnostics and purity/termination rules where applicable.

- [x] Add paired tests: a helper establishes P and unrelated Q; scoped hints admit P but leave Q unproved, while a plain helper call admits Q. Test inside both an ordinary function and a lemma.
- [x] Add negative cases for false/unknown goals, failed helper preconditions, hint-local shadowing of goal variables, nested scopes, sibling branches, effectful calls, and nonterminating hints. None may manufacture a later proof.
- [x] Establish failing focused proof tests, including the review regressions; ensure Z3 is present through the test script prerequisite checks.
- [x] Implement a nested proof walk with lexical isolation and success-gated goal export. Audit all state channels used by the walk, not only the path-fact list. Do not use ordinary assertion fallback behavior.
- [x] Extend erasure after checking. Add interpreted/compiled parity and IR-erasure comparisons against the same program with proof blocks removed, including when proofs are unverified outside `cap verified`.
- [x] Run full refinement, quick general regressions, and IR/refinement baseline comparisons. Review diagnostics and erasure results. See the explicit LSP limitation below; affected checks ran as separate commands to avoid duplicate suites.

### Task 3: user-facing acceptance

**Files:** `specs/lang/lemmas.md`, generated `docs/lemmas.md`, `CHANGELOG.md`, the A1 TODO/progress entry, error/report fixtures where new output is emitted.

- [x] Document lexical scope, proof failure, erased execution, and the difference from ordinary assert, with a worked List proof.
- [x] Add diagnostic/report fixtures establishing that failure points to the goal or failing hint and that `cap verified` rejects the unproved construct.
- [x] Run `scripts/gen-lang-docs.py`, `scripts/check-docs.sh`, and affected checks. Move only the scoped-assertion TODO to progress after its acceptance tests pass.
- [x] Package the independently reviewed feature with its documentation and progress record in one commit after final verification.

## A2 and A3: design boundaries before detailed task plans

**Calc:** lower steps to the A1 scope operation while retaining original spans and step numbers. Specify a relation-composition table before implementation: equality can combine with order; strictness propagates for `<`/`<=`; implication operates on Bool; reject incompatible mixtures. Give each step enclosing facts plus its own hints; export only the composed endpoint relation after every step succeeds. Tests must cover failed middle steps, mixed relations, hint leakage, type errors, and per-step report rows. Relevant files include the A1 surface/checker files and `test/test_refine_lemma.ml`.

**Reveal/fuel:** distinguish validated-but-hidden templates from ineligible definitions. Require the normal totality, purity, termination, and supported-logic checks before revealing a body; never reveal trusted assumptions as proofs. Use an explicit scoped configuration rather than mutating shared templates. Decide a local fuel bound consistently with the current 1–8 attribute range. Test nested overrides, restoration after errors, qualified/shadowed names, invalid targets, and warm/cold cache parity. Relevant code is `lib/refinecheck/refine_reflect.ml`, the proof walker, and `test/test_refine_reflect.ml`.

## Follow-on work that needs its own design

- **Bounded quantifiers:** settle range endpoint semantics, indexing on partial/out-of-range access, empty bounds, binder sorts, triggers that actually mention quantified variables, and existential witnesses. Start with an indexing/trigger experiment before promising sorted insertion. Compiler-selected triggers alone do not guarantee predictable solving.
- **Ghost code:** define noninterference for control flow as well as values, then ghost-parameter arity through closures, interfaces, and erasure. A ghost value must never influence runtime branch selection.
- **Lean export:** specify the exact exported logic subset, transitive dependency digest, proof-artifact validation, and invalidation policy. A digest of a statement alone is not evidence that Lean checked a proof of it.
- **Checked solver proofs:** verify actual solver/exporter/checker compatibility and coverage before selecting tools. The TODO's Alethe path is a feasibility hypothesis until exercised. Independent checking validates the encoded VC, not its correspondence to March semantics.
- **Capability contracts:** first connect two-state specs to runtime/model conformance for one capability, as required by the TODO. Avoid broad effect specifications before that evidence exists.

## Planning status

A1 is implemented and independently reviewed. All 19 focused proof tests, surface/type/format tests, diagnostic fixtures, grammar checks, and determinism checks pass. The full refinement suite passed (2,479 tests in 208 groups), as did the compiler and interpreter quick suites. Baseline comparisons found identical LLVM IR across 526 programs and identical refinement diagnostics across 581 fixtures (8,996 report lines). Quick codegen, stdlib, March stdlib, JIT, UTF-16, JSON-RPC, incremental, query CLI, diagnostic golden, and test-report suites also passed. The broad LSP suite was interrupted as described below. A2/A3 and later stages have not been implemented.

## A1 implementation decisions and validation scope

- Deliver syntax, checking, erasure, documentation, and regression coverage in one atomic commit.
- Hint bindings that shadow names used in the goal are rejected with a rename diagnostic. This conservatively preserves the enclosing meaning of the goal.
- Tail `if`/`match` branches each receive a static goal obligation; every hint and goal obligation must pass before the goal escapes.
- Speculative checking snapshots proof state. Proof validation also runs with reflection disabled.
- General regressions use the repository's quick mode; refinement runs in full. Explicit native/interpreter/JIT erasure tests cover the new construct.
- Baseline comparisons cover emitted IR and refinement. The optional type-inference oracle was omitted: this adds a focused Bool/Unit rule, without refactoring inference.
- Grammar, documentation, snapshots, and determinism checks passed. Focused forge topology checks passed; the broader forge alias was interrupted in an unrelated upgrade test and is not claimed as passing.

### Final verification limitation

The broad LSP suite was interrupted during the import-organizing test after prolonged repository-wide scans for missing imports. A process sample showed `Resolver.read_file`, `file_declares`, and `scan`; no assertion failure was reported. A separate run of the remaining groups passed further TIR, allocation-contract, and code-lens checks, then encountered another long scan in HTML folding tests and was also interrupted. Neither run is claimed as a full LSP pass. The general runner therefore exited nonzero solely because the LSP process received SIGTERM; all twelve other selected suites passed.

Rendered diagnostic goldens retain the renderer's trailing blank lines, consistent with existing fixtures. Diff whitespace checks otherwise pass. No push or merge is part of A1 delivery.
