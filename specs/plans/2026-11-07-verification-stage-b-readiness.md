# Verification ladder: Stage B readiness

**Status:** Bounded quantifiers approved and under implementation. Ghost state remains a separate subsequent stage. See `2026-11-07-bounded-quantifiers-design.md` and `2026-11-07-bounded-quantifiers-implementation.md`.

A1–A3 landed through PR #1189 (`specs/progress/2026-11-06-proof-hints.md`). PR #1192 preserves additional scoped-proof validation and regression coverage from the independently developed A1 implementation. Its final validation boundary should be the foundation for further proof features. The earlier A2 draft is superseded.

## Next objective

Start with bounded quantifiers (`specs/todos/2026-11-06-bounded-quantifiers.md`), followed by ghost state (`specs/todos/2026-11-06-ghost-code.md`). The acceptance examples are sorted-list insertion and a tree insertion proof against a ghost set. Keep external prover export and checked solver proofs separate.

## First work session

1. Read the two TODOs and the current predicate AST, sort mapping, measure registry, and SMT encoder. Identify the exact files and interfaces before writing an implementation plan.
2. Build a small disposable SMT experiment for indexed sortedness and membership. Define half-open versus inclusive range bounds explicitly, including empty and negative ranges. Establish the indexing measure's behavior outside the valid range.
3. Compare quantifier trigger choices on positive, false, and unknown insertion obligations. Every trigger must include its bound variable; compiler-selected triggers alone are not evidence of stable solving. Pin solver versions and cold/warm results.
4. Define existential witnesses and their diagnostic before committing syntax. Separate skolemised assumptions from witness obligations in goals.
5. Capture emitted SMT for the existing quantifier-free corpus and require byte-for-byte preservation. Measure solver time with a stated tolerance and repeated runs before claiming no regression.
6. Write the bounded-quantifier design and implementation plan from the successful experiment. Preserve warn-by-default, strict `cap verified`, source spans, and proof-state isolation.

## Ghost-state boundary to settle next

Ghost values may flow only into ghost positions, refinements, and erased lemma arguments. Include control dependence: a runtime branch must not depend on a ghost Bool. Plan ghost-parameter erasure through closures, interfaces, partial applications, and arity checks, plus byte-identical IR against proof-free controls. Do not implement ghost state until the bounded-quantifier model and one concrete tree proof establish the required surface.

## Integration checks

- Use the existing managed worktree and a fresh `codex/` branch from merged main.
- Inspect the verification roadmap before beginning; other concurrent work may have advanced a stage.
- Run focused tests first, then affected suites and oracles. The full CI run must be green before merge.
- A prior local LSP scan stalled while resolving deliberately missing imports in a populated checkout; preserve the test runner's prescribed working directory and rely on complete CI coverage rather than declaring interrupted tests passed.
