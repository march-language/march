# Field refinements of an anonymous-record parameter are assumed and obliged (2026-11-04)

Gap G5 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` (phase A). The
design's P3 probe found it on a `migrate_state`:
`fn tally_migrate_state(old : { count : {Int | _ >= 0} })` didn't give its body
`old.count >= 0`.

## Before

For a parameter like `fn f(r : { v : {Int | _ > 0} })`:
- `--refine-audit` reported the refinement as "below the outermost position of the
  declared type";
- the callee never assumed it (`r.v` as the subject of a postcondition was
  `unreflectable-subject`);
- no caller was obliged.

A separate gap: the hand-written named form, `fn f(r : {T | _.v > 0})`, reached the
callee's postcondition, but not a call's precondition inside the body (`need(r.v)` was
`solver-undecided`). The same refinement stored on `T`'s field did prove there.

## What landed

- **`lib/refinecheck/refine_anon.ml`** (`Refine_anon.lift`, run first in
  `Refine_check.check_module`):
  - It rewrites each such parameter to a refinement over a synthetic record type with the
    same fields, unrefined: `AnonRecord__<n>`, prepended to the module's declarations.
  - The refinement is the conjunction of the field predicates over `_.field`. The binder,
    `_` and the field's own name each denote the field, and a sibling field's name denotes
    that field, so `{ lo : Int, hi : {Int | _ > lo} }` is `_.hi > _.lo`.
  - Callers are then obliged, as for any record-typed refinement.
  - A record with no refined field, or with a refinement below a field's top level, is
    left alone.
- **`Refine_scope.collect_ctor_sigs`.** A synthetic type never takes a literal shape that a
  declared type already has, so literal typing elsewhere is unchanged.
- **`Refine_check.record_param_refinement_facts`.** A record parameter's own refinement is
  also a path fact over the parameter, beside its stored-field facts. It is retired on
  rebinding like them. This fixes the named form's call-site gap, and it is what the lifted
  form relies on.

## Tests

- `test_refinecheck` `stored-field-contract`, four new cases:
  - assumed (one field, a sibling field, a named binder);
  - obliged at the caller (`f({ v: 0 })` refuted, `f({ v: 2 })` proved);
  - a named `{T | _.v > 0}` at a call, and both forms retired by `let r = { v: 0 }`;
  - a declared type's literal is typed as before beside a same-shaped parameter.
- RED controls, each run and reverted:
  - without the lift, cases 5 and 7 fail;
  - without the path fact, cases 5 and 6 fail.
