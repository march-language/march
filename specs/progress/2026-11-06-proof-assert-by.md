`[P2]` `assert P by do … end`: a scoped proof hint.

Quick win 1 of `2026-11-06-verification-ladder-roadmap`. Dafny's `assert P by { … }`.

## Now

`assert P` in a body is checked and then assumed for the rest of the walk, and lemma calls add
their theorems to every later obligation in the block. A long proof therefore carries every
helper fact into every later query: slower solving, and facts that make a later proof pass for
the wrong reason.

## Wanted

```march
assert sum_int(append(xs, ys)) == sum_int(xs) + sum_int(ys) by do
  List.sum_int_append(xs, ys)
  List.len_append(xs, ys)
end
```

The block's lemma calls and `let`s are in scope only while proving `P`; afterwards only `P` is
assumed. The block is erased like a lemma body.

## Done when

- Parser, desugar (the block is ghost, erased), and the walk: obligations inside the block see its
  facts; after it, only `P`.
- A test where a later obligation would pass only through a helper fact: with `assert … by` it is
  not proved (the fact did not leak); with a plain lemma call it is.
- `specs/lang/lemmas.md` documents it; tree-sitter grammar extended (CLAUDE.md rule).

## Completed 2026-11-07

Implemented `EAssertBy` through parsing, typing, desugaring, formatting, editor
traversal, proof checking, and erasure. `by` was already a keyword. Goal names
resolve outside the hints; rebinding a name used by the goal is rejected.
The checker validates pure, total hints using reflection's eligibility rules,
checks static assertions and the goal, and exports only the proved goal.
Hints ending in `if`/`match` prove the goal at each branch exit. Speculative
walks restore proof tables and context. Unproved blocks warn by default and
fail under `cap verified`; refuted assertions remain errors.

Erasure covers modules without lemma declarations and REPL declaration
processing, with interpreter/lowering fallbacks that never execute proofs.
Tree-sitter, AST JSON, coverage, call/name walkers, and generated language
and diagnostic documentation understand the new form.

Validation:

- 19 scoped-proof regression cases in `test/test_refine_lemma.ml`: isolation,
  goal export, nesting, branch exits, invalid hints, failed hypotheses, strict
  verification, custom `Eq`, reflection, and interpreter/JIT/native erasure.
- Parser/type/scope and formatter round-trip tests in `test/test_compiler.ml`.
- Native LLVM is byte-identical with the proof block removed.
- Diagnostic golden fixtures `invalid_lemma_2` and `lemma_unproved_2`.
- Tree-sitter corpus and repository grammar checks, documentation lint,
  and a 29-program cold/warm/cwd determinism check passed.
- Independent review found and verified fixes for hint equality totality,
  static assertions during reflection, and speculative proof-state isolation.

The full refinement suite passed: 2,479 tests in 208 groups. Baseline LLVM IR
is identical across 526 programs, and refinement diagnostics are identical
across 581 fixtures. The general quick suites passed except the broad LSP run, which was interrupted
during prolonged repository scans. Completed editor cases passed; full LSP
coverage is not claimed. Details and omitted checks are recorded in the implementation plan. The remainder of the verification ladder is open.
