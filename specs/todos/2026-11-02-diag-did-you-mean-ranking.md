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
