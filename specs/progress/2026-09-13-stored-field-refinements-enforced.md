# Stored-field refinements are enforced (plan phase 4)

Landed 2026-09-13. Phase 4 of
`specs/plans/2026-09-13-refinement-enforcement-holes-plan.md`. Closes the
state half of the actor todo (now
`specs/progress/2026-09-13-actor-state-and-handler-refinement-enforced.md`)
and narrows `specs/todos/2026-09-01-nested-refinement-enforcement.md` to
refinements inside type arguments.

## What is enforced

A refined record field (`type Box = { v : {Int | _ > 0} }`), a refined
variant argument (`type W = W({Int | _ > 0})`), a refined actor state field
(`state { value : {Int | value >= 0} }`), and a refinement under a `linear`
wrapper.

**Obligation side.** Every CONSTRUCTION is a call to a synthesised
"constructor signature" (`Refine_scope.ctor_sig_of_fields` /
`collect_ctor_sigs`: one parameter per field in declaration order, refined
where the field is), discharged by the unchanged `check_call`:

- a record literal `{ v: 0 }` — typed by its field set, the unique record or
  actor state with exactly those fields; two types of one shape make it
  ambiguous and it is NOT obliged (fail closed);
- an update `{ r with v: e }` of a `recenv`-tracked variable — obliged for
  the updated fields only, the others reflected as `r.f` through the sort's
  selector;
- a constructor application `W(e)` (`visit`'s `ECon` arm, after the
  actor-message table);
- an actor's `init` and every handler tail that is a fresh literal, checked
  against the actor's own signature regardless of field-set ambiguity.

**Assumption side.** `Refine_scope.field_facts`: whenever a variable of a
refined record/actor type enters `recenv` (a function, lambda, local-fn or
handler parameter; a `let` with a declared record type or aliasing one; the
handler's `state`), each refined field's predicate is pushed as a path fact
over `x.field`, which the path translator reflects through the selector. The
subject is substituted under BOTH its spellings — the binder and the field's
own name used free (`value : {Int | value >= 0}` has binder `None`), which is
the bug the first cut had: the fact mentioned an unbound `value` and was
silently dropped, so the update `{ state with value: state.value + n }` came
back undecided while `_ >= 0` proved.

Actor state is therefore an inductive invariant: `init` and every result
establish it, the incoming `state` assumes it.

**Fail closed on a bare-name clash**, program-wide: two constructors, or a
constructor and an actor message, sharing a name withdraw the contract
(neither obliged nor assumed), the same rule as `collect_handler_sigs`.

## Supporting changes

- `Refine_encode.smt_sort_of_field` strips `TyRefine`/`TyLinear` before
  choosing a sort: a `{Int | _ > 0}` field was mapped to the opaque `Elem`
  sort, harmless while nothing read a refined field, wrong the moment one is
  reflected.
- `register_adt_names` / `register_field_sorts` register an actor's state as
  a one-constructor record under the actor's name.
- `Refine_scope.unlinear`: `refined_param_ty`, `refined_scope_ty` and
  `return_refine_sorted` strip a `linear` wrapper first; the audit's
  `walk_ty` no longer counts it as nesting.
- `Refine_audit.classify`: `Field` and `Variant_arg` report Enforced when
  `refined_param_ty` accepts the field's type. Hole fixtures `nested`,
  `variant_arg`, `linear_wrapper` and `actor` are retired; `type_arg` stays.

## Not done here

- Refinements inside a type ARGUMENT (`List({Int | _ > 0})`): container
  subtyping, still open in the nested todo.
- The witness gate (`witness.ml`'s `witness_safe_param`) keeps declining a
  witness for a function whose parameter type carries a nested refinement,
  now for the closed shapes as well; the coupling note in the nested todo
  asked for exactly this ordering (never lift the decline first).
- A `match` binder over a refined record does not enter `recenv`, so a field
  read through a pattern-bound name has no fact yet.

## Tests

`test/test_refinecheck.ml`, group `stored-field-contract` (7 cases): literal,
reader assumption, update (obliged for the updated field, may use the old
one), variant constructor, `linear` transparency, the ambiguous-shape
fail-closed control, and the actor invariant from init, result, and the
assumed incoming state.
