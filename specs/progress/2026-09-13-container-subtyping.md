# Container subtyping: element refinements in `List` / `Option` type arguments

Landed 2026-09-13. Closes the last open shape of
`specs/todos/2026-09-01-nested-refinement-enforcement.md` (moved to
`specs/progress/`) for the two containers the checker's ADT registry
already knows; the rest is `specs/todos/2026-09-13-container-subtyping-other-containers.md`.

## Mechanism

A fourth fact channel, `contenv` (`Refine_scope`): variable name → (container,
element refinement in `refined_param_ty`'s shape), threaded through `visit`
beside `scope` / `recenv` / `cbenv` with the same shadow discipline.
`elem_refinement` extracts it from a declared type (`List({Int | p})`,
`Option({Int | p})`, through a `linear` wrapper).

**Obligation side** (`Refine_check.check_elements`), wherever a value flows
into a container-refined position — a call argument (`check_arg_elements`,
over the callee's `param_tys`; `entry_of_sig` keeps such a signature
resolvable even with no outermost refinement, as it does for an arrow
parameter), a function return (every tail), an annotated `let`, a record
field (`check_field_elements`, the companion of `check_ctor_fields`):

- a literal (`[a, b]` is a `Cons`/`Nil` chain; `Some(x)`): each element is
  checked by `check_call` against a one-parameter `elem_sig`;
- a variable in `contenv` with element refinement `q`: element subtyping,
  `q ⇒ p` for every element, as a check on the fresh symbolic element
  `$elem` carrying `q` — the new `Element_domain` subject, which shares
  `Callback_domain`'s definite-failure rule (a model IS a real element);
- anything else: a recorded skip (`--refine-report` counts it, `cap
  verified` escalates it).

**Assumption side**: a parameter, handler parameter, lambda/local-fn
parameter, or proved annotated `let` enters `contenv`; `match xs do Cons(h,
t) -> …` on a `contenv` variable gives `h` the element refinement as a
scope fact and `t` the same container entry; `Some(x)` gives `x` the fact.
A `let ys : List({Int | p}) = …` enters only when its element obligations
were PROVED, the rule `check_let_annotation` already applies to a scalar.

`Refine_audit.classify` reports a `Type_arg` site Enforced when
`elem_refinement` accepts the declared type, before the nesting rule; the
`type_arg` hole fixture is retired (only `arrow_domain` remains), and the
audit's pinned fixtures move to the two-layer shape.

## Tests

`test/test_refinecheck.ml`, group `container-subtyping` (6 cases): literal
element-wise, variable implication (weaker rejected with witness `0`,
stronger proved), `Cons`/`Some` element facts with an unrefined control,
`Option`, return + annotated `let`, and the recorded skip for an unrefined
source.
