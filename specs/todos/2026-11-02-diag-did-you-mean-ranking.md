`[P3]` Diagnostics: suggestions use spelling only. Make them type-, refinement- and capability-directed:
(1) rank spelling candidates by trial unification against the position's expected type (`send(a, Pokee(1))`
ranks `Post`/`Pong` above `Poke`, the only message actor `A` takes); (2) when spelling finds nothing, search
in-scope functions by call shape (`List.fodl(xs, 0, …)` → `fold_left`/`fold_right`), argument permutations, and
`S -> T` conversions in place of hard-coded hints; (3) after a precondition failure suggest total twins
(`head` → `head_opt`), solver-checked guards over the real argument, and rank candidates by provability and by
capabilities in scope. Needs a rollback-able trial unify in `typecheck_unify.ml`. specs/plans/2026-11-02-diagnostics-depth-plan.md §X8.

**Status (2026-11-03):** tier 1 (rank spelling candidates by type fit) landed, by read-only
structural comparison rather than a trial unify; see
`specs/progress/2026-11-03-diag-did-you-mean-tier1.md`. Tiers 2 (type-directed search,
argument permutations, conversions) and 3 (total twins, solver-checked guards, provability and
capability ranking) remain open; tier 2 is where the rollback-able trial unify is still needed.

**Status (2026-11-05):** tier 2 landed (search by call shape, argument permutations, exact
`S -> T` conversions, on a trial unification over a private substitution that never writes
the live union-find), and so did tier 3 item 1, total twins (`head` → `head_opt`); see
`specs/progress/2026-11-05-diag-did-you-mean-tier2.md`. Still open:
- tier 3 item 2, solver-checked guards: the instantiated guard is already printed
  (`guard the call (e.g. if len(xs) > 0 do …)`), and a closed argument already says it can
  never satisfy it; what is missing is the solver check that the guard is satisfiable under
  the path facts (a dead guard otherwise);
- tier 3 items 3 and 4, ranking spelling and type candidates by provability of their
  precondition at the call and by the capabilities in scope;
- conversions to `Option(T)` / `Result(T, _)` when the position needs one (a parse);
- `@[total_twin(f)]` for pairs the `_opt` naming convention misses.
