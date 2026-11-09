`[P2]` Proof-dependency diagnostics: vacuity warnings, unused hypotheses, "facts used" on hover, and the facts in scope at a failure.

Source: `specs/2026-11-08-auto-active-verifier-lessons.md` (research survey, 2026-11-08), recommendation 6.

## Why

Every usability study surveyed puts the same request first: show what the verifier knew. These
are Dafny OOPSLA 2025 (14 experts), Liquid Haskell PLDI 2025 (19 developers), an ETH survey (29
practitioners) and MSR telemetry on F*/Verus experts. One Dafny user rebuilt that view by hand
with 50 assertions. Dafny 4.4–4.6 ships unsat-core-based warnings: a proof that succeeds because
its assumptions contradict each other (vacuous), assumptions no proof used, and code no
specification constrained. They cost about 30% more verification time, and the authors found
them useful on every large code base they tried. They also catch weak specifications written by
people or agents.

## Now

Reflection's stage-2 proofs already record their unsat core (`uses:`, `lib/refine/refine.ml`).
Nothing reports vacuity: a contradictory hypothesis set still yields `proved`
(`lib/refine/refine.ml`, `ground_verified` notes this is deliberate for unreachable call sites).

## Wanted

- `--warn-vacuous`: for each proved obligation, check whether the hypotheses alone are
  unsatisfiable. If so, warn "proved only because the assumptions contradict each other", with
  the contradicting pair from the core. An unreachable call site should be reported as such
  rather than as a proof.
- An "unused hypothesis" hint for a function's refined parameters that no obligation's core used.
- In the LSP, hovering over a proved obligation shows the facts its core used, and a failed one
  shows the facts in scope, in source syntax.

## Done when

Each warning has accept/reject fixtures and an `--explain` page, the cost is measured on the
stdlib sweep, and the warnings are off by default until that cost is known.
