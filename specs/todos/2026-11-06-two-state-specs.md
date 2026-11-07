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
