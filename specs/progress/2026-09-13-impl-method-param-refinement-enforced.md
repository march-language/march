# A non-adoptable `impl` method's parameter refinement is never checked

`[P3]` Filed 2026-09-03, found by the refinement coverage audit
(`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`, Task 2/3;
`lib/refinecheck/refine_audit.ml`'s `classify`).

## What is broken

An `impl` method's declared parameter refinement is checked only when the
method's bare name is "adoptable": exactly one `impl` in the whole module
defines that name, and no top-level `fn` shares it
(`Refine_scope.adoptable_impl_methods`). When two `impl`s both define the
same method name (or a top-level `fn` collides with it), `visit_decl` strips
the parameter refinement from the body entirely, and no caller is ever
obliged by it -- silently, with no warning that this happened.

This is a real hole distinct from the audit's own conservatism: `classify`
reports EVERY `impl` method parameter as `Unenforced`, whether or not it is
actually adoptable in a given module, because adoptability is a
module-level fact a single site cannot determine. When the method genuinely
is adoptable, the checker still enforces it correctly; only the
non-adoptable case below is an actual gap.

## Repro

```march
mod ImplMethodHole do
  interface Indexable(a) do
    fn at : a -> Int -> Int
  end

  type Box = Box(Int)
  type Crate = Crate(Int)

  impl Indexable(Box) do
    fn at(b, i : {Int | i >= 0}) do
      match b do Box(v) -> v end
    end
  end

  impl Indexable(Crate) do
    fn at(c, i : {Int | i >= 0}) do
      match c do Crate(v) -> v end
    end
  end

  fn main() : Int do
    at(Crate(0), 0 - 1)     -- accepted in silence: `at` is not adoptable (two impls)
  end
end
```

```
$ march --check --refine-audit impl_method_hole.march
coverage audit: impl_method_hole.march:10:24: param `at` #1: i >= 0: this is an `impl` method's parameter, whose enforcement depends on a module-level fact a single site cannot determine: contract_is_enforced only assumes it when the method's bare name is adoptable (exactly one `impl` defines it and no top-level `fn` shares the name); when it is not, visit_decl strips the parameter refinement from the body and no caller is obliged. The audit reports Unenforced rather than guess at adoptability from this site alone
coverage audit: impl_method_hole.march:16:24: param `at` #1: i >= 0: this is an `impl` method's parameter, ...
```

`march --check` exits 0 on `at(Crate(0), 0 - 1)`, despite `at`'s own
declared precondition `i >= 0`.

## Root cause

`Refine_scope.adoptable_impl_methods` (`lib/refinecheck/refine_scope.ml`)
only adopts a method's contract when exactly one `impl` defines its bare
name and no top-level `fn` collides with it. `contract_is_enforced`
(`lib/refinecheck/refine_check.ml`) consults this table before wiring a
method's parameter refinement into scope; `visit_decl` strips the
refinement outright for a non-adoptable name, so `check_call` never even
sees a contract to check.

## Where a fix would land

`lib/refinecheck/refine_check.ml` and `refine_scope.ml`: enforcing a
non-adoptable method's contract requires knowing, at each call site, which
concrete `impl` the call resolves to (the same dispatch information
`lower.ml`'s defunctionalization eventually needs), so the refinement
checker would need its own type-directed dispatch resolution rather than
the current bare-name lookup. This is a bigger structural change than a
local fix; it is the reason `Refine_audit.classify` treats it as `Unenforced`
regardless of adoptability rather than trying to special-case it.

## Why it matters

Cross-reference `test/refine_audit/holes/impl_method.march`, one of the
fixtures in the audit's non-vacuity guard (`test/refine_audit/holes.baseline`).
Any interface with more than one implementation loses all parameter
enforcement on every method they share a name for, which is the common case
for any interface with more than one conforming type.

## Landed 2026-09-13 (plan phase 5)

`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`, phase 5. The
"type-directed dispatch resolution" the todo asked for is the same rule
compilation already applies (`Lower_state.resolve_iface_method`): the impl
for the FIRST argument's type.

- `Refine_check.check_module` takes `?type_map`, the typechecker's span →
  type table; `bin/main.ml` passes it at both call sites. The test harness's
  other helpers do not, and are honest about it (below).
- `Refine_scope.collect_impl_sigs` indexes every refined `impl` method's
  signature by bare method name, then by the impl's bare type name.
- `visit`'s `EApp` arm, when a call resolves to nothing by name and is not a
  local: `check_impl_dispatch` looks up the first argument's checked type,
  picks the single impl for that constructor, and files the ordinary
  `check_call` obligations. When that cannot be decided (no type recorded, a
  type variable, no or several matching impls) it records one SKIP per
  distinct candidate predicate — counted by `--refine-report`, escalated
  under `cap verified` — never silence.
- Method bodies stay walked with the refinement stripped unless the name is
  adoptable: obliging callers without letting the body assume is sound, and
  lifting the strip needs a proof that no generic call site escapes
  resolution, which is a separate change.

`Refine_audit.classify` reports `Impl_method_fn` parameters Enforced when
`refined_param_ty` accepts the type; the `impl_method` hole fixture is
retired. Tests: `test/test_refinecheck.ml`, group `impl-dispatch` (3 cases:
the violation through the receiver's type, the receiver selecting WHICH
impl's contract applies — `Crate` needing `i >= 10` while `Box` needs
`i >= 0` — and the recorded skip without a type map).
