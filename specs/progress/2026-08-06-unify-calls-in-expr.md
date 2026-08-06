# Unify the three `calls_in_expr` copies

Task 1 of the per-function transitive capability closure plan
(`docs/superpowers/plans/2026-08-06-per-function-capability-closure.md`).

## What existed

Three separate walks over `Ast.expr` collecting direct function calls:

1. `lib/typecheck/typecheck.ml` (capability body-scan, feeding
   `check_module_needs`'s Check 1/1b/2 diagnostics and actor-handler cap
   recording) — returned `(string * Ast.span) list`.
2. `lib/typecheck/typecheck.ml`, a second `let rec calls_in_expr` further down
   the file — **byte-identical** to copy 1, and since OCaml shadowing is
   textual, it silently replaced copy 1 for every use site *after* its own
   definition (`check_no_panic_module`, `check_pure_module`,
   `check_deterministic_module`). Copy 1 had no doc-comment note that it was
   about to be shadowed.
3. `lib/refinecheck/panic_surface_by_proof.ml` — the same traversal but
   carrying a second span per call site (`name_span` for the diagnostic caret,
   `app_span` — the whole `EApp` node's span — because that's the key
   `Obligation.record` files preconditions under). This copy existed at all
   because `march_refinecheck` depends on `march_typecheck`, not the reverse,
   so it could not simply call either typechecker copy.

A `KEEP IN SYNC` doc comment was added above copy 1 in PR #199, instructing
future editors to update `panic_surface_by_proof.ml` in lockstep. It was on
the **wrong copy**: copy 1 was already dead by shadowing, so the comment sat
above code nothing else in the file actually used, while copy 2 — the one
`panic_surface_by_proof.ml` structurally mirrored — carried no note at all.

The drift between the three was fail-**open**: an `Ast.expr` constructor added
to one walk and not another would let a call that can panic through `cap
no_panic` silently.

## What changed

- New `lib/ast/calls.ml` (`March_ast.Calls`): the single walker, as
  `calls_in_expr : (name * name_span * app_span) list -> expr -> ... list`,
  plus `names_and_name_spans : expr -> (name * name_span) list`, a projection
  matching the pair shape the typechecker's two former copies returned.
  `march_ast` has no dependencies and both `march_typecheck` and
  `march_refinecheck` already depend on it, resolving the dependency-direction
  problem that forced copy 3 to exist as a separate traversal in the first
  place.
- Both typechecker copies deleted, including the now-obsolete `KEEP IN SYNC`
  comment (unification makes the instruction structural rather than needed).
  Call sites now call `March_ast.Calls.names_and_name_spans`, except the one
  site in `check_no_panic_module` that threads an accumulator across a
  function's multiple clauses — that site threads
  `March_ast.Calls.calls_in_expr`'s triple accumulator across clauses (to
  preserve the exact prior consing order across clauses) and projects to
  pairs only once, after the fold, rather than per-clause.
- `panic_surface_by_proof.ml`'s copy deleted; its one call site (which already
  threaded an accumulator across clauses in the triple form) now calls
  `March_ast.Calls.calls_in_expr` directly — no projection needed since the
  types already matched.
- New `test/test_ast_calls.ml` — the walker's first direct test, covering a
  bare call, a qualified `Mod.fn` call, descent into match arms/if branches,
  descent into a lambda body, and that `name_span`/`app_span` are genuinely
  distinct for a call with arguments.

### Test correction versus the task brief

The brief's test parsed source with the raw parser only (no desugar) before
walking it. That failed two of the five cases: the raw parser represents an
uppercase module reference like `List` in `List.map(...)` as `ECon("List", [],
_)`, not `EVar`, so the walker's qualified-call arm
(`EField(EVar mod_name, fn_name, _)`) never matches un-desugared input. Every
real caller of this walker (both former typechecker copies, the proof-based
pass) only ever sees **desugared** ASTs — `bin/main.ml` runs
`Desugar.desugar_module` before any of the three `check_module`-family passes
— and `desugar_expr`'s `EField` case is exactly what flattens `List.map(...)`
from `EField(ECon "List", "map", _)` down to a plain `EVar "List.map"`,
consumed by the walker's *first* match arm rather than its qualified one. The
test's `parse` helper now desugars after parsing, matching what the walker
actually ever sees in production; the qualified-call test case passes as
intended. Confirmed with a throwaway probe: raw-parsed `List.map(xs, ...)`
prints as `EApp(EField(ECon "List", "map"), ...)`.

## Verification

- TDD: RED (`dune build --root . test/test_ast_calls.exe`) failed to compile
  with `Error: Unbound module "March_ast.Calls"` before `lib/ast/calls.ml`
  existed. GREEN after creating it and correcting the test's `parse` helper
  to desugar: all 5 cases pass.
- `grep -c "^let rec calls_in_expr" lib/typecheck/typecheck.ml
  lib/refinecheck/panic_surface_by_proof.ml` → `0` and `0`.
- Full corpus sweep (`stdlib/*.march test/native/*.march bench/*.march`
  through `--check`), base commit (`b80aa6d0`) vs. this change: **byte-
  identical** diagnostic output, 6606 lines each side, empty diff.
- Positive control: temporarily replaced the `Ast.EIf` arm in
  `lib/ast/calls.ml` with `| Ast.EIf _ -> acc`, rebuilt, re-ran the same
  sweep — diff against the base went **non-empty** (127 lines). Restored the
  arm, rebuilt, re-ran — diff returned to **empty** (0 lines). This confirms
  the sweep instrument can actually detect a regression, not just that the
  before/after run happened to match.
- Suites: `test_ast_calls` (5/5 pass), `run_compiler` (760/760 pass, 183s),
  `test_refinecheck` (full suite, ~215s) all green.
