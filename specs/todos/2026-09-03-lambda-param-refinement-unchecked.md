# A lambda's own parameter refinement is never checked

`[P3]` Filed 2026-09-03, found by the refinement coverage audit
(`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`, Task 2/3;
`lib/refinecheck/refine_audit.ml`'s `classify`).

## What is broken

A declared parameter refinement on an anonymous lambda (`A.ELam`) is parsed
and typechecked but never enforced. No call through the lambda, ever, is
obliged by it.

## Repro

```march
mod LambdaParamHole do
  fn apply(f : Int -> Int, x : Int) : Int do
    f(x)
  end

  fn main() : Int do
    let g = fn (n : {Int | n > 0}) -> n
    apply(g, 0)     -- accepted in silence today
  end
end
```

```
$ march --check --refine-audit lambda_hole.march
coverage audit: lambda_hole.march:7:27: lambda param #0: n > 0: an A.ELam parameter is never scope-checked: scope_add_param and sig_of_clause both consume an A.fn_clause's params, which a lambda does not have, so no call through this lambda is ever obliged by its own parameter's refinement
```

`march --check` exits 0; `apply(g, 0)` runs `g(0)` with no complaint despite
`g`'s own declared contract `n > 0`.

## Root cause

`scope_add_param` and `sig_of_clause` (`lib/refinecheck/refine_scope.ml`)
both consume an `A.fn_clause`'s parameter list, which only a `fn` produces.
An `A.ELam`'s parameters are never routed through either function, so
`refined_param_ty` accepting the lambda's declared parameter type is
irrelevant: nothing downstream ever asks about it.

## Where a fix would land

`lib/refinecheck/refine_check.ml` (or wherever `A.ELam` is visited during
scope construction) would need to register the lambda's own declared
parameter types the same way a `fn`'s clause does, so that a call through a
value of the resulting closure type files an obligation. This likely
interacts with how a closure's type is tracked at its call sites (the
refinement would need to travel with the closure value, not just the
lexical scope of the lambda's own body), which is a larger change than a
local fix to `scope_add_param` alone.

## Why it matters

Cross-reference `test/refine_audit/holes/lambda_param.march`, one of the
fixtures in the audit's non-vacuity guard (`test/refine_audit/holes.baseline`).
A user writing a locally-scoped helper as a lambda rather than a `fn` loses
all enforcement of any refinement they write on its parameters, with no
diagnostic warning them this happened.
