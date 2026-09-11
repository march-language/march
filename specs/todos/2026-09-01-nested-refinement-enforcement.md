`[P3]` Nested refinements are parsed but never enforced (filed 2026-09-01)

A refinement below the outermost position of a type parses and typechecks
but is not checked anywhere:

```march
type Box = { v : {Int | _ > 0} }
fn f(b : Box) : Int do b.v end
fn main() : Int do f({ v: 0 }) end     -- accepted in silence today
```

The same holds for a refinement inside a type argument
(`List({Int | _ > 0})`) and under a `TyLinear` wrapper. Only a `TyRefine`
at the top of a declared parameter type is enforced at call sites.

**Coupled work in `lib/refinecheck/witness.ml`.** Three confirmation paths
execute a decoded model against the function and would otherwise report a
zero-filled value the declared type excludes (`but f({ v: 0 }) returns 0.`):
`confirm_post`, `confirm_enumerative` (return contracts, closed 2026-09-01,
see `specs/progress/2026-09-01-witness-nested-refinement-guard-return-contracts.md`)
and `confirm_precond_reachable` (call-site promotion). All three share one
gate, `witness_safe_param` / `refinement_free`, which DECLINES any parameter
carrying a refinement below the outermost position, so a function whose
parameter type nests a refinement gets no executed witness at all.

When nested enforcement lands, revisit that gate in the same change: either
teach `admissible` to check nested refinements against the decoded value (and
`zero_value` / `battery_values` to build values that satisfy them), then drop
the decline, or keep the decline and document that such functions never get
a witness. Do not lift the decline first; without it the enforcement change
turns a silent decline into a false-positive witness.

## Cross-reference

The refinement coverage audit (`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`)
reproduces this exact repro at `test/refine_audit/holes/nested.march`, one of
the fixtures in the audit's non-vacuity guard
(`test/refine_audit/holes.baseline`). `--refine-audit` classifies the `Box.v`
field as `Unenforced` for a related but distinct reason (no extractor exists
for a stored field at all, nested or not); see
`docs/refinement-types.md`/`specs/lang/refinement-types.md`'s "Coverage
audit" section.
