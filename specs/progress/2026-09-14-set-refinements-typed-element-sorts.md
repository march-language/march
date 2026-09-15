# Set refinements strengthening, Phase 1: typed element sorts

Landed 2026-09-14. Design: `specs/2026-09-14-set-refinements-strengthening-design.md`;
plan: `specs/plans/set-refinements-strengthening-plan.md` (Phase 1, steps
1.0 to 1.6). The open item for Phases 2 to 4 stays in
`specs/todos/2026-09-14-set-refinements-strengthening.md`.

## What landed

- **1.0 Rejected queries fail the suite.** `Solver.malformed_count` and
  `malformed_messages` count every query z3 answers with `(error …)`;
  `MARCH_REFINE_Z3_ERRORS=<file>` appends the rejected query text, and the last
  group of `test_refinecheck.ml` (`z3-well-formed`) requires the count to be
  zero. `MARCH_REFINE_Z3_LOG=<file>` logs every query with its verdict, for
  comparing solver versions (piping z3's stdout through `tee` stalls the
  driver).
- **1.1 and 1.2 Sorts carry type arguments.** `Smt.SData of string * sort
  list`, `SParam` for a datatype's own parameter in field sorts,
  `ctor_field_sorts_poly`, and the typed `Smt.Ctor` term.
- **1.3 and 1.4 Instance-typed terms and per-instance measures.** A datatype
  term takes the instance its declared type gives. `Refine_encode.resolve_sorts`
  unifies every sort in a finished query, rewrites testers at an instance to
  `Smt.IsCtorAt`, and renames a measure applied at another instance to
  `m$<instance>`; `instance_measure_text` declares and axiomatises those
  instances from the same arm templates. New capabilities, each pinned by an
  accept and a reject case in `typed-instances`: a measure over `Tree(Int)`
  reading its `Int` payload, a set-valued measure over `Expr(Int)`, and a
  generic and an instance measure in one predicate.
- **Monomorphic instance declarations.** Every datatype instance is its own
  monomorphic z3 datatype (`M_Tree`, `M_Tree$Int`, same constructor names),
  never `(par …)`: z3 4.8.12, the CI solver, segfaults on a satisfiable query
  with a recursion axiom over a `par` datatype with two recursive fields, at
  any instance. 1.2 as first written had this latent crash; only the new
  ledgers exposed it, and only under 4.8.12. Module preambles declare closed
  instance sets (`datatype_decls`, `measure_preamble_sorts` now holds instance
  names too) and `query_instance_preamble` declares what a query adds.
- **1.5 The single-element-type rule.** `check_set_element_types` in
  `refine_check.ml` reports a set predicate whose operands have known,
  different element types, read from declared types only.
- **1.6** Deleted the dead `selector_field_sort`. The set-free fast path was
  measured and not applied (see
  `specs/progress/2026-09-14-set-free-vcs-pay-set-sort-resolution.md`); the
  `Int` default for caller values is filed as
  `specs/todos/2026-09-14-refine-caller-values-default-to-int.md`.

## Verification

- `scripts/refine-oracle.sh check` against a baseline recorded on the six-fix
  code: identical, 7028 report lines over 331 fixtures, no rejected query.
- Full `test_refinecheck.exe` on z3 4.16 and on z3 4.8.12 (Docker image of
  the CI version, run from an empty directory so the VC cache is cold): all
  cases pass on both, `z3-well-formed` included.

## Traps

- **4.16 is not a proxy for CI's 4.8.12.** Every typed-instances ledger passed
  locally and failed under 4.8.12 with the solver process dying mid-module,
  which the driver reports as undecided skips.
- **The VC cache hides a solver swap.** It lives under the cwd's
  `.march/cas/vc`, so a second run with a different `MARCH_Z3` answers from
  the first run's verdicts. Use an empty directory, and run groups that read
  `stdlib/` relative to cwd (`no-panic-by-proof`) from the worktree root after
  clearing the cache.
