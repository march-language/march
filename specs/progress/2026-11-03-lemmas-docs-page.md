# Lemmas guide page (2026-11-03)

`specs/lang/lemmas.md` (rendered as `docs/lemmas.md`, `/docs/lemmas/`, nav 5.55 beside
Refinement Types), in the chapter-rewrite style of 2026-10-13 (plain introduction, **On this
page**, **Which tool do I need?**, **How it fits with the rest of March**, **See also**).

- Covers why lemmas (one unfolding versus induction, `cat(xs, Nil) == xs`), the rules L1-L5,
  induction, `assert` steps, decided steps and `@[reflect(fuel: N)]`, reading
  `lemma_unproved` and a refuted lemma, using lemmas (facts after a call, hypotheses and
  `lemma_unproved_call`, branch scope, pure arguments, `cap verified`), and the tooling on
  `main` (`forge test` lemma tests and the miscompile check, laws in `forge doc`,
  `forge search --law`, LSP rewrites, lemmas as a spec for agent-written code).
- The stdlib `List` lemmas (phase 3) and interface laws are marked as not on `main` yet.
- Every `march` block was checked with `march --check --refine-report-sites=all`, and each
  proved/skipped/error claim matches the report; the `lemma-test` output is a real run.
- Linked from `specs/lang/index.md`, `docs/index.md`, the refinement-types chapter (lemma
  section, fits-with table, See also) and the five lemma/reflect error pages.
- Found on the way: `specs/todos/2026-11-03-return-contract-ignores-block-facts.md`.
