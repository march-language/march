`[P2]` Minimal solver context: send each VC only the measures, reflected definitions and lemmas it can use.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 3.

## Why

Irrelevant context is the main cause of instability. In typical Dafny/F* queries 96–99% of
the assertions are unneeded, and they account for 78% of observed instability. SHAKE's
relevance pruning (3–10x smaller queries) improved stability by 29% on z3 and 41% on cvc5.
Verus is minimal by default: on its IronKV port, queries were 95% smaller and verification
was 10x faster.

## Wanted

- Measure first: for the stdlib `cap verified` modules and the refine-oracle corpus, count the
  axioms per VC and how many the unsat core actually uses (z3 `:named` / core extraction on a
  sample).
- Then prune per VC: start from the goal and hypotheses' symbols, take the transitive closure
  over the measure/reflection/lemma axioms that mention them, with a depth bound. Fall back to
  the full context when the pruned query fails, and report the fallback so it shows up in the
  stability report (`2026-11-08-verifier-stability-mode`).
- Keep emitted SMT byte-identical for queries whose pruned and full contexts are equal, so the
  refine oracle stays meaningful.

## Done when

Pruning is on by default with a switch to turn it off. On the oracle corpus there is no verdict
change, or every change is explained. Median query size and check time drop, measured cold and
warm, and the stability sweep shows no regressions.
