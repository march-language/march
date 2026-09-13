# Unobliged parameter refinements are no longer assumed (plan phase 0)

Landed 2026-09-13. Phase 0 of
`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`. The three
todos this touches stay OPEN (their obligation side is still unenforced):

- `specs/todos/2026-09-03-lambda-param-refinement-unchecked.md`
- `specs/todos/2026-09-03-block-fn-refinement-unchecked.md`
- `specs/todos/2026-09-03-actor-state-and-handler-refinement-unchecked.md`

## What was wrong

Those todos describe each position as merely *unchecked*: a refinement on a
lambda's, a block-level `fn`'s, or an actor handler's parameter obliges no
caller. That was only half of it. `Refine_check.visit`'s `A.ELam` and
`A.ELetFn` arms and `visit_decl`'s `A.DActor` arm fed those same parameters
through `scope_add_param`, so the BODY assumed the predicate as a fact. With
nobody obliged and the body assuming, this exited 0 under `cap verified`:

```march
fn need(k : {Int | k > 0}) : Int do k end
fn main() : Int do
  let g = fn (n : {Int | n > 0}) -> need(n)
  g(0)
end
```

while the same program with `n : Int` exited 1 (`cannot verify precondition
\`k > 0\` on \`need\``). Same for `fn inner(n : {Int | n > 0}) : Int do
need(n) end  inner(0)` and for `on Inc(n : {Int | n > 0}) do ... need(n)`
sent `Inc(0 - 1)`. This is the assume-without-check the checker already
refuses for a non-adoptable `impl` method (`strip_param_refinements`).

## The fix

`Refine_scope.strip_param_refinement` / `strip_params_refinements` (a
`param`-level analogue of `strip_param_refinements`, which now shares the
helper) and three call sites in `refine_check.ml`: the `A.ELam` and
`A.ELetFn` arms of `visit`, and the handler loop in `visit_decl`'s
`A.DActor` arm, each build `scope` from the stripped params. `recenv` and
`cbenv` still see the declared types: a record sort or a callback signature
is a fact about the parameter's shape, not its value.

## Tests

`test/test_refinecheck.ml`, group `unobliged-assume`: three cases, each
pairing the refined program (must reject) with its unrefined control
(already rejects), so re-admitting the assumption shows as the refined half
going green while the control stays red. All three ran `[OK]` with z3 on
PATH, and the four scratch probes flipped exit 0 → exit 1 against the
rebuilt compiler.

## Fallout

See the commit message for the corpus/oracle sweep result.
