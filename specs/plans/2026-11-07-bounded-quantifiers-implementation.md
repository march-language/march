# Bounded Quantifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Implement bounded predicate quantifiers, checked list indexing, and witness obligations with a worked sorted-insertion proof.
**Architecture:** Extend predicate syntax with lexical binders and lower them into typed SMT binders. Keep quantifier-free rendering unchanged; check indexed-expression definedness separately from truth.
**Tech Stack:** OCaml, Menhir, tree-sitter, SMT-LIB, pinned Z3 4.16.0.
**Spec:** `specs/plans/2026-11-07-bounded-quantifiers-design.md` (approved).

## Global Constraints

- Half-open integer ranges; universal empty domains are true, existential empty domains false.
- Definedness applies to every domain member, including existential predicates.
- Unknown never proves a goal. Preserve warning-by-default and strict `cap verified`.
- No new trusted insertion/sorting axioms or public sorting API.
- Quantifier-free SMT byte-identical; median solver time within 5% in three cold and three warm paired runs.
- Explicitly stage files; use dune `--root .`; preserve the current worktree.

## Review Focus

- Shadowed binders and contract substitution cannot capture program variables (Task 2).
- Quantified formulas under negation cannot hide invalid indexing (Tasks 3–4).
- Unsupported element sorts cannot silently become Int (Task 4).
- Candidate witnesses must satisfy bounds and cannot leak into later proofs (Task 4).
- Queries without quantifiers cannot acquire global axioms or changed options (Tasks 1, 5).

### Task 1: Solver feasibility and baseline capture

**Files:** disposable `/tmp/march-stage-b-spike/`; `scripts/` capture utility if required; `lib/refine/solver.ml` only if a query capture hook is needed.
**Interfaces:** consume pinned Z3 and current compiler; produce reproducible SMT queries, expected verdicts, and baseline query hashes.
- [ ] Run list-datatype insertion induction, membership, nested binders, valid/invalid indexing and witness cases; compare explicit patterns with MBQI on/off, fresh and persistent sessions. Assert SAT/UNSAT/UNKNOWN outcomes, including a deliberately tiny resource limit.
- [ ] Capture current quantifier-free queries using a solver wrapper, verify a deliberate query perturbation changes the manifest, and retain baseline timings.
- [ ] Record encoding decisions and gate results before compiler changes.

### Task 2: Bounded syntax and lexical binder representation

**Files:** `lib/ast/ast.ml`, `lib/parser/parser.mly`, lexer/token-filter as required, `tree-sitter-march/grammar.js`, AST consumers, compiler parser tests.
**Interfaces:** produce a bounded quantified predicate carrying kind, binder, range/set domain, body and spans; provide binder-aware traversal/substitution.
- [ ] Add rejecting parser tests for the current compiler and positive AST expectations for range/set domains, precedence, nesting and legacy identifiers.
- [ ] Implement bounded syntax and update all AST consumers, rejecting quantifiers in runtime positions.
- [ ] Exercise capture avoidance across parameter substitution, nested shadowing and range bounds using outer names.
- [ ] Run compiler and tree-sitter tests; commit the coherent syntax/traversal change.

### Task 3: Universal ranges and checked indexing

**Files:** `lib/refine/smt.ml`, `lib/refinecheck/refine_scope.ml`, `lib/refinecheck/refine_encode.ml`, refinement tests.
**Interfaces:** typed quantified SMT terms with binder-aware free names; per-query list indexing declarations; definedness and truth obligations.
- [ ] Write failing checks for empty/reversed/negative ranges, adjacent sortedness, invalid index, guarded index, and negated invalid predicates.
- [ ] Implement deterministic rendering and patterns, exact sort resolution and range guards; add `nth` valid-index equations only to queries using it.
- [ ] Run focused soundness and positive controls, then refinement suite; commit.

### Task 4: Set domains and existential goals

**Files:** same encoder/checker modules, `lib/refinecheck/refine_check.ml`, diagnostics and refinement tests.
**Interfaces:** membership-guarded element binders; deterministic well-sorted witness candidates checked for domain and body, no escaping proof state.
- [ ] Add failing tests for elts/keys, mixed sorts, nested quantified predicates, missing/invalid/valid witnesses and strict capability errors.
- [ ] Implement scoped existential assumptions and checked candidate goals with actionable diagnostics.
- [ ] Test unknown/tiny resource limits and scope isolation; commit.

### Task 5: Worked induction proof and integration

**Files:** proof fixtures, `specs/lang/lemmas.md`, generated docs, TODO/progress files, CHANGELOG, diagnostic goldens.
**Interfaces:** verified integer insertion and insertion-sort fixtures using Task 2–4 syntax without new trust.
- [ ] Write and prove insertion and insertion-sort contracts; verify false variants fail.
- [ ] Compare baseline SMT manifests and three paired cold/warm timings; run affected suites, IR/refinement oracles and full required checks.
- [ ] Update documentation and feature status; review whole branch, resolve findings, and commit.
