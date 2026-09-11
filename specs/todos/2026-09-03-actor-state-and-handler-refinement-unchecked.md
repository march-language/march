# Actor state and handler parameter refinements are never checked

`[P3]` Filed 2026-09-03, found by the refinement coverage audit
(`specs/plans/2026-09-03-refinement-coverage-audit-plan.md`, Task 2/3;
`lib/refinecheck/refine_audit.ml`'s `classify`).

## What is broken

An actor's `state { ... }` field can carry a declared refinement, and so can
an `on Msg(...)` handler's own parameter. Neither is ever checked. A state
field uses the same `Field` position a record type's field uses (there is
no extractor for a stored field at all, actor or otherwise); a handler
parameter has no dedicated extractor of its own either.

## Repro

```march
mod ActorHole do
  actor Counter do
    state { value : {Int | value >= 0} }
    init { value: 0 }

    on Increment(n : {Int | n > 0}) do
      { state with value: state.value + n }
    end
  end

  fn main() : Unit do
    let c = spawn(Counter)
    let _ = send(c, Increment(0 - 1))     -- accepted in silence today
    kill(c)
  end
end
```

```
$ march --check --refine-audit actor_hole.march
coverage audit: actor_hole.march:3:27: field `Counter.value`: value >= 0: a record (or actor-state) field's declared type is never re-examined once a value is constructed; the checker has no extractor for a stored field, only for a parameter, a return, or a let-binding
coverage audit: actor_hole.march:6:28: actor handler `Increment` param #0: n > 0: an actor handler parameter's declared type is never scope-checked: refined_param_ty is called only from a `fn`'s own parameter walk, never from an actor handler's
```

`march --check` exits 0; sending `Increment(-1)` drives `state.value` below
its own declared `value >= 0` invariant with no complaint.

## Root cause

Two independent gaps, both already named by `Refine_audit.classify`:

- The state field shares the generic `Field` position with a record's
  field: there is no extractor anywhere in the checker for a stored field,
  so a state update via `{ state with ... }` (or the initial `init { ... }`
  block) is never checked against the field's declared refinement.
- A handler's parameter never goes through `refined_param_ty`, which is
  only ever called from a `fn`'s own clause-parameter walk
  (`lib/refinecheck/refine_scope.ml`); `visit_decl`'s actor-handling arm
  never routes a handler's parameters through it.

## Where a fix would land

`lib/refinecheck/refine_check.ml`'s actor-handling code (wherever `A.on_handler`
/ the actor's `state` field types are visited) would need:
- an extractor for a state-field update, checked against the field's
  declared refinement at both `init` and every `{ state with ... }`
  reconstruction (this is the SAME underlying gap the generic record-field
  todo would need to close, since state fields reuse the record `Field`
  position -- fixing one is likely to fix or inform the other), and
- a call into `scope_add_param` / `refined_param_ty` for each handler's own
  parameter list, the same way a `fn`'s clause parameters are wired in.

## Why it matters

Cross-reference `test/refine_audit/holes/actor.march`, one of the fixtures
in the audit's non-vacuity guard (`test/refine_audit/holes.baseline`).
Actor state is exactly the kind of long-lived, mutated-in-place value a
refinement is meant to protect (an invariant that must hold across every
message), and today nothing enforces it.
