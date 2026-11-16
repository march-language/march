`[P3]` Two-state specs: `old(e)` in actor handler and migration contracts.

Medium step 7 of `2026-11-06-verification-ladder-roadmap`.

## Wanted

A handler's postcondition can relate the state after the message to the state before:

```march
on Deposit(n : {Int | _ > 0}) ensures state.balance == old(state.balance) + n do …
on Withdraw(n : Int) ensures state.balance <= old(state.balance) do …
```

and a migration contract can relate new state to old (`migrate_state` already has the old state
as a parameter; `old` gives the same thing in handler form).

## Builds on

The actor state as a record sort, reflected handlers (`<Actor>.step`,
`2026-11-06-actor-inductive-invariants`), and HCR's migration obligations. `old(e)` is the
handler's input state substituted into `e`.

## Done when

- `old` is accepted only in handler `ensures` (and documented as such), proved per handler, and a
  wrong handler is refused with the message and before/after states.
- `--guarantees` lists handler contracts beside invariants.

## Done (2026-11-09)

Handler guarantees landed for handlers; the migration half is not a separate feature:
`<actor>_migrate_state` already takes the old state as a parameter, so its result refinement
relates the two states directly, and `old` is refused there like anywhere outside a guarantee.

- **Syntax.** `on Msg(params) ensures P do … end` (`Ast.actor_handler.ah_ensures`). `ensures`
  is a soft keyword (`lib/parser/token_filter.ml`), promoted only before a token that can start
  its predicate (a name, a literal, `!`, `state`); formatter and tree-sitter grammar updated.
- **Meaning.** In `P`, `state` and the bare field names are the returned state, `old(e)` is `e`
  of the incoming state, and the message's parameters are in scope.
- **Proof** (`lib/refinecheck/refine_check.ml`, DActor arm step (5)). The handler is stated as
  a function from `state : {s : <Actor> | inv(s)}` (or a trivially refined state when there is
  no invariant, so a model is a counterexample) and its parameters, returning
  `{after : <Actor> | P'}`, and checked by `check_fn_post_verdict`: the same machinery as the
  `@invariant` (counterexamples, `cap verified` escalation, ledger row
  `<Actor>.<Msg>.ensures`). A parameter named like a field is renamed apart (a bare field name in
  a record refinement reads the field) and shown under its own name in a counterexample.
- **Message.** `post_subject` gained `ps_after`, which runs the counterexample's state and
  arguments through the body in the interpreter (display only, uncharged) so the message shows
  the state the handler returns, and `ps_rename`.
- **Placement** (`lib/desugar/two_state.ml`, `old_misuse`, explain page). `old(…)` in an
  `@invariant`, a state field's type, a message parameter's type or a function's type is refused,
  as is `old` without exactly one argument in a guarantee; a program defining its own `old`
  keeps it.
- **Report.** `--guarantees` prints `ensures on <Msg>` per guarantee (`bin/guarantees.ml`).
- **Tests.** Group `two-state` in `test_refinecheck` (`test/test_refine_two_state.ml`): proved
  guarantees (deposit/withdraw, a call handler's `state == old(state)`, bare fields, shadowing
  parameters, the invariant assumed on entry), violations with both states, every `old_misuse`
  form, `ensures` as an ordinary name, the formatter, and a program with guarantees that runs.
  Error-corpus case `old_misuse_1`.

Not covered: a guarantee about a call handler's reply value (a reply is an effect, not the
handler's result), and properties across several messages (the protocol todos).
