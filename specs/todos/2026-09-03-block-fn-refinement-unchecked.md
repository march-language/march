# A block-level `fn`'s own parameter and return refinements are never checked

`[P3]` Filed 2026-09-03, found by the refinement coverage audit
(`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`, Task 2/3;
`lib/refinecheck/refine_audit.ml`'s `classify`).

## What is broken

A named function declared inside a block (`A.ELetFn`, e.g. a helper defined
with `fn inner(...)` inside another function's body) has both its parameter
refinements and its return refinement declared and typechecked, but neither
is ever checked. `check_fn_post_verdict` and `scope_add_param` /
`sig_of_clause` are reached only through `visit_decl`'s `A.DFn` and
`A.DImpl` arms; a local `A.ELetFn` never goes through `visit_decl` at all.

## Repro

```march
mod BlockFnHole do
  fn outer() : Int do
    fn inner(n : {Int | n > 0}) : {Int | _ > 0} do
      n
    end
    inner(0)     -- accepted in silence today, on both ends of `inner`'s contract
  end

  fn main() : Int do
    outer()
  end
end
```

```
$ march --check --refine-audit block_fn_hole.march
coverage audit: block_fn_hole.march:3:24: param `inner` #0: n > 0: this is a block-level function's own parameter: scope_add_param and sig_of_clause are reached only through visit_fn, which is called for A.DFn and A.DImpl, never for a local A.ELetFn, so no caller is ever obliged by it (the same reason this declaration form's Return site is Unenforced)
coverage audit: block_fn_hole.march:3:41: return of `inner`: _ > 0: this is a block-level function's return type: check_fn_post_verdict is reached only through visit_fn, which is called for A.DFn and A.DImpl, never for a local A.ELetFn, so no extractor is ever consulted for this position
```

`march --check` exits 0; `inner(0)` both violates `inner`'s own precondition
and (trivially, since `n` is returned unchanged) its postcondition, with no
complaint either way.

## Root cause

`lib/refinecheck/refine_check.ml`'s `visit_decl` calls `visit_fn` (the
function that wires a `fn`'s parameters and return into
`scope_add_param` / `sig_of_clause` / `check_fn_post_verdict`) only from the
`A.DFn` and `A.DImpl` arms. A block-level function is represented as
`A.ELetFn` inside an expression, which the declaration-level walk never
reaches; whatever expression-level walk does visit an `A.ELetFn`'s body
never calls `visit_fn` on it either.

## Where a fix would land

`lib/refinecheck/refine_check.ml`: the expression-level visitor needs an
`A.ELetFn` arm that calls the same `visit_fn` machinery `A.DFn` uses,
scoped to the enclosing function's environment rather than the module's.
This is likely coupled to whatever call-site-obligation machinery assumes a
callee is always a module-level declaration (a local function has no stable
top-level name to key an obligation or a per-callee cache on), so a full fix
may need a design decision about how local-function obligations key into
the existing obligation ledger, not just a call-site addition.

## Why it matters

Cross-reference `test/refine_audit/holes/local_fn.march`, one of the
fixtures in the audit's non-vacuity guard (`test/refine_audit/holes.baseline`).
Refactoring a top-level function (which IS enforced) into a nested helper
inside a bigger function silently drops all refinement checking on it, with
no diagnostic marking the change in coverage.
